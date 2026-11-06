import PencilKit
import PhotosUI
import SwiftUI

/// 日记编辑页（导航推入，返回或点 ✓ 时自动保存）
struct EntryEditorView: View {
    let original: Entry

    @EnvironmentObject private var store: JournalStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var entry: Entry
    @State private var text: NSAttributedString
    @StateObject private var rich = RichTextController()
    @StateObject private var locationFetcher = LocationFetcher()

    @State private var addedFiles: [String] = []
    @State private var deleted = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var sheet: SheetKind?
    @State private var viewer: ViewerTarget?
    @State private var showDeleteConfirm = false
    @State private var locating = false
    @State private var errorText: String?
    @FocusState private var titleFocused: Bool

    enum SheetKind: String, Identifiable {
        case format, prompts, recorder, camera, drawing, mood, date
        var id: String { rawValue }
    }

    struct ViewerTarget: Identifiable {
        let id = UUID()
        let index: Int
    }

    init(entry: Entry) {
        original = entry
        _entry = State(initialValue: entry)
        _text = State(initialValue: RichTextController.decode(entry.richText, fallback: entry.body))
    }

    private var titleHidden: Bool { entry.titleHidden ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                dateLine
                if let prompt = entry.prompt { promptBanner(prompt) }
                if let m = entry.mood.flatMap(Mood.init(rawValue:)) { moodChip(m) }
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

                if !titleHidden {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("标题", text: $entry.title, axis: .vertical)
                            .font(.title3.weight(.semibold))
                            .focused($titleFocused)
                        Divider()
                    }
                }

