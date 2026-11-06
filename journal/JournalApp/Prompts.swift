import Foundation

/// 写作提示（反思类问题）
enum Prompts {
    struct Category: Identifiable {
        let id: String
        let icon: String
        let prompts: [String]
    }

    static let categories: [Category] = [
        .init(id: "今天", icon: "sun.max", prompts: [
            "今天让你微笑的一个瞬间是什么？",
            "今天你学到了什么新东西？",
            "如果可以重来，今天你会做些什么不一样的事？",
            "今天吃到的最好吃的是什么？和谁一起？",
            "用三个词形容今天，并说说为什么。",
            "今天有什么事情比你预想的更顺利？",
        ]),
        .init(id: "感恩", icon: "heart", prompts: [
            "写下三件你此刻心怀感激的小事。",
            "最近有谁帮助过你？你想对他说什么？",
            "有哪样东西你每天都在用，却很少想起它有多重要？",
            "回想一个让你觉得被理解的时刻。",
            "你身体的哪一部分今天为你出了力？",
        ]),
        .init(id: "回顾", icon: "clock.arrow.circlepath", prompts: [
            "一年前的今天，你在担心什么？现在呢？",
            "最近一次走出舒适区是什么时候？结果如何？",
            "这个月你最骄傲的一件事是什么？",
            "有什么习惯是你最近养成或放下的？",
            "描述一个你想永远记住的地方。",
        ]),
        .init(id: "关系", icon: "person.2", prompts: [
            "最近一次和朋友深聊，聊了些什么？",
            "有谁是你想多联系一下的？为什么还没有？",
            "家人身上有什么特质是你希望自己也有的？",
            "写一封不会寄出的信给一个重要的人。",
        ]),
        .init(id: "展望", icon: "sparkles", prompts: [
            "接下来一周，你最期待的是什么？",
            "如果明天不用工作，你会怎样度过？",
            "五年后的你，会想对现在的你说什么？",
            "有什么事情你一直想尝试却还没开始？第一步是什么？",
            "此刻，你最想要放下的是什么？",
        ]),
    ]

    static var all: [String] { categories.flatMap(\.prompts) }

    /// 每天固定的「今日提示」
    static func ofTheDay(_ date: Date = Date()) -> String {
        let day = Fmt.calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return all[day % all.count]
    }

    static func random(count: Int) -> [String] { Array(all.shuffled().prefix(count)) }
}
