import SwiftUI

struct ComposeTarget: Identifiable {
    let id = UUID()
    let entry: Entry
    let isNew: Bool
}

struct HomeView: View {
    @EnvironmentObject private var store: JournalStore

    @State private var filter: EntryFilter = .all
    @State private var query = ""
    @State private var composing: ComposeTarget?
    @State private var showStart = false
    @State private var showInsights = false
    @State private var showSettings = false
    @State private var pendingDelete: Entry?

    private var visible: [Entry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return store.entries.filter { filter.includes($0) && (q.isEmpty || $0.matches(q)) }
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
        NavigationStack {
            ScrollView {
                if store.entries.isEmpty {
                    WelcomeView { showStart = true }
                        .padding(.top, 60)
                } else if visible.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "没有\(filter.title)" : "没有找到“\(query)”",
                                           systemImage: query.isEmpty ? filter.icon : "magnifyingglass")
                        .padding(.top, 80)
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if filter == .all && query.isEmpty {
                            StreakBanner()
                        }
                        ForEach(sections, id: \.title) { section in
                            Text(section.title)
                                .font(.title3.bold())
                                .padding(.top, 8)
                                .padding(.leading, 4)
                            ForEach(section.entries) { e in
                                EntryCard(entry: e,
                                          onEdit: { composing = ComposeTarget(entry: e, isNew: false) },
                                          onDelete: { pendingDelete = e })
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 120)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(filter == .all ? "片刻" : filter.title)
            .searchable(text: $query, prompt: "搜索")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showInsights = true } label: { Image(systemName: "chart.bar.xaxis") }
                        .accessibilityLabel("回顾")
                    Menu {
                        Picker("显示", selection: $filter) {
                            ForEach(EntryFilter.allCases) { f in
                                Label(f.title, systemImage: f.icon).tag(f)
                            }
                        }
                        Divider()
                        Button { showSettings = true } label: { Label("设置", systemImage: "gearshape") }
                    } label: {
                        Image(systemName: filter == .all
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("筛选")
                }
            }
            .overlay(alignment: .bottom) { newEntryButton }
            .sheet(isPresented: $showStart) {
                StartSheet { prompt in
                    showStart = false
                    var e = Entry()
                    e.prompt = prompt
                    // 等提示面板收起再弹出编辑器
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        composing = ComposeTarget(entry: e, isNew: true)
                    }
                }
            }
            .sheet(item: $composing) { t in
                ComposerView(entry: t.entry, isNew: t.isNew)
            }
            .sheet(isPresented: $showInsights) { InsightsView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .confirmationDialog("删除这篇日记？", isPresented: Binding(get: { pendingDelete != nil },
                                                                 set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    if let e = pendingDelete {
                        withAnimation { store.delete(e) }
                    }
                }
            } message: {
                Text("删除后无法恢复。")
            }
            .alert("提示", isPresented: Binding(get: { store.lastError != nil },
                                              set: { if !$0 { store.lastError = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(store.lastError ?? "")
            }
        }
    }

    private var newEntryButton: some View {
        Button { showStart = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 68, height: 68)
                .background(
                    Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.36), .accentColor],
                                                 startPoint: .top, endPoint: .bottom))
                )
                .shadow(color: .accentColor.opacity(0.35), radius: 12, y: 6)
        }
        .accessibilityLabel("新建日记")
        .padding(.bottom, 12)
    }
}

// MARK: - 卡片

struct EntryCard: View {
    let entry: Entry
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
                if let prompt = entry.prompt {
                    Label(prompt, systemImage: "sparkles")
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

// MARK: - 新建面板

/// 点「＋」后弹出：直接新建，或从写作提示开始
struct StartSheet: View {
    var onStart: (String?) -> Void
    @State private var prompts = Prompts.random(count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Button { onStart(nil) } label: {
                        HStack {
                            Image(systemName: "square.and.pencil")
                            Text("新建日记").bold()
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.bold())
                        }
                        .padding()
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("写作提示").font(.headline)
                            Spacer()
                            Button {
                                withAnimation { prompts = Prompts.random(count: 6) }
                            } label: { Image(systemName: "arrow.clockwise") }
                            .accessibilityLabel("换一批")
                        }
                        Text("不知道写什么？从一个问题开始。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(prompts, id: \.self) { p in
                                    Button { onStart(p) } label: { promptCard(p) }
                                        .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("开始书写")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func promptCard(_ p: String) -> some View {
        VStack(alignment: .leading) {
            Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
            Spacer()
            Text(p)
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.leading)
                .lineLimit(4)
        }
        .padding(14)
        .frame(width: 180, height: 150, alignment: .leading)
        .background(
            LinearGradient(colors: [Color.accentColor.opacity(0.16), Color.orange.opacity(0.08)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}

// MARK: - 空状态 / 连续记录

struct WelcomeView: View {
    var onStart: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "book.pages")
                .font(.system(size: 64))
                .foregroundStyle(LinearGradient(colors: [.orange, .accentColor], startPoint: .top, endPoint: .bottom))
            Text("开始写日记").font(.title2.bold())
            Text("记录每天的片刻：文字、照片、录音和去过的地方，\n都只保存在这台设备上。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onStart) {
                Text("写下第一篇").bold().padding(.horizontal, 20)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }
}

struct StreakBanner: View {
    @EnvironmentObject private var store: JournalStore

    var body: some View {
        let streak = store.currentStreak
        let today = store.entries.contains { Fmt.calendar.isDateInToday($0.date) }
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundStyle(streak > 0 ? Color.orange : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(streak > 0 ? "已连续记录 \(streak) 天" : "今天还没有写日记")
                    .font(.subheadline.bold())
                Text(today ? "今天已经写过了，明天继续 ✨" : "今日提示：\(Prompts.ofTheDay())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
