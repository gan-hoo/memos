import AVFoundation
import MapKit
import SwiftUI
import UIKit

// MARK: - 图片（异步缩略图 + 缓存）

private let thumbnailCache = NSCache<NSString, UIImage>()

struct MediaImage: View {
    let url: URL
    var maxPixel: CGFloat = 900

    @State private var image: UIImage?

    var body: some View {
        Color(.tertiarySystemFill)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: url) {
                let key = "\(url.lastPathComponent)@\(Int(maxPixel))" as NSString
                if let cached = thumbnailCache.object(forKey: key) {
                    image = cached
                    return
                }
                let path = url.path
                let limit = maxPixel
                let loaded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                    guard let full = UIImage(contentsOfFile: path) else { return nil }
                    let s = full.size
                    let scale = min(1, limit / max(s.width, s.height, 1))
                    return full.preparingThumbnail(of: CGSize(width: s.width * scale, height: s.height * scale)) ?? full
                }.value
                if let loaded {
                    thumbnailCache.setObject(loaded, forKey: key)
                    withAnimation(.easeOut(duration: 0.15)) { image = loaded }
                }
            }
    }
}

/// 卡片顶部的照片拼图：1 张铺满，2 张并排，3 张以上一大两小
struct PhotoMosaic: View {
    let urls: [URL]
    var height: CGFloat = 230
    var onTap: ((Int) -> Void)?

    var body: some View {
        Group {
            switch urls.count {
            case 0:
                EmptyView()
            case 1:
                cell(0)
            case 2:
                HStack(spacing: 2) { cell(0); cell(1) }
            default:
                HStack(spacing: 2) {
                    cell(0)
                    VStack(spacing: 2) {
                        cell(1)
                        cell(2)
                            .overlay {
                                if urls.count > 3 {
                                    ZStack {
                                        Color.black.opacity(0.35)
                                        Text("+\(urls.count - 3)")
                                            .font(.title2.bold())
                                            .foregroundStyle(.white)
                                    }
                                    .allowsHitTesting(false)
                                }
                            }
                    }
                }
            }
        }
        .frame(height: urls.isEmpty ? 0 : height)
    }

    private func cell(_ i: Int) -> some View {
        MediaImage(url: urls[i])
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { onTap?(i) }
    }
}

/// 全屏查看照片
struct PhotoViewer: View {
    let urls: [URL]
    @State var index: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(urls.indices, id: \.self) { i in
                    FullImage(url: urls[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never))
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .white.opacity(0.25))
            }
            .padding()
        }
    }
}

private struct FullImage: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: url) {
            let path = url.path
            image = await Task.detached { UIImage(contentsOfFile: path) }.value
        }
    }
}

// MARK: - 录音播放

@MainActor
final class AudioPlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayback()

    @Published private(set) var playingName: String?
    @Published private(set) var progress: Double = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(_ url: URL) {
        let name = url.lastPathComponent
        if playingName == name {
            stop()
            return
        }
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.delegate = self
        p.play()
        player = p
        playingName = name
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.player, p.duration > 0 else { return }
                self.progress = p.currentTime / p.duration
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        playingName = nil
        progress = 0
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}

struct AudioChip: View {
    let url: URL
    let duration: TimeInterval
    var onDelete: (() -> Void)?

    @ObservedObject private var playback = AudioPlayback.shared

    private var isPlaying: Bool { playback.playingName == url.lastPathComponent }

    var body: some View {
        HStack(spacing: 12) {
            Button { playback.toggle(url) } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.accentColor))
            }
            .buttonStyle(.plain)

            WaveformBars(progress: isPlaying ? playback.progress : 0, seed: url.lastPathComponent.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) })
                .frame(height: 24)

            Text(Fmt.duration(duration))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)

            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// 装饰性的波形条，播放时按进度着色
struct WaveformBars: View {
    var progress: Double
    var seed: Int
    var count = 32

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<count, id: \.self) { i in
                    let h = height(i)
                    Capsule()
                        .fill(Double(i) / Double(count) < progress ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: max(1, (geo.size.width - CGFloat(count - 1) * 2) / CGFloat(count)),
                               height: max(3, geo.size.height * h))
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func height(_ i: Int) -> CGFloat {
        var x = UInt64(bitPattern: Int64(seed &+ i &* 7919))
        x ^= x >> 33; x &*= 0xff51afd7ed558ccd; x ^= x >> 33
        return 0.25 + CGFloat(x % 1000) / 1000 * 0.75
    }
}

// MARK: - 地点

struct LocationCard: View {
    let attachment: Attachment
    var height: CGFloat = 120
    var onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lat = attachment.latitude, let lon = attachment.longitude {
                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                Map(initialPosition: .region(MKCoordinateRegion(center: coord, latitudinalMeters: 900, longitudinalMeters: 900)),
                    interactionModes: []) {
                    Marker(attachment.placeName ?? "", coordinate: coord)
                        .tint(Color.accentColor)
                }
                .frame(height: height)
                .allowsHitTesting(false)
            }
            HStack {
                Label(attachment.placeName ?? "未知地点", systemImage: "mappin.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - 相机 / 分享

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
