import PhotosUI
import SwiftUI

/// 新建 / 编辑日记
struct ComposerView: View {
    let original: Entry
    let isNew: Bool

    @EnvironmentObject private var store: JournalStore
    @Environment(\.dismiss) private var dismiss

    @State private var entry: Entry
    /// 本次编辑新加的文件，取消时删除
    @State private var addedFiles: [String] = []

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showDatePicker = false
    @State private var showPrompts = false
    @State private var showRecorder = false
    @State private var showCamera = false
    @State private var showDiscard = false
    @State private var locating = false
    @State private var viewer: ViewerTarget?
    @State private var errorText: String?
    @StateObject private var locationFetcher = LocationFetcher()
    @FocusState private var focus: Field?

    enum Field { case title, body }

    struct ViewerTarget: Identifiable {
        let id = UUID()
        let index: Int
    }

    init(entry: Entry, isNew: Bool) {
        original = entry
        self.isNew = isNew
        _entry = State(initialValue: entry)
    }

    private var isDirty: Bool { entry != original }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let prompt = entry.prompt {
                        promptBanner(prompt)
                    }
                    photosGrid
                    ForEach(entry.audios) { a in
                        if let name = a.fileName {
                            AudioChip(url: store.mediaURL(name), duration: a.duration ?? 0) { remove(a) }
                        }
                    }
                    if let loc = entry.location {
                        LocationCard(attachment: loc, height: 110) { remove(loc) }
                    }
                    if locating {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("正在获取位置…").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }

                    TextField("标题", text: $entry.title, axis: .vertical)
                        .font(.title2.bold())
                        .focused($focus, equals: .title)
                        .submitLabel(.next)
                        .onSubmit { focus = .body }

