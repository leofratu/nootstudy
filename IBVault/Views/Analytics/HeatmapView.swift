import SwiftUI

struct HeatmapView: View {
    let activities: [StudyActivity]
    private let columns = 52
    private let rows = 7
    private let cellSize: CGFloat = 12
    private let spacing: CGFloat = 3

    var body: some View {
        // Hoisted once per render: the index is a computed property, so without
        // this the per-cell `intensityFor` lookup would rebuild it 52×7 times.
        let index = activityByDay
        return ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: spacing) {
                // Day labels
                HStack(spacing: spacing) {
                    Text("").frame(width: 24)
                    ForEach(0..<columns, id: \.self) { week in
                        if week == 0 || !Calendar.current.isDate(dateFor(week: week, day: 0), equalTo: dateFor(week: week - 1, day: 0), toGranularity: .month) {
                            monthLabel(for: week)
                        } else {
                            Color.clear.frame(width: cellSize)
                        }
                    }
                }
                // Grid
                ForEach(0..<rows, id: \.self) { day in
                    HStack(spacing: spacing) {
                        Text(dayLabel(day)).font(.system(size: 8)).foregroundColor(IBColors.inkTertiary).frame(width: 24)
                        ForEach(0..<columns, id: \.self) { week in
                            let date = dateFor(week: week, day: day)
                            let intensity = intensityFor(date: date, in: index)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(date > Date() ? Color.clear : colorForIntensity(intensity))
                                .frame(width: cellSize, height: cellSize)
                                .help("\(date.formatted(date: .abbreviated, time: .omitted)): \(intensity == 0 ? "No study activity" : "Study activity level \(intensity) of 4")")
                                .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted)), activity \(intensity) of 4")
                        }
                    }
                }
                // Legend
                HStack(spacing: IBSpacing.sm) {
                    Spacer()
                    Text("Less").font(.system(size: 9)).foregroundColor(IBColors.inkTertiary)
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2).fill(colorForIntensity(i)).frame(width: 10, height: 10)
                    }
                    Text("More").font(.system(size: 9)).foregroundColor(IBColors.inkTertiary)
                }
            }
        }
    }

    private func dayLabel(_ day: Int) -> String {
        ["", "M", "", "W", "", "F", ""][day]
    }

    private func monthLabel(for week: Int) -> some View {
        let date = dateFor(week: week, day: 0)
        return Text(Self.monthFormatter.string(from: date))
            .font(.system(size: 8))
            .foregroundColor(IBColors.inkTertiary)
            // Allow "Dec"/"Mar" to overflow their 12pt cell instead of clipping
            // while keeping the grid column alignment intact.
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: cellSize, alignment: .leading)
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private func dateFor(week: Int, day: Int) -> Date {
        let today = Calendar.current.startOfDay(for: Date())
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: today)
        let startOfWeek = cal.date(byAdding: .day, value: -(weekday - 1), to: today) ?? today
        let startDate = cal.date(byAdding: .weekOfYear, value: -(columns - 1 - week), to: startOfWeek) ?? today
        return cal.date(byAdding: .day, value: day, to: startDate) ?? today
    }

    private var activityByDay: [Date: Int] {
        let cal = Calendar.current
        var totals: [Date: (cards: Int, minutes: Double)] = [:]
        for activity in activities {
            let day = cal.startOfDay(for: activity.date)
            let existing = totals[day] ?? (0, 0)
            totals[day] = (existing.cards + activity.cardsReviewed, existing.minutes + activity.minutesStudied)
        }
        return totals.mapValues { StudyActivity.intensity(cardsReviewed: $0.cards, minutesStudied: $0.minutes) }
    }

    private func intensityFor(date: Date, in index: [Date: Int]) -> Int {
        index[Calendar.current.startOfDay(for: date)] ?? 0
    }

    private func colorForIntensity(_ level: Int) -> Color {
        switch level {
        case 0: return IBColors.border
        case 1: return IBColors.accent.opacity(0.25)
        case 2: return IBColors.accent.opacity(0.5)
        case 3: return IBColors.accent.opacity(0.75)
        default: return IBColors.accent
        }
    }
}
