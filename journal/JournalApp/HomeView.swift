import MapKit
import SwiftUI

enum Route: Hashable {
    case journal(UUID?)
    case editor(Entry)
    case insights
    case places
}

// MARK: - 首页

struct RootView: View {
    @EnvironmentObject private var store: JournalStore
    @EnvironmentObject private var lock: AppLock

    @State private var path: [Route] = []
    @State private var editMode: EditMode = .inactive
    @State private var journalSheet: JournalSheetTarget?
    @State private var pendingDelete: Journal?
    @State private var showNotifications = false
    @State private var share: SharePayload?
    @AppStorage(AppLock.enabledKey) private var lockEnabled = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button { path.append(.insights) } label: { InsightsCard() }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section {
                    Button { path.append(.places) } label: { PlacesCard() }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section {
                    NavigationLink(value: Route.journal(nil)) {
                        JournalRow(icon: "square.grid.3x3", color: .secondary, name: "所有日记", count: store.entries.count)
                    }
                    .moveDisabled(true)
                    .deleteDisabled(true)

                    ForEach(store.journals) { j in
                        NavigationLink(value: Route.journal(j.id)) {
                            JournalRow(icon: j.icon, color: Palette.color(j.colorIndex), name: j.name,
                                       count: store.entries(in: j.id).count)
                        }
                        .swipeActions {
                            if store.journals.count > 1 {
                                Button(role: .destructive) { pendingDelete = j } label: { Label("删除", systemImage: "trash") }
                            }
                            Button { journalSheet = JournalSheetTarget(journal: j) } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.gray)
                        }
                        .contextMenu {
                            Button { journalSheet = JournalSheetTarget(journal: j) } label: { Label("编辑日记本", systemImage: "pencil") }
                            if store.journals.count > 1 {
                                Button(role: .destructive) { pendingDelete = j } label: { Label("删除日记本", systemImage: "trash") }
                            }
                        }
                    }
                    .onMove { store.moveJournals(from: $0, to: $1) }
                    .deleteDisabled(true)
                } header: {
                    HStack {
                        Text("日记本")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button { journalSheet = JournalSheetTarget(journal: nil) } label: {
                            Image(systemName: "plus")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color(.tertiarySystemFill)))
                        }
                        .accessibilityLabel("新建日记本")
                    }
                    .textCase(nil)
                    .padding(.bottom, 4)
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(18)
            .environment(\.editMode, $editMode)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if editMode.isEditing {
                        Button("完成") { withAnimation { editMode = .inactive } }.bold()
                    } else {
                        menu
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .journal(let id):
                    JournalEntriesView(journalID: id) { path.append(.editor($0)) }
                case .editor(let e):
                    EntryEditorView(entry: e)
                case .insights:
                    InsightsView { path.append(.editor($0)) }
                case .places:
                    PlacesView { path.append(.editor($0)) }
                }
            }
            .sheet(item: $journalSheet) { t in JournalSheet(journal: t.journal) }
            .sheet(isPresented: $showNotifications) { SettingsView() }
            .sheet(item: $share) { ShareSheet(items: $0.items) }
            .confirmationDialog("删除日记本「\(pendingDelete?.name ?? "")」？",
                                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("删除日记本和其中的日记", role: .destructive) {
                    if let j = pendingDelete { withAnimation { store.deleteJournal(j) } }
                }
            } message: {
                Text("其中的 \(pendingDelete.map { store.entries(in: $0.id).count } ?? 0) 篇日记也会被删除，且无法恢复。")
            }
            .alert("提示", isPresented: Binding(get: { store.lastError != nil },
                                              set: { if !$0 { store.lastError = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(store.lastError ?? "")
            }
        }
    }

    private var menu: some View {
        Menu {
            Section {
                Button { withAnimation { editMode = .active } } label: { Label("编辑", systemImage: "pencil") }
            }
            Section {
                Button { showNotifications = true } label: { Label("通知", systemImage: "bell") }
                Button {
                    if let url = store.exportMarkdown() { share = SharePayload(items: [url]) }
                } label: { Label("导出日记", systemImage: "square.and.arrow.up") }
                Button {
                    Task {
                        if await AppLock.authenticate(reason: lockEnabled ? "关闭日记锁定" : "锁定日记") {
                            lockEnabled.toggle()
                        }
                    }
                } label: {
                    Label(lockEnabled ? "取消锁定日记" : "锁定日记", systemImage: lockEnabled ? "lock.open" : "lock")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("更多")
    }
}

struct JournalRow: View {
    let icon: String
    let color: Color
    let name: String
    let count: Int

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(color)
                .frame(width: 34)
            Text(name).font(.body)
            Spacer()
            Text("\(count)").foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 分析卡片

struct InsightsCard: View {
    @EnvironmentObject private var store: JournalStore

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.71, green: 0.56, blue: 0.67), Color(red: 0.86, green: 0.58, blue: 0.62)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 0) {
                Text("分析").font(.headline).foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 8)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(store.wordsThisMonth)")
                            .font(.system(size: 64, weight: .heavy, design: .rounded))
                            .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text("个字 - 本月").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .leading, spacing: 10) {
                        stat("flame.fill", "\(store.currentStreak)", "天连续记录")
                        stat("square.stack.fill", "\(store.thisYear.count)", "今年日记数量")
                    }
                    .frame(width: 140, alignment: .leading)
                }
            }
            .padding(18)
        }
        .frame(height: 176)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func stat(_ icon: String, _ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(value).font(.title3.bold())
            }
            .foregroundStyle(.white)
            Text(label).font(.footnote).foregroundStyle(.white.opacity(0.8))
        }
    }
}

