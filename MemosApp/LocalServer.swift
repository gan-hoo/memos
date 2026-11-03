import Foundation
import WebKit
import Memosmobile

/// What the web view needs to open the embedded Memos instance.
struct WebSession {
    let id = UUID()
    let baseURL: URL
    /// JavaScript injected at document start (seeds the access token after an automatic sign-in).
    let bootstrapScript: String?
}

/// Runs the embedded Memos server (Go, compiled with gomobile) on 127.0.0.1
/// and signs into a local account automatically, so no external server or
/// manual login is needed.
@MainActor
final class LocalServer: ObservableObject {
    enum State {
        case starting
        case ready(WebSession)
        case failed(String)
    }

    @Published private(set) var state: State = .starting
    /// Bumped whenever the server had to be restarted (e.g. after iOS suspended the app).
    @Published private(set) var restartCount = 0

    private(set) var port = 0
    private var isStarting = false

    static let preferredPorts = Array(25230...25250)
    private static let lastPortKey = "memos.localPort"

    /// Notes database lives in Documents so it is visible (and backup-able) in the Files app.
    static var dataDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }
    var version: String { MemosmobileVersion() }

    func start(forceSignIn: Bool = false) {
        guard !isStarting else { return }
        isStarting = true
        state = .starting
        let dataDir = Self.dataDirectory.path
        let lastPort = UserDefaults.standard.integer(forKey: Self.lastPortKey)
        let runningPort = self.port
        var candidates = Self.preferredPorts
        for preferred in [lastPort, runningPort] where preferred != 0 {
            candidates.removeAll { $0 == preferred }
            candidates.insert(preferred, at: 0)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var chosen = 0
            var lastError = "没有可用端口"
            for p in candidates where p == runningPort || MemosmobilePortAvailable(p) {
                let err = MemosmobileStart(dataDir, p)
                if err.isEmpty { chosen = p; break }
                lastError = err
            }
            Task { @MainActor in
                guard chosen != 0 else {
                    self.isStarting = false
                    self.state = .failed(lastError)
                    return
                }
                let portChanged = chosen != lastPort
                self.port = chosen
                UserDefaults.standard.set(chosen, forKey: Self.lastPortKey)
                Task {
                    let script = await LocalAuth.prepare(baseURL: self.baseURL,
                                                         forceSignIn: forceSignIn || portChanged)
                    self.isStarting = false
                    self.state = .ready(WebSession(baseURL: self.baseURL, bootstrapScript: script))
                }
            }
        }
    }

    /// iOS may tear down the listening socket while the app is suspended; bring it back.
    func ensureAlive() {
        guard case .ready = state, !isStarting else { return }
        let dataDir = Self.dataDirectory.path
        let port = self.port
        DispatchQueue.global(qos: .userInitiated).async {
            guard !MemosmobileIsAlive() else { return }
            MemosmobileStop()
            let err = MemosmobileStart(dataDir, port)
            Task { @MainActor in
                if err.isEmpty { self.restartCount += 1 } else { self.start() }
            }
        }
    }

    /// Re-run the automatic sign-in (e.g. after signing out in the web UI).
    func signInAgain() {
        start(forceSignIn: true)
    }
}
