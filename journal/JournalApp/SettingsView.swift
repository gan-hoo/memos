import LocalAuthentication
import SwiftUI
import UserNotifications

// MARK: - 锁定

@MainActor
final class AppLock: ObservableObject {
    @Published var isLocked: Bool

    static let enabledKey = "lockEnabled"
    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    init() {
        isLocked = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    func lockIfNeeded() {
        if enabled { isLocked = true }
    }

    func unlock() async {
        if await Self.authenticate(reason: "解锁你的日记") { isLocked = false }
    }

    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // 设备没有设置密码时无法锁定，直接放行
            return true
        }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    static var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "面容 ID"
        case .touchID: return "触控 ID"
        case .opticID: return "Optic ID"
        default: return "密码"
        }
    }
}

struct LockView: View {
    @EnvironmentObject private var lock: AppLock
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
                Text("日记已锁定").font(.title3.bold())
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Text("使用\(AppLock.biometryName)解锁").bold().padding(.horizontal, 16)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .task {
            if scenePhase == .active { await lock.unlock() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await lock.unlock() } }
        }
    }
}

// MARK: - 提醒

enum Reminder {
    static let id = "daily-journal"

    static func schedule(at time: Date) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }
        center.removePendingNotificationRequests(withIdentifiers: [id])
        let content = UNMutableNotificationContent()
        content.title = "记录今天的片刻"
        content.body = Prompts.ofTheDay()
        content.sound = .default
        let comps = Fmt.calendar.dateComponents([.hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        do {
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            return true
        } catch {
            return false
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}

// MARK: - 设置页

struct SettingsView: View {
    @EnvironmentObject private var store: JournalStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppLock.enabledKey) private var lockEnabled = false
    @AppStorage("reminderEnabled") private var reminderEnabled = false
    @AppStorage("reminderTime") private var reminderTime: Double = {
        Fmt.calendar.date(bySettingHour: 21, minute: 0, second: 0, of: Date())!.timeIntervalSinceReferenceDate
    }()

    @State private var share: SharePayload?
    @State private var message: String?

    private var timeBinding: Binding<Date> {
        Binding(get: { Date(timeIntervalSinceReferenceDate: reminderTime) },
                set: { reminderTime = $0.timeIntervalSinceReferenceDate })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: Binding(get: { reminderEnabled }, set: { setReminder($0) })) {
                        Label("每日提醒", systemImage: "bell")
                    }
                    if reminderEnabled {
                        DatePicker("提醒时间", selection: timeBinding, displayedComponents: .hourAndMinute)
                            .onChange(of: reminderTime) { _, _ in
                                Task { _ = await Reminder.schedule(at: timeBinding.wrappedValue) }
                            }
                    }
                } footer: {
                    Text("每天在设定的时间提醒你写日记，并附上一个写作提示。")
                }

            }
            .environment(\.locale, Fmt.locale)
            .navigationTitle("通知")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .sheet(item: $share) { ShareSheet(items: $0.items) }
            .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func setLock(_ on: Bool) {
        Task {
            // 开关都需要验证一次，防止别人随手关掉
            if await AppLock.authenticate(reason: on ? "开启日记锁定" : "关闭日记锁定") {
                lockEnabled = on
            }
        }
    }

    private func setReminder(_ on: Bool) {
        if on {
            Task {
                if await Reminder.schedule(at: timeBinding.wrappedValue) {
                    reminderEnabled = true
                } else {
                    message = "没有通知权限，请在「设置 → 通知 → 片刻」中允许。"
                }
            }
        } else {
            Reminder.cancel()
            reminderEnabled = false
        }
    }
}