                    TextField("开始书写…", text: $entry.body, axis: .vertical)
                        .font(.body)
                        .lineSpacing(5)
                        .focused($focus, equals: .body)
                        .frame(minHeight: 260, alignment: .top)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        if isDirty && !(isNew && entry.isEmpty) { showDiscard = true } else { cancel() }
                    }
                }
                ToolbarItem(placement: .principal) {
                    Button { showDatePicker = true } label: {
                        VStack(spacing: 0) {
                            Text(Fmt.relativeDay(entry.date)).font(.headline)
                            Text(Fmt.full(entry.date)).font(.caption2).foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.primary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { save() }.bold()
                }
                ToolbarItemGroup(placement: .bottomBar) { attachmentButtons }
                ToolbarItemGroup(placement: .keyboard) { attachmentButtons }
            }
            .confirmationDialog("放弃更改？", isPresented: $showDiscard, titleVisibility: .visible) {
                Button("放弃更改", role: .destructive) { cancel() }
                Button("继续编辑", role: .cancel) {}
            }
            .sheet(isPresented: $showDatePicker) { datePickerSheet }
            .sheet(isPresented: $showPrompts) {
                PromptPickerView { prompt in
                    entry.prompt = prompt
                    focus = .body
                }
            }
            .sheet(isPresented: $showRecorder) {
                RecorderSheet { url, duration in
                    if let name = store.storeAudio(from: url) {
                        addedFiles.append(name)
                        entry.attachments.append(Attachment(kind: .audio, fileName: name, duration: duration))
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in addImage(image) }
                    .ignoresSafeArea()
            }
            .fullScreenCover(item: $viewer) { t in
                PhotoViewer(urls: entry.photos.compactMap { $0.fileName.map(store.mediaURL) }, index: t.index)
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let name = store.storeImage(data: data) {
                            addedFiles.append(name)
                            entry.attachments.append(Attachment(kind: .photo, fileName: name))
                        }
                    }
                    photoItems = []
                }
            }
            .alert("提示", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
            .onAppear {
                if isNew && entry.prompt == nil { focus = .body }
            }
        }
        .interactiveDismissDisabled(isDirty)
    }

    // MARK: - 组件

    private func promptBanner(_ prompt: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
            Text(prompt)
                .font(.callout.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { entry.prompt = nil } label: {
                Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var photosGrid: some View {
        let photos = entry.photos
        if !photos.isEmpty {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: photos.count == 1 ? 1 : 3),
                      spacing: 6) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { i, p in
                    if let name = p.fileName {
                        MediaImage(url: store.mediaURL(name))
                            .aspectRatio(photos.count == 1 ? 4 / 3 : 1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Button { remove(p) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.45))
                                }
                                .padding(5)
                            }
                            .onTapGesture { viewer = ViewerTarget(index: i) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var attachmentButtons: some View {
        Button { showPrompts = true } label: { Image(systemName: "sparkles") }
            .accessibilityLabel("写作提示")
        Spacer()
        PhotosPicker(selection: $photoItems, maxSelectionCount: 20, matching: .images) {
            Image(systemName: "photo.on.rectangle")
        }
        .accessibilityLabel("照片")
        Spacer()
        Button {
            if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true } else { errorText = "此设备没有可用的相机" }
        } label: { Image(systemName: "camera") }
            .accessibilityLabel("拍照")
        Spacer()
        Button { showRecorder = true } label: { Image(systemName: "waveform") }
            .accessibilityLabel("录音")
        Spacer()
        Button { addLocation() } label: { Image(systemName: entry.location == nil ? "location" : "location.fill") }
            .accessibilityLabel("地点")
            .disabled(locating)
        Spacer()
        Button { entry.isBookmarked.toggle() } label: {
            Image(systemName: entry.isBookmarked ? "bookmark.fill" : "bookmark")
        }
        .accessibilityLabel("收藏")
    }

    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker("日期", selection: $entry.date, in: ...Date.now.addingTimeInterval(86_400 * 365))
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("日记日期")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("完成") { showDatePicker = false } }
                }
        }
        .environment(\.locale, Fmt.locale)
        .presentationDetents([.medium, .large])
    }

    // MARK: - 操作

    private func addImage(_ image: UIImage) {
        if let name = store.storeImage(image) {
            addedFiles.append(name)
            entry.attachments.append(Attachment(kind: .photo, fileName: name))
        }
    }

    private func addLocation() {
        locating = true
        Task {
            defer { locating = false }
            do {
                let loc = try await locationFetcher.fetch()
                entry.attachments.removeAll { $0.kind == .location }
                entry.attachments.append(loc)
            } catch is CancellationError {
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func remove(_ a: Attachment) {
        entry.attachments.removeAll { $0.id == a.id }
        // 本次新加的文件直接删；原有文件等保存时再删，取消时还能恢复
        if let name = a.fileName, let i = addedFiles.firstIndex(of: name) {
            if AudioPlayback.shared.playingName == name { AudioPlayback.shared.stop() }
            addedFiles.remove(at: i)
            store.removeFiles([name])
        }
    }

    private func save() {
        AudioPlayback.shared.stop()
        if entry.isEmpty {
            if !isNew { store.delete(original) }
            dismiss()
            return
        }
        let kept = Set(entry.attachments.compactMap(\.fileName))
        let removed = original.attachments.compactMap(\.fileName).filter { !kept.contains($0) }
        store.removeFiles(removed)
        store.save(entry)
        dismiss()
    }

    private func cancel() {
        AudioPlayback.shared.stop()
        store.removeFiles(addedFiles)
        dismiss()
    }
}

/// 选择写作提示
struct PromptPickerView: View {
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Prompts.categories) { cat in
                    Section {
                        ForEach(cat.prompts, id: \.self) { p in
                            Button {
                                onPick(p)
                                dismiss()
                            } label: {
                                Text(p).foregroundStyle(.primary)
                            }
                        }
                    } header: {
                        Label(cat.id, systemImage: cat.icon)
                    }
                }
            }
            .navigationTitle("写作提示")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
        }
    }
}