                RichTextEditor(text: $text, controller: rich, placeholder: "开始记录…")
            }
            .padding(.horizontal, 26)
            .padding(.top, 6)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .bottom) {
            attachmentBar
                .padding(.bottom, 6)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(item: $sheet) { kind in sheetView(kind) }
        .fullScreenCover(item: $viewer) { t in
            PhotoViewer(urls: entry.photos.compactMap { $0.fileName.map(store.mediaURL) }, index: t.index)
        }
        .confirmationDialog("删除这篇日记？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) { deleteEntry() }
        } message: {
            Text("删除后无法恢复。")
        }
        .alert("提示", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { commit() }
        }
        .onAppear {
            if store.entry(entry.id) == nil && entry.title.isEmpty && !titleHidden { titleFocused = true }
        }
        .onDisappear { commit() }
    }

    // MARK: - 顶部

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { sheet = .format } label: { Text("格式") }
            Button { sheet = .drawing } label: { Image(systemName: "pencil.tip.crop.circle") }
                .accessibilityLabel("绘图")
        }
        ToolbarItem(placement: .topBarTrailing) { moreMenu }
        ToolbarItem(placement: .confirmationAction) {
            Button { dismiss() } label: { Image(systemName: "checkmark") }
                .prominentGlassButton()
                .accessibilityLabel("完成")
        }
    }

    private var moreMenu: some View {
        Menu {
            Section {
                Button { sheet = .date } label: {
                    Label { Text("日记日期"); Text(Fmt.day(entry.date)) } icon: { Image(systemName: "calendar") }
                }
            }
            Section {
                Picker(selection: Binding(get: { entry.journalID ?? store.defaultJournalID },
                                          set: { entry.journalID = $0 })) {
                    ForEach(store.journals) { j in
                        Label(j.name, systemImage: j.icon).tag(j.id)
                    }
                } label: {
                    Label {
                        Text("选取日记本")
                        Text(store.journal(entry.journalID)?.name ?? "")
                    } icon: { Image(systemName: "square.stack") }
                }
                .pickerStyle(.menu)
            }
            Section {
                Button { entry.isBookmarked.toggle() } label: {
                    Label(entry.isBookmarked ? "移除书签" : "添加书签",
                          systemImage: entry.isBookmarked ? "bookmark.slash" : "bookmark")
                }
                Button {
                    entry.titleHidden = !titleHidden
                    if entry.titleHidden == true { entry.title = "" }
                } label: {
                    Label(titleHidden ? "添加标题" : "移除标题",
                          systemImage: titleHidden ? "textformat" : "rectangle.slash")
                }
                Button { rich.find() } label: { Label("在日记中查找", systemImage: "magnifyingglass") }
                Button(role: .destructive) { showDeleteConfirm = true } label: { Label("删除", systemImage: "trash") }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("更多")
    }

    private var dateLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
            Text("\(Fmt.short(entry.date)) \(Fmt.time(entry.date))")
            Text("·")
            Button("编辑") { sheet = .date }
                .foregroundStyle(Color.accentColor)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 底部附件栏

    private var attachmentBar: some View {
        HStack(spacing: 0) {
            barButton("wand.and.sparkles", "写作建议") { sheet = .prompts }
            PhotosPicker(selection: $photoItems, maxSelectionCount: 20, matching: .images) {
                barIcon("photo.on.rectangle.angled")
            }
            .accessibilityLabel("照片")
            barButton("camera", "拍照") {
                if UIImagePickerController.isSourceTypeAvailable(.camera) { sheet = .camera } else { errorText = "此设备没有可用的相机" }
            }
            barButton("waveform", "录音") { sheet = .recorder }
            barButton(entry.location == nil ? "location" : "location.fill", "地点") { addLocation() }
                .disabled(locating)
            barButton("fireworks", "心情") { sheet = .mood }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .glassCapsule()
        .padding(.horizontal, 30)
    }

    private func barIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 21))
            .frame(maxWidth: .infinity, minHeight: 46)
            .contentShape(Rectangle())
    }

    private func barButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { barIcon(icon) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }

    // MARK: - 内容组件

    private func promptBanner(_ prompt: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wand.and.sparkles").foregroundStyle(Color.accentColor)
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

    private func moodChip(_ m: Mood) -> some View {
        Button { sheet = .mood } label: {
            HStack(spacing: 6) {
                Text(m.emoji)
                Text(m.title).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(m.color.opacity(0.18), in: Capsule())
        }
        .buttonStyle(.plain)
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
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    // MARK: - 弹出面板

    @ViewBuilder
    private func sheetView(_ kind: SheetKind) -> some View {
        switch kind {
        case .format:
            FormatPanel(controller: rich)
        case .prompts:
            PromptPickerView { entry.prompt = $0 }
        case .recorder:
            RecorderSheet { url, duration in
                if let name = store.storeAudio(from: url) {
                    addedFiles.append(name)
                    entry.attachments.append(Attachment(kind: .audio, fileName: name, duration: duration))
                }
            }
        case .camera:
            CameraPicker { addImage($0) }.ignoresSafeArea()
        case .drawing:
            DrawingSheet { addImage($0) }
        case .mood:
            MoodPicker(selection: Binding(get: { entry.mood.flatMap(Mood.init(rawValue:)) },
                                          set: { entry.mood = $0?.rawValue }))
        case .date:
            NavigationStack {
                DatePicker("日期", selection: $entry.date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("日记日期")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("完成") { sheet = nil } }
                    }
            }
            .environment(\.locale, Fmt.locale)
            .presentationDetents([.large])
        }
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
        if let name = a.fileName, let i = addedFiles.firstIndex(of: name) {
            if AudioPlayback.shared.playingName == name { AudioPlayback.shared.stop() }
            addedFiles.remove(at: i)
            store.removeFiles([name])
        }
    }

    private func deleteEntry() {
        deleted = true
        AudioPlayback.shared.stop()
        store.delete(entry)
        store.removeFiles(addedFiles)
        dismiss()
    }

    /// 保存当前内容（空日记不保存）
    private func commit() {
        guard !deleted else { return }
        AudioPlayback.shared.stop()
        var e = entry
        e.body = text.string
        e.richText = RichTextController.encode(text)
        if e.journalID == nil { e.journalID = store.defaultJournalID }
        if e.isEmpty {
            if store.entry(e.id) != nil { store.delete(e) }
            store.removeFiles(addedFiles)
            addedFiles = []
            return
        }
        let kept = Set(e.attachments.compactMap(\.fileName))
        store.removeFiles(original.attachments.compactMap(\.fileName).filter { !kept.contains($0) })
        store.save(e)
    }
}

// MARK: - 心情

struct MoodPicker: View {
    @Binding var selection: Mood?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(Mood.allCases) { m in
                    Button {
                        selection = m
                        dismiss()
                    } label: {
                        VStack(spacing: 8) {
                            Text(m.emoji).font(.system(size: 40))
                            Text(m.title).font(.footnote.weight(.medium)).foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 100)
                        .background(m.color.opacity(selection == m ? 0.35 : 0.14),
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            if selection == m {
                                RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(m.color, lineWidth: 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .navigationTitle("此刻的心情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if selection != nil {
                        Button("清除") {
                            selection = nil
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .presentationDetents([.height(330)])
    }
}

// MARK: - 写作建议

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
            .navigationTitle("写作建议")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 绘图

struct DrawingSheet: View {
    var onSave: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var canvas = PKCanvasView()

    var body: some View {
        NavigationStack {
            CanvasView(canvas: canvas)
                .background(Color.white)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("绘图")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            if let img = render() { onSave(img) }
                            dismiss()
                        }
                        .bold()
                    }
                }
        }
        .interactiveDismissDisabled()
    }

    private func render() -> UIImage? {
        let drawing = canvas.drawing
        guard !drawing.strokes.isEmpty else { return nil }
        let bounds = drawing.bounds.insetBy(dx: -24, dy: -24)
        var ink: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = drawing.image(from: bounds, scale: 2)
        }
        guard let ink else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2
        return UIGraphicsImageRenderer(size: bounds.size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: bounds.size))
            ink.draw(in: CGRect(origin: .zero, size: bounds.size))
        }
    }
}

private struct CanvasView: UIViewRepresentable {
    let canvas: PKCanvasView

    func makeCoordinator() -> PKToolPicker { PKToolPicker() }

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        let picker = context.coordinator
        picker.overrideUserInterfaceStyle = .light
        picker.addObserver(canvas)
        picker.setVisible(true, forFirstResponder: canvas)
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }

    func updateUIView(_ view: PKCanvasView, context: Context) {}
}