// MARK: - 地点

struct PlaceCluster: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let entries: [Entry]
}

extension JournalStore {
    /// 按约 1 公里网格把地点聚合
    var placeClusters: [PlaceCluster] {
        var groups: [String: [Entry]] = [:]
        for e in placeEntries {
            guard let lat = e.location?.latitude, let lon = e.location?.longitude else { continue }
            let key = String(format: "%.2f,%.2f", lat, lon)
            groups[key, default: []].append(e)
        }
        return groups.map { key, list in
            let lat = list.compactMap { $0.location?.latitude }.reduce(0, +) / Double(list.count)
            let lon = list.compactMap { $0.location?.longitude }.reduce(0, +) / Double(list.count)
            return PlaceCluster(id: key, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), entries: list)
        }
    }
}

struct ClusterPin: View {
    let count: Int
    var body: some View {
        Text("\(count)")
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Circle().fill(Color.accentColor))
            .overlay(Circle().stroke(.white, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
    }
}

struct PlacesCard: View {
    @EnvironmentObject private var store: JournalStore

    var body: some View {
        let clusters = store.placeClusters
        ZStack(alignment: .topLeading) {
            Map(initialPosition: .automatic, interactionModes: []) {
                ForEach(clusters) { c in
                    Annotation("", coordinate: c.coordinate) { ClusterPin(count: c.entries.count) }
                }
            }
            .id(clusters.map(\.id).joined())
            .allowsHitTesting(false)

            LinearGradient(colors: [Color(red: 0.25, green: 0.42, blue: 0.2).opacity(0.85), .clear],
                           startPoint: .leading, endPoint: UnitPoint(x: 0.55, y: 0.5))
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 4) {
                Text("地点").font(.headline)
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                    Text("\(Set(store.placeEntries.compactMap { $0.location?.placeName }).count)").font(.title3.bold())
                }
            }
            .foregroundStyle(.white)
            .padding(18)
        }
        .frame(height: 176)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

struct PlacesView: View {
    var open: (Entry) -> Void
    @EnvironmentObject private var store: JournalStore
    @State private var selected: PlaceCluster?

