import SwiftUI

/// 回顾：连续记录、年度统计、日历
struct InsightsView: View {
    var open: (Entry) -> Void
    @EnvironmentObject private var store: JournalStore

    @State private var month = Fmt.calendar.dateInterval(of: .month, for: Date())!.start
    @State private var selectedDay: Date?

    private var cal: Calendar { Fmt.calendar }

    var body: some View {
            ScrollView {
                VStack(spacing: 16) {
                    streakCard
                    HStack(spacing: 12) {
                        statTile(value: "\(store.thisYear.count)", label: "今年日记", icon: "book.closed.fill", color: .accentColor)
                        statTile(value: "\(store.thisYear.reduce(0) { $0 + $1.wordCount })", label: "今年字数", icon: "character.cursor.ibeam", color: .blue)
                    }
                    HStack(spacing: 12) {
                        statTile(value: "\(store.entries.reduce(0) { $0 + $1.photos.count })", label: "照片", icon: "photo.fill", color: .green)
                        statTile(value: "\(Set(store.entries.compactMap { $0.location?.placeName }).count)", label: "地点", icon: "mappin.circle.fill", color: .red)
                    }
                    calendarCard
                    if let day = selectedDay {
                        dayEntries(day)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("分析")
            .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 卡片

    private var streakCard: some View {
        HStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(systemName: "flame.fill").font(.title).foregroundStyle(.orange)
                Text("\(store.currentStreak)").font(.system(size: 34, weight: .bold, design: .rounded))
                Text("当前连续天数").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            Divider().frame(height: 80)
            VStack(spacing: 6) {
                Image(systemName: "trophy.fill").font(.title).foregroundStyle(.yellow)
                Text("\(store.longestStreak)").font(.system(size: 34, weight: .bold, design: .rounded))
                Text("最长连续天数").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func statTile(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var calendarCard: some View {
        let days = store.entryDays
        let grid = monthGrid()
        return VStack(spacing: 12) {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(Fmt.month(month)).font(.headline)
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(cal.isDate(month, equalTo: Date(), toGranularity: .month))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { d in
                    Text(d).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(Array(grid.enumerated()), id: \.offset) { _, day in
                    if let day {
                        let has = days.contains(day)
                        let isToday = cal.isDateInToday(day)
                        let isSelected = selectedDay.map { cal.isDate($0, inSameDayAs: day) } ?? false
                        Button {
                            selectedDay = has ? day : nil
                        } label: {
                            Text("\(cal.component(.day, from: day))")
                                .font(.callout.weight(has ? .bold : .regular))
                                .foregroundStyle(has ? Color.white : (isToday ? Color.accentColor : Color.primary))
                                .frame(width: 36, height: 36)
                                .background {
                                    if has {
                                        Circle().fill(Color.accentColor.opacity(isSelected ? 1 : 0.75))
                                    } else if isToday {
                                        Circle().stroke(Color.accentColor, lineWidth: 1.5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func dayEntries(_ day: Date) -> some View {
        let list = store.entries.filter { cal.isDate($0.date, inSameDayAs: day) }
        return VStack(alignment: .leading, spacing: 10) {
            Text(Fmt.full(day)).font(.headline)
            ForEach(list) { e in
                Button {
                    open(e)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(e.title.isEmpty ? (e.prompt ?? "无标题") : e.title)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        if !e.body.isEmpty {
                            Text(e.body).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 日历计算

    private func shiftMonth(_ delta: Int) {
        if let m = cal.date(byAdding: .month, value: delta, to: month) {
            month = m
            selectedDay = nil
        }
    }

    /// 当月日期（前面用 nil 补齐到周一）
    private func monthGrid() -> [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = cal.component(.weekday, from: month)  // 1 = 周日
        let leading = (weekday - cal.firstWeekday + 7) % 7
        var result: [Date?] = Array(repeating: nil, count: leading)
        for d in range {
            result.append(cal.date(byAdding: .day, value: d - 1, to: month))
        }
        return result
    }
}
