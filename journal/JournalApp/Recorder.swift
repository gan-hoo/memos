import AVFoundation
import SwiftUI

@MainActor
final class Recorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var hasStarted = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0.04, count: 48)
    @Published var permissionDenied = false

    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    func toggle() async {
        if isRecording { pause() } else if hasStarted { resume() } else { await start() }
    }

    private func start() async {
        guard await AVAudioApplication.requestRecordPermission() else {
            permissionDenied = true
            return
        }
        AudioPlayback.shared.stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        guard let r = try? AVAudioRecorder(url: url, settings: settings) else { return }
        r.isMeteringEnabled = true
        r.record()
        recorder = r
        hasStarted = true
        isRecording = true
        startTimer()
    }

    private func pause() {
        recorder?.pause()
        isRecording = false
        timer?.invalidate()
    }

    private func resume() {
        recorder?.record()
        isRecording = true
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let r = recorder, r.isRecording else { return }
        r.updateMeters()
        elapsed = r.currentTime
        let level = CGFloat(pow(10, r.averagePower(forChannel: 0) / 20))
        levels.append(min(1, max(0.04, level * 2.2)))
        levels.removeFirst()
    }

    /// 结束录音，返回文件和时长
    func finish() -> (URL, TimeInterval)? {
        timer?.invalidate()
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard hasStarted, let p = try? AVAudioPlayer(contentsOf: url), p.duration > 0.3 else {
            discard()
            return nil
        }
        return (url, p.duration)
    }

    func discard() {
        timer?.invalidate()
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? FileManager.default.removeItem(at: url)
    }
}

struct RecorderSheet: View {
    var onFinish: (URL, TimeInterval) -> Void
    @StateObject private var recorder = Recorder()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Button("取消") {
                    recorder.discard()
                    dismiss()
                }
                Spacer()
                Text("录音").font(.headline)
                Spacer()
                Button("完成") {
                    if let result = recorder.finish() { onFinish(result.0, result.1) }
                    dismiss()
                }
                .bold()
                .disabled(!recorder.hasStarted)
            }

            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(recorder.levels.enumerated()), id: \.offset) { _, l in
                    Capsule()
                        .fill(recorder.isRecording ? Color.accentColor : Color.secondary.opacity(0.4))
                        .frame(width: 3, height: max(4, 70 * l))
                }
            }
            .frame(height: 74)
            .animation(.linear(duration: 0.05), value: recorder.levels)

            Text(Fmt.duration(recorder.elapsed))
                .font(.system(size: 40, weight: .light).monospacedDigit())

            Button {
                Task { await recorder.toggle() }
            } label: {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.35), lineWidth: 4).frame(width: 74, height: 74)
                    if recorder.isRecording {
                        RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 28, height: 28)
                    } else {
                        Circle().fill(.red).frame(width: 60, height: 60)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recorder.isRecording ? "暂停" : "录音")

            if recorder.permissionDenied {
                Text("没有麦克风权限，请在「设置」中允许。")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .interactiveDismissDisabled(recorder.hasStarted)
        .presentationDetents([.height(360)])
    }
}
