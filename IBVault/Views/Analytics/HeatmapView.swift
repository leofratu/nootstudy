import SwiftUI

/// Consistency facts behind the heatmap, kept pure so they can be tested.
nonisolated struct StudyConsistency: Equatable, Sendable {
    let activeDays: Int
    let currentStreak: Int
    let longestStreak: Int
    let totalMinutes: Int
    let totalCards: Int

    /// A day missed so far today does not break a streak; yesterday still counts.
    static func compute(days: [Date: (cards: Int, minutes: Double)], today: Date, calendar: Calendar) -> StudyConsistency {
        let active = Set(days.filter { $0.value.cards > 0 || $0.value.minutes > 0 }.keys.map { calendar.startOfDay(for: $0) })
        var longest = 0
        var run = 0
        var previous: Date?
        for day in active.sorted() {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }
        let startOfToday = calendar.startOfDay(for: today)
        var cursor = active.contains(startOfToday)
            ? startOfToday
            : (calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday)
        var current = 0
        while active.contains(cursor) {
            current += 1
            guard let earlier = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = earlier
        }
        return StudyConsistency(
            activeDays: active.count,
            currentStreak: current,
            longestStreak: longest,
            totalMinutes: Int(days.values.reduce(0) { $0 + max($1.minutes, 0) }),
            totalCards: days.values.reduce(0) { $0 + max($1.cards, 0) }
        )
    }
}

struct HeatmapView: View {
    let activities: [StudyActivity]
    private let columns = 53
    private let rows = 7
    private let cellSize: CGFloat = 11
    private let spacing: CGFloat = 3
    private let labelWidth: CGFloat = 24

    var body: some View {
        // Hoisted once per render so each cell does not rebuild the index.
        let index = totalsByDay
        let today = Calendar.current.startOfDay(for: Date())
        let stats = StudyConsistency.compute(days: index, today: today, calendar: .current)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 28) {
                stat("\(stats.currentStreak)", "day streak")
                stat("\(stats.longestStreak)", "longest streak")
                stat("\(stats.activeDays)", "active days")
                stat(hoursLabel(stats.totalMinutes), "studied")
                stat("\(stats.totalCards)", "cards reviewed")
            }
            // Scrolls only in a window too narrow for the whole year, and then
            // opens on the most recent weeks.
            ViewThatFits(in: .horizontal) {
                grid(index: index, today: today)
                ScrollView(.horizontal, showsIndicators: false) {
                    grid(index: index, today: today)
                }
                .defaultScrollAnchor(.trailing)
            }
            HStack(spacing: 4) {
                Spacer()
                Text("Less").font(.system(size: 10)).foregroundStyle(IBColors.inkTertiary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2).fill(color(for: level)).frame(width: cellSize, height: cellSize)
                }
                Text("More").font(.system(size: 10)).foregroundStyle(IBColors.inkTertiary)
            }
        }
    }

    private func grid(index: [Date: (cards: Int, minutes: Double)], today: Date) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            monthRow
            ForEach(0..<rows, id: \.self) { day in
                HStack(spacing: spacing) {
                    Text(dayLabel(day))
                        .font(.system(size: 9))
                        .foregroundStyle(IBColors.inkTertiary)
                        .frame(width: labelWidth, alignment: .leading)
                    ForEach(0..<columns, id: \.self) { week in
                        cell(date: dateFor(week: week, day: day), index: index, today: today)
                    }
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .foregroundStyle(IBColors.ink)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(IBColors.inkTertiary)
                .lineLimit(1)
        }
    }

    private func hoursLabel(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
    }

    private var monthRow: some View {
        HStack(spacing: spacing) {
            Color.clear.frame(width: labelWidth, height: 12)
            ForEach(0..<columns, id: \.self) { week in
                if week == 0 || !Calendar.current.isDate(dateFor(week: week, day: 0), equalTo: dateFor(week: week - 1, day: 0), toGranularity: .month) {
                    Text(Self.monthFormatter.string(from: dateFor(week: week, day: 0)))
                        .font(.system(size: 9))
                        .foregroundStyle(IBColors.inkTertiary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(width: cellSize, alignment: .leading)
                } else {
                    Color.clear.frame(width: cellSize, height: 12)
                }
            }
        }
    }

    @ViewBuilder
    private func cell(date: Date, index: [Date: (cards: Int, minutes: Double)], today: Date) -> some View {
        if date > today {
            Color.clear.frame(width: cellSize, height: cellSize)
        } else {
            let day = index[date] ?? (0, 0)
            let summary = daySummary(date: date, cards: day.cards, minutes: day.minutes)
            RoundedRectangle(cornerRadius: 2)
                .fill(color(for: StudyActivity.intensity(cardsReviewed: day.cards, minutesStudied: day.minutes)))
                .frame(width: cellSize, height: cellSize)
                .overlay {
                    if date == today {
                        RoundedRectangle(cornerRadius: 2).stroke(IBColors.inkSecondary, lineWidth: 1)
                    }
                }
                .help(summary)
                .accessibilityLabel(summary)
        }
    }

    private func daySummary(date: Date, cards: Int, minutes: Double) -> String {
        let title = date.formatted(date: .abbreviated, time: .omitted)
        guard cards > 0 || minutes > 0 else { return "\(title): no study" }
        return "\(title): \(cards) cards, \(Int(minutes)) min"
    }

    private func dayLabel(_ day: Int) -> String {
        ["", "Mon", "", "Wed", "", "Fri", ""][day]
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private func dateFor(week: Int, day: Int) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let startOfWeek = cal.date(byAdding: .day, value: -(weekday - 1), to: today) ?? today
        let startDate = cal.date(byAdding: .weekOfYear, value: -(columns - 1 - week), to: startOfWeek) ?? today
        return cal.date(byAdding: .day, value: day, to: startDate) ?? today
    }

    private var totalsByDay: [Date: (cards: Int, minutes: Double)] {
        let cal = Calendar.current
        var totals: [Date: (cards: Int, minutes: Double)] = [:]
        for activity in activities {
            let day = cal.startOfDay(for: activity.date)
            let existing = totals[day] ?? (0, 0)
            totals[day] = (existing.cards + activity.cardsReviewed, existing.minutes + activity.minutesStudied)
        }
        return totals
    }

    private func color(for level: Int) -> Color {
        switch level {
        case 0: return IBColors.surfaceHover
        case 1: return IBColors.accent.opacity(0.28)
        case 2: return IBColors.accent.opacity(0.5)
        case 3: return IBColors.accent.opacity(0.75)
        default: return IBColors.accent
        }
    }
}
