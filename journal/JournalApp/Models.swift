import SwiftUI

enum AttachmentKind: String, Codable {
    case photo, audio, location
}

struct Attachment: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: AttachmentKind
    /// 照片 / 录音保存在 Documents/Media 下的文件名
    var fileName: String?
    var duration: TimeInterval?
    var placeName: String?
    var latitude: Double?
    var longitude: Double?
}

struct Entry: Codable, Identifiable, Hashable {
    var id = UUID()
    /// 日记所属日期（可修改）
    var date = Date()
    var createdAt = Date()
    var updatedAt = Date()
    var title = ""
    var body = ""
    /// 从写作提示开始时显示的问题
    var prompt: String?
    var isBookmarked = false
    var attachments: [Attachment] = []
    /// 所属日记本
    var journalID: UUID?
    /// 心情（Mood.rawValue）
    var mood: String?
    /// 带格式的正文（RTF）；`body` 始终保存纯文本用于搜索和统计
    var richText: Data?
    var titleHidden: Bool?

    var photos: [Attachment] { attachments.filter { $0.kind == .photo } }
    var audios: [Attachment] { attachments.filter { $0.kind == .audio } }
    var location: Attachment? { attachments.first { $0.kind == .location } }

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && attachments.isEmpty
    }

    /// 字数：中文按字、英文按词
    var wordCount: Int {
        let text = title + "\n" + body
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { word, _, _, _ in
            guard let word else { return }
            let cjk = word.unicodeScalars.filter { (0x3400...0x9FFF).contains($0.value) }.count
            count += cjk > 0 ? cjk : 1
        }
        return count
    }

    func matches(_ query: String) -> Bool {
        title.localizedCaseInsensitiveContains(query)
            || body.localizedCaseInsensitiveContains(query)
            || (prompt?.localizedCaseInsensitiveContains(query) ?? false)
            || (location?.placeName?.localizedCaseInsensitiveContains(query) ?? false)
    }
}

struct Journal: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var icon: String
    var colorIndex: Int

    static let icons = [
        "book.closed.fill", "heart.fill", "moon.fill", "house.fill", "star.fill", "leaf.fill",
        "sun.max.fill", "airplane", "briefcase.fill", "pawprint.fill", "cup.and.saucer.fill", "music.note",
        "camera.fill", "figure.walk", "graduationcap.fill", "gift.fill", "tray.full.fill", "sparkles",
    ]
}

enum Palette {
    static let colors: [Color] = [
        Color(red: 0.42, green: 0.36, blue: 0.95), Color(red: 0.96, green: 0.42, blue: 0.29),
        Color(red: 0.98, green: 0.78, blue: 0.20), Color(red: 0.30, green: 0.75, blue: 0.45),
        Color(red: 0.20, green: 0.60, blue: 0.95), Color(red: 0.93, green: 0.35, blue: 0.55),
        Color(red: 0.78, green: 0.52, blue: 0.40), Color(red: 0.15, green: 0.15, blue: 0.17),
    ]
    static func color(_ i: Int) -> Color { colors[((i % colors.count) + colors.count) % colors.count] }
}

enum Mood: String, CaseIterable, Identifiable {
    case great, good, calm, neutral, bad, awful

    var id: String { rawValue }

    var title: String {
        switch self {
        case .great: return "非常愉快"
        case .good: return "愉快"
        case .calm: return "平静"
        case .neutral: return "一般"
        case .bad: return "不愉快"
        case .awful: return "非常不愉快"
        }
    }

    var emoji: String {
        switch self {
        case .great: return "🤩"
        case .good: return "😊"
        case .calm: return "😌"
        case .neutral: return "😐"
        case .bad: return "😔"
        case .awful: return "😣"
        }
    }

    var color: Color {
        switch self {
        case .great: return .orange
        case .good: return .yellow
        case .calm: return .mint
        case .neutral: return .gray
        case .bad: return .indigo
        case .awful: return .purple
        }
    }
}

enum EntryFilter: String, CaseIterable, Identifiable {
    case all, bookmarked, photos, recordings, places

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部条目"
        case .bookmarked: return "已收藏"
        case .photos: return "照片"
        case .recordings: return "录音"
        case .places: return "地点"
        }
    }

    var icon: String {
        switch self {
        case .all: return "book"
        case .bookmarked: return "bookmark"
        case .photos: return "photo"
        case .recordings: return "waveform"
        case .places: return "mappin.and.ellipse"
        }
    }

    func includes(_ e: Entry) -> Bool {
        switch self {
        case .all: return true
        case .bookmarked: return e.isBookmarked
        case .photos: return !e.photos.isEmpty
        case .recordings: return !e.audios.isEmpty
        case .places: return e.location != nil
        }
    }
}

/// 统一使用中文日期格式（不随系统语言变化）
enum Fmt {
    static let locale = Locale(identifier: "zh_CN")

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = locale
        c.firstWeekday = 2
        return c
    }()

    private static func make(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.calendar = calendar
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    private static let dayF = make("MMMdEEEE")
    private static let shortF = make("MMMdEEE")
    private static let fullF = make("yMMMdEEEE")
    private static let monthF = make("yMMMM")
    private static let weekdayF = make("EEEE")
    private static let timeF = make("jm")

    static func day(_ d: Date) -> String {
        calendar.isDate(d, equalTo: Date(), toGranularity: .year) ? dayF.string(from: d) : fullF.string(from: d)
    }
    static func full(_ d: Date) -> String { fullF.string(from: d) }
    static func short(_ d: Date) -> String { shortF.string(from: d) }
    static func month(_ d: Date) -> String { monthF.string(from: d) }
    static func weekday(_ d: Date) -> String { weekdayF.string(from: d) }
    static func time(_ d: Date) -> String { timeF.string(from: d) }

    static func relativeDay(_ d: Date) -> String {
        if calendar.isDateInToday(d) { return "今天" }
        if calendar.isDateInYesterday(d) { return "昨天" }
        return weekday(d)
    }

    static func duration(_ t: TimeInterval) -> String {
        let s = Int(max(0, t).rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
