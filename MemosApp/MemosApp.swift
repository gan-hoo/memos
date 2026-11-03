import SwiftUI

@main
struct MemosApp: App {
    @StateObject private var server = LocalServer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(server)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var server: LocalServer
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch server.state {
            case .starting:
                VStack(spacing: 16) {
                    Image(systemName: "note.text")
                        .font(.system(size: 56))
                        .foregroundColor(.accentColor)
                    ProgressView("正在启动 Memos…")
                }
            case .failed(let message):
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 44))
                        .foregroundColor(.orange)
                    Text("Memos 启动失败").font(.headline)
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重试") { server.start() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(32)
            case .ready(let session):
                BrowserView(session: session)
                    .id(session.id)
            }
        }
        .onAppear { server.start() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { server.ensureAlive() }
        }
    }
}
