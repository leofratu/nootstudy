import SwiftUI

struct HeatmapView: View {
    let activities: [StudyActivity]
    private let columns = 52
    private let rows = 7
    private let cellSize: CGFloat = 12
    private let spacing: CGFloat = 3

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: spacing) {
                // Day labels
                HStack(spacing: spacing) {
                    Text("").frame(width: 24)
                    ForEach(0..<columns, id: \.self) { week in
                        if week % 4 == 0 { monthLabel(for: week) } else { Color.clear.frame(width: cellSize) }
                    }
                }
                // Grid
                ForEach(0..<rows, id: \.self) { day in
                    HStack(spacing: spacing) {
                        Text(dayLabel(day)).font(.system(size: 8)).foregroundColor(IBColors.mutedGray).frame(width: 24)
                        ForEach(0..<columns, id: \.self) { week in
                            let date = dateFor(week: week, day: day)
                            let intensity = intensityFor(date: date)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(colorForIntensity(intensity))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
                // Legend
                HStack(spacing: IBSpacing.sm) {
                    Spacer()
                    Text("Less").font(.system(size: 9)).foregroundColor(IBColors.mutedGray)
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2).fill(colorForIntensity(i)).frame(width: 10, height: 10)
                    }
                    Text("More").font(.system(size: 9)).foregroundColor(IBColors.mutedGray)
                }
            }
        }
    }

    private func dayLabel(_ day: Int) -> String {
        ["", "M", "", "W", "", "F", ""][day]
    }

    private func monthLabel(for week: Int) -> some View {
        let date = dateFor(week: week, day: 0)
        let fmt = DateFormatter(); fmt.dateFormat = "MMM"
        return Text(fmt.string(from: date)).font(.system(size: 8)).foregroundColor(IBColors.mutedGray).frame(width: cellSize)
    }

    private func dateFor(week: Int, day: Int) -> Date {
        let today = Date()
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: today)
        let startOfWeek = cal.date(byAdding: .day, value: -(weekday - 1), to: today)!
        let startDate = cal.date(byAdding: .weekOfYear, value: -(columns - 1 - week), to: startOfWeek)!
        return cal.date(byAdding: .day, value: day, to: startDate) ?? today
    }

    private func intensityFor(date: Date) -> Int {
        let cal = Calendar.current
        let target = cal.startOfDay(for: date)
        return activities.first { cal.startOfDay(for: $0.date) == target }?.intensity ?? 0
    }

    private func colorForIntensity(_ level: Int) -> Color {
        switch level {
        case 0: return IBColors.cardBorder
        case 1: return IBColors.electricBlue.opacity(0.25)
        case 2: return IBColors.electricBlue.opacity(0.5)
        case 3: return IBColors.electricBlue.opacity(0.75)
        default: return IBColors.electricBlue
        }
    }
}