    var body: some View {
        Map(initialPosition: .automatic) {
            ForEach(store.placeClusters) { c in
                Annotation(c.entries.first?.location?.placeName ?? "", coordinate: c.coordinate) {
                    Button { selected = c } label: { ClusterPin(count: c.entries.count) }
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("地点")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if store.placeEntries.isEmpty {
                ContentUnavailableView("还没有地点", systemImage: "mappin.slash",
                                       description: Text("在日记中点「地点」按钮即可记录你所在的位置。"))
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .padding(40)
            }
        }
        .sheet(item: $selected) { c in
            NavigationStack {
                List(c.entries) { e in
                    Button {
                        selected = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { open(e) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(e.title.isEmpty ? Fmt.day(e.date) : e.title).font(.headline).foregroundStyle(.primary)
                            Text(e.body.isEmpty ? (e.location?.placeName ?? "") : e.body)
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                .navigationTitle(c.entries.first?.location?.placeName ?? "地点")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - 新建 / 编辑日记本

struct JournalSheetTarget: Identifiable {
    let id = UUID()
    let journal: Journal?
}

struct JournalSheet: View {
    let journal: Journal?
    @EnvironmentObject private var store: JournalStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var icon: String
    @State private var colorIndex: Int

    init(journal: Journal?) {
        self.journal = journal
        _name = State(initialValue: journal?.name ?? "")
        _icon = State(initialValue: journal?.icon ?? Journal.icons[1])
        _colorIndex = State(initialValue: journal?.colorIndex ?? 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: icon)
                            .font(.system(size: 44))
                            .foregroundStyle(Palette.color(colorIndex))
                            .frame(width: 90, height: 90)
                            .background(Palette.color(colorIndex).opacity(0.15), in: Circle())
                        TextField("日记本名称", text: $name)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .padding(12)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                Section("颜色") {
                    HStack {
                        ForEach(Palette.colors.indices, id: \.self) { i in
                            Circle()
                                .fill(Palette.colors[i])
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(Color.primary, lineWidth: colorIndex == i ? 2.5 : 0).padding(-4))
                                .frame(maxWidth: .infinity)
                                .onTapGesture { colorIndex = i }
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                        ForEach(Journal.icons, id: \.self) { ic in
                            Image(systemName: ic)
                                .font(.title3)
                                .foregroundStyle(icon == ic ? Palette.color(colorIndex) : .secondary)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(icon == ic ? Palette.color(colorIndex).opacity(0.18) : Color(.tertiarySystemFill)))
                                .onTapGesture { icon = ic }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle(journal == nil ? "新建日记本" : "编辑日记本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        var j = journal ?? Journal(name: "", icon: icon, colorIndex: colorIndex)
                        j.name = name.trimmingCharacters(in: .whitespaces)
                        j.icon = icon
                        j.colorIndex = colorIndex
                        store.saveJournal(j)
                        dismiss()
                    }
                    .bold()
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - 日记本内的日记列表

struct JournalEntriesView: View {
    let journalID: UUID?
    var open: (Entry) -> Void

    @EnvironmentObject private var store: JournalStore
    @State private var filter: EntryFilter = .all
    @State private var query = ""
    @State private var pendingDelete: Entry?

    private var title: String { store.journal(journalID)?.name ?? "所有日记" }

    private var visible: [Entry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return store.entries(in: journalID).filter { filter.includes($0) && (q.isEmpty || $0.matches(q)) }
    }

    struct MonthSection {
        let title: String
        var entries: [Entry]
    }

    private var sections: [MonthSection] {
        var result: [MonthSection] = []
        for e in visible {
            let t = Fmt.month(e.date)
            if result.last?.title == t {
                result[result.count - 1].entries.append(e)
            } else {
                result.append(MonthSection(title: t, entries: [e]))
            }
        }
        return result
    }

    var body: some View {
        ScrollView {
            if store.entries(in: journalID).isEmpty {
                ContentUnavailableView {
                    Label("开始写日记", systemImage: "book.pages")
                } description: {
                    Text("记录每天的片刻：文字、照片、录音和去过的地方。")
                } actions: {
                    Button("写下第一篇") { newEntry() }.buttonStyle(.borderedProminent)
                }
                .padding(.top, 80)
            } else if visible.isEmpty {
                ContentUnavailableView(query.isEmpty ? "没有\(filter.title)" : "没有找到“\(query)”",
                                       systemImage: query.isEmpty ? filter.icon : "magnifyingglass")
                    .padding(.top, 80)
            } else {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(sections, id: \.title) { section in
                        Text(section.title)
                            .font(.title3.bold())
                            .padding(.top, 8)
                            .padding(.leading, 4)
                        ForEach(section.entries) { e in
                            EntryCard(entry: e,
                                      journal: journalID == nil ? store.journal(e.journalID) : nil,
                                      onEdit: { open(e) },
                                      onDelete: { pendingDelete = e })
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 110)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .searchable(text: $query, prompt: "搜索")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("显示", selection: $filter) {
                        ForEach(EntryFilter.allCases) { f in Label(f.title, systemImage: f.icon).tag(f) }
                    }
                } label: {
                    Image(systemName: filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .overlay(alignment: .bottom) {
            Button { newEntry() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .prominentGlassButton()
            .controlSize(.large)
            .accessibilityLabel("新建日记")
            .padding(.bottom, 16)
        }
        .confirmationDialog("删除这篇日记？",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let e = pendingDelete { withAnimation { store.delete(e) } }
            }
        } message: {
            Text("删除后无法恢复。")
        }
    }

    private func newEntry() {
        open(Entry(journalID: journalID ?? store.defaultJournalID))
    }
}

// MARK: - 卡片

struct EntryCard: View {
    let entry: Entry
    var journal: Journal?
    var onEdit: () -> Void
    var onDelete: () -> Void

    @EnvironmentObject private var store: JournalStore
    @State private var viewerIndex: ViewerIndex?

    struct ViewerIndex: Identifiable {
        let id: Int
    }

    private var photoURLs: [URL] { entry.photos.compactMap { $0.fileName.map(store.mediaURL) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !photoURLs.isEmpty {
                PhotoMosaic(urls: photoURLs) { viewerIndex = ViewerIndex(id: $0) }
            }

            VStack(alignment: .leading, spacing: 10) {
                if let m = entry.mood.flatMap(Mood.init(rawValue:)) {
                    Text("\(m.emoji) \(m.title)")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(m.color.opacity(0.18), in: Capsule())
                }
                if let prompt = entry.prompt {
                    Label(prompt, systemImage: "wand.and.sparkles")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
                ForEach(entry.audios) { a in
                    if let name = a.fileName {
                        AudioChip(url: store.mediaURL(name), duration: a.duration ?? 0)
                    }
                }
                if let loc = entry.location {
                    LocationCard(attachment: loc)
                }
                if !entry.title.isEmpty {
                    Text(entry.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                if !entry.body.isEmpty {
                    Text(entry.body)
                        .font(.body)
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(6)
                        .lineSpacing(3)
                }

                HStack(spacing: 6) {
                    if let journal {
                        Image(systemName: journal.icon).foregroundStyle(Palette.color(journal.colorIndex))
                    }
                    Text(Fmt.day(entry.date))
                    if entry.isBookmarked {
                        Image(systemName: "bookmark.fill").foregroundStyle(Color.accentColor)
                    }
                    Spacer()
                    Menu {
                        Button(action: onEdit) { Label("编辑", systemImage: "pencil") }
                        Button { store.toggleBookmark(entry) } label: {
                            Label(entry.isBookmarked ? "取消收藏" : "收藏",
                                  systemImage: entry.isBookmarked ? "bookmark.slash" : "bookmark")
                        }
                        ShareLink(item: shareText) { Label("分享", systemImage: "square.and.arrow.up") }
                        Divider()
                        Button(role: .destructive, action: onDelete) { Label("删除", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.semibold))
                            .frame(width: 36, height: 28)
                            .contentShape(Rectangle())
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }
            .padding(16)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(perform: onEdit)
        .contextMenu {
            Button(action: onEdit) { Label("编辑", systemImage: "pencil") }
            Button { store.toggleBookmark(entry) } label: {
                Label(entry.isBookmarked ? "取消收藏" : "收藏", systemImage: "bookmark")
            }
            Button(role: .destructive, action: onDelete) { Label("删除", systemImage: "trash") }
        }
        .fullScreenCover(item: $viewerIndex) { v in
            PhotoViewer(urls: photoURLs, index: v.id)
        }
    }

    private var shareText: String {
        var parts = [Fmt.full(entry.date)]
        if !entry.title.isEmpty { parts.append(entry.title) }
        if !entry.body.isEmpty { parts.append(entry.body) }
        return parts.joined(separator: "\n\n")
    }
}

