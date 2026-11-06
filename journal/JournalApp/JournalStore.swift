import SwiftUI
import UIKit

/// 日记数据：Documents/journal.json + Documents/Media/（照片、录音）
@MainActor
final class JournalStore: ObservableObject {
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var journals: [Journal] = []
    @Published var lastError: String?

    let mediaDir: URL
    private let indexURL: URL
    private let journalsURL: URL
    private let fm = FileManager.default

    init() {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        mediaDir = docs.appendingPathComponent("Media", isDirectory: true)
        indexURL = docs.appendingPathComponent("journal.json")
        journalsURL = docs.appendingPathComponent("journals.json")
        try? fm.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        load()
    }

    func mediaURL(_ name: String) -> URL { mediaDir.appendingPathComponent(name) }

    // MARK: - 读写

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: indexURL) {
            entries = ((try? decoder.decode([Entry].self, from: data)) ?? []).sorted { $0.date > $1.date }
        }
        if let data = try? Data(contentsOf: journalsURL) {
            journals = (try? decoder.decode([Journal].self, from: data)) ?? []
        }
        if journals.isEmpty {
            journals = [Journal(name: "日记", icon: "book.closed.fill", colorIndex: 0)]
            persistJournals()
        }
        // 旧数据或日记本被删除：归到第一个日记本
        let ids = Set(journals.map(\.id))
        var changed = false
        for i in entries.indices where entries[i].journalID.map({ !ids.contains($0) }) ?? true {
            entries[i].journalID = journals[0].id
            changed = true
        }
        if changed { persist() }
    }

    private func persistJournals() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        try? encoder.encode(journals).write(to: journalsURL, options: [.atomic, .completeFileProtection])
    }

    // MARK: - 日记本

    var defaultJournalID: UUID { journals[0].id }

    func journal(_ id: UUID?) -> Journal? { journals.first { $0.id == id } }

    func entries(in journalID: UUID?) -> [Entry] {
        guard let journalID else { return entries }
        return entries.filter { $0.journalID == journalID }
    }

    func saveJournal(_ j: Journal) {
        if let i = journals.firstIndex(where: { $0.id == j.id }) { journals[i] = j } else { journals.append(j) }
        persistJournals()
    }

    func moveJournals(from: IndexSet, to: Int) {
        journals.move(fromOffsets: from, toOffset: to)
        persistJournals()
    }

    /// 删除日记本及其中所有日记
    func deleteJournal(_ j: Journal) {
        guard journals.count > 1 else { return }
        for e in entries where e.journalID == j.id { removeFiles(e.attachments.compactMap(\.fileName)) }
        entries.removeAll { $0.journalID == j.id }
        journals.removeAll { $0.id == j.id }
        persist()
        persistJournals()
    }

    func entry(_ id: UUID) -> Entry? { entries.first { $0.id == id } }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(entries).write(to: indexURL, options: [.atomic, .completeFileProtection])
        } catch {
            lastError = "保存失败：\(error.localizedDescription)"
        }
    }

    func save(_ entry: Entry) {
        var e = entry
        e.updatedAt = Date()
        if let i = entries.firstIndex(where: { $0.id == e.id }) {
            entries[i] = e
        } else {
            entries.append(e)
        }
        entries.sort { $0.date > $1.date }
        persist()
    }

    func delete(_ entry: Entry) {
        guard let stored = self.entry(entry.id) else { return }
        removeFiles(stored.attachments.compactMap(\.fileName))
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func toggleBookmark(_ entry: Entry) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[i].isBookmarked.toggle()
        persist()
    }

    // MARK: - 媒体文件

    func removeFiles(_ names: [String]) {
        for n in names { try? fm.removeItem(at: mediaURL(n)) }
    }

    func storeImage(_ image: UIImage) -> String? {
        let scaled = image.normalized(maxDimension: 2400)
        guard let data = scaled.jpegData(compressionQuality: 0.85) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try data.write(to: mediaURL(name), options: .completeFileProtection)
            return name
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func storeImage(data: Data) -> String? {
        guard let img = UIImage(data: data) else { return nil }
        return storeImage(img)
    }

    func storeAudio(from url: URL) -> String? {
        let name = UUID().uuidString + "." + (url.pathExtension.isEmpty ? "m4a" : url.pathExtension)
        do {
            try fm.moveItem(at: url, to: mediaURL(name))
            return name
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - 统计

    private var cal: Calendar { Fmt.calendar }

    var entryDays: Set<Date> { Set(entries.map { cal.startOfDay(for: $0.date) }) }

    var currentStreak: Int {
        let days = entryDays
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var n = 0
        while days.contains(day) {
            n += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return n
    }

    var longestStreak: Int {
        let days = entryDays.sorted()
        var best = 0, run = 0
        var prev: Date?
        for d in days {
            if let p = prev, cal.dateComponents([.day], from: p, to: d).day == 1 { run += 1 } else { run = 1 }
            best = max(best, run)
            prev = d
        }
        return best
    }

    var wordsThisMonth: Int {
        entries.filter { cal.isDate($0.date, equalTo: Date(), toGranularity: .month) }.reduce(0) { $0 + $1.wordCount }
    }

    var placeEntries: [Entry] { entries.filter { $0.location?.latitude != nil } }

    var thisYear: [Entry] { entries.filter { cal.isDate($0.date, equalTo: Date(), toGranularity: .year) } }

    // MARK: - 导出

    func exportMarkdown() -> URL? {
        var md = "# 片刻 · 日记导出\n\n"
        for e in entries.sorted(by: { $0.date < $1.date }) {
            md += "## \(Fmt.full(e.date))" + (e.title.isEmpty ? "" : " · \(e.title)") + "\n\n"
            if let p = e.prompt { md += "> \(p)\n\n" }
            if let place = e.location?.placeName { md += "📍 \(place)\n\n" }
            if !e.body.isEmpty { md += e.body + "\n\n" }
            if !e.photos.isEmpty { md += "（\(e.photos.count) 张照片）\n\n" }
            if !e.audios.isEmpty { md += "（\(e.audios.count) 段录音）\n\n" }
        }
        let url = fm.temporaryDirectory.appendingPathComponent("片刻日记.md")
        do {
            try md.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}

extension UIImage {
    /// 修正方向并按最长边缩放
    func normalized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
