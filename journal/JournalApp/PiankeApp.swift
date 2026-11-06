import SwiftUI

@main
struct PiankeApp: App {
    @StateObject private var store = JournalStore()
    @StateObject private var lock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                HomeView()
                if lock.isLocked {
                    LockView()
                        .transition(.opacity)
                } else if scenePhase != .active && lock.enabled {
                    // 多任务切换界面中隐藏内容
                    Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
                }
            }
            .animation(.easeInOut(duration: 0.2), value: lock.isLocked)
            .environmentObject(store)
            .environmentObject(lock)
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    lock.lockIfNeeded()
                    AudioPlayback.shared.stop()
                }
            }
        }
    }
}
