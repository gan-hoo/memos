import SwiftUI

@main
struct MemosApp: App {
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
        }
    }
}

/// Persists the Memos server address.
final class AppSettings: ObservableObject {
    private static let serverKey = "memos.serverURL"

    @Published var serverURL: URL? {
        didSet { UserDefaults.standard.set(serverURL?.absoluteString, forKey: Self.serverKey) }
    }

    init() {
        if let s = UserDefaults.standard.string(forKey: Self.serverKey), let url = URL(string: s) {
            serverURL = url
        }
    }

    /// Turns user input like "memos.example.com" or "192.168.1.2:5230" into a full URL.
    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "https://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}

struct RootView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        if let url = settings.serverURL {
            BrowserView(serverURL: url)
                .id(url)
        } else {
            ServerSetupView()
        }
    }
}
