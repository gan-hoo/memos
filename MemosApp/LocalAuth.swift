import Foundation
import WebKit

/// Credentials of the single on-device Memos account. Stored next to (not inside)
/// the Files-visible Documents folder.
struct LocalAccount: Codable {
    var username: String
    var password: String

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("local-account.json")
    }

    static func loadOrCreate() -> LocalAccount {
        if let data = try? Data(contentsOf: fileURL),
           let account = try? JSONDecoder().decode(LocalAccount.self, from: data) {
            return account
        }
        var bytes = [UInt8](repeating: 0, count: 18)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let password = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        let account = LocalAccount(username: "me", password: password)
        if let data = try? JSONEncoder().encode(account) {
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        return account
    }
}

enum LocalAuth {
    private static let refreshCookie = "memos_refresh"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    /// Makes sure the local account exists and the web view is signed in.
    /// Returns a document-start script to seed the web app's token, or nil when
    /// the existing web session is still valid (or automatic sign-in failed and
    /// the regular Memos login page should be shown instead).
    @MainActor
    static func prepare(baseURL: URL, forceSignIn: Bool) async -> String? {
        let account = LocalAccount.loadOrCreate()
        do {
            try await ensureAccount(baseURL: baseURL, account: account)
            let store = WKWebsiteDataStore.default().httpCookieStore
            if !forceSignIn, await hasValidRefreshCookie(store) {
                return nil
            }
            return try await signIn(baseURL: baseURL, account: account, store: store)
        } catch {
            NSLog("Memos auto sign-in failed: \(error)")
            return nil
        }
    }

    private static func ensureAccount(baseURL: URL, account: LocalAccount) async throws {
        let (data, _) = try await session.data(from: baseURL.appendingPathComponent("api/v1/instance/profile"))
        let profile = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard profile?["needsSetup"] as? Bool == true else { return }

        var req = URLRequest(url: baseURL.appendingPathComponent("api/v1/users"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "username": account.username,
            "password": account.password,
            "displayName": "我",
        ])
        let (_, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }

    @MainActor
    private static func hasValidRefreshCookie(_ store: WKHTTPCookieStore) async -> Bool {
        let cookies: [HTTPCookie] = await withCheckedContinuation { cont in
            store.getAllCookies { cont.resume(returning: $0) }
        }
        let soon = Date().addingTimeInterval(2 * 24 * 3600)
        return cookies.contains { c in
            c.name == refreshCookie && c.domain.contains("127.0.0.1") && (c.expiresDate ?? .distantPast) > soon
        }
    }

    @MainActor
    private static func signIn(baseURL: URL, account: LocalAccount, store: WKHTTPCookieStore) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/v1/auth/signin"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "passwordCredentials": ["username": account.username, "password": account.password],
        ])
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["accessToken"] as? String,
              let expires = json["accessTokenExpiresAt"] as? String
        else { throw URLError(.userAuthenticationRequired) }

        // The REST gateway relays the cookie as Grpc-Metadata-Set-Cookie.
        let rawCookie = http.value(forHTTPHeaderField: "Set-Cookie")
            ?? http.value(forHTTPHeaderField: "Grpc-Metadata-Set-Cookie")
        if let raw = rawCookie {
            for cookie in HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": raw], for: baseURL) {
                await withCheckedContinuation { cont in
                    store.setCookie(cookie) { cont.resume() }
                }
            }
        }

        let nonce = UUID().uuidString
        func js(_ s: String) -> String {
            let data = try? JSONSerialization.data(withJSONObject: [s])
            let arr = String(data: data ?? Data("[\"\"]".utf8), encoding: .utf8) ?? "[\"\"]"
            return String(arr.dropFirst().dropLast())
        }
        return """
        (function() {
          try {
            if (localStorage.getItem("memos_ios_login") === \(js(nonce))) return;
            localStorage.setItem("memos_access_token", \(js(token)));
            localStorage.setItem("memos_token_expires_at", new Date(\(js(expires))).toISOString());
            localStorage.setItem("memos_ios_login", \(js(nonce)));
          } catch (e) {}
        })();
        """
    }
}
