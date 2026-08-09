import SwiftUI
import SwiftData

/// A stable week board for study planning. It deliberately avoids invisible
/// timeline hit targets: every day has one visible scheduling action and every
/// plan has one predictable tap target.
struct StudyCalendarView: View {
    let plans: [StudyPlan]
    let onTapPlan: (StudyPlan) -> Void
    let onDeletePlan: ((StudyPlan) -> Void)?
    let onSchedule: ((Date) -> Void)?

    @State private var selectedWeekOffset = 0
    @State private var now = IBLocalClock.now

    init(
        plans: [StudyPlan],
        onTapPlan: @escaping (StudyPlan) -> Void,
        onDeletePlan: ((StudyPlan) -> Void)? = nil,
        onSchedule: ((Date) -> Void)? = nil
    ) {
        self.plans = plans
        self.onTapPlan = onTapPlan
        self.onDeletePlan = onDeletePlan
        self.onSchedule = onSchedule
    }

    private var currentWeekStart: Date {
        let calendar = IBLocalClock.calendar
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let mondayOffset = weekday == 1 ? -6 : 2 - weekday
        return calendar.date(byAdding: .day, value: mondayOffset + selectedWeekOffset * 7, to: today) ?? today
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { IBLocalClock.calendar.date(byAdding: .day, value: $0, to: currentWeekStart) }
    }

    private var weekPlans: [StudyPlan] {
        let calendar = IBLocalClock.calendar
        let start = calendar.startOfDay(for: currentWeekStart)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return plans.filter { !$0.isCompleted && $0.scheduledDate >= start && $0.scheduledDate < end }
    }

    private var totalMinutes: Int { weekPlans.reduce(0) { $0 + $1.durationMinutes } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            LazyVStack(spacing: 0) {
                ForEach(Array(weekDays.enumerated()), id: \.element) { index, day in
                    dayRow(day)
                    if index < weekDays.count - 1 {
                        Divider().padding(.leading, 86)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(IBColors.surface)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(IBColors.cardBorder, lineWidth: 1))
        )
        .task {
            now = IBLocalClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = IBLocalClock.now
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(IBColors.electricBlue)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text("Week board").font(.callout.weight(.bold))
                Text(weekRange).font(.caption).foregroundStyle(IBColors.secondaryText)
            }

            Spacer(minLength: 12)

            HStack(spacing: 14) {
                calendarStat(value: "\(weekPlans.count)", label: "blocks")
                calendarStat(value: formatMinutes(totalMinutes), label: "planned")
            }

            HStack(spacing: 6) {
                Button { withAnimation(.snappy) { selectedWeekOffset -= 1 } } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Previous week")

                Button("Today") { withAnimation(.snappy) { selectedWeekOffset = 0 } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(IBColors.electricBlue)

                Button { withAnimation(.snappy) { selectedWeekOffset += 1 } } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Next week")
            }
        }
        .padding(14)
    }

    private func calendarStat(value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value).font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(IBColors.ink)
            Text(label).font(.caption2).foregroundStyle(IBColors.secondaryText)
        }
        .frame(minWidth: 48, alignment: .trailing)
    }

    private func dayRow(_ day: Date) -> some View {
        let isToday = IBLocalClock.calendar.isDate(day, inSameDayAs: now)
        let dayPlans = weekPlans.filter { IBLocalClock.calendar.isDate($0.scheduledDate, inSameDayAs: day) }
            .sorted { $0.scheduledDate < $1.scheduledDate }

        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isToday ? IBColors.electricBlue : IBColors.secondaryText)
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 18, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isToday ? IBColors.electricBlue : IBColors.ink)
            }
            .frame(width: 54, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                if dayPlans.isEmpty {
                    Text(isToday ? "No session planned today" : "Open for a focused session")
                        .font(.callout)
                        .foregroundStyle(IBColors.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                } else {
                    ForEach(dayPlans) { plan in
                        planBlock(plan)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onSchedule {
                Button {
                    onSchedule(defaultScheduleDate(on: day))
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(IBColors.secondaryText)
                .help("Schedule a study block on this day")
            }
        }
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isToday ? IBColors.electricBlue.opacity(0.04) : Color.clear)
        )
    }

    private func planBlock(_ plan: StudyPlan) -> some View {
        let tint = subjectColor(plan.subjectName)
        return Button { onTapPlan(plan) } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint)
                    .frame(width: 3, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.subjectName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(IBColors.ink)
                        .lineLimit(1)
                    Text(plan.selectionSummary)
                        .font(.caption)
                        .foregroundStyle(IBColors.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(timeLabel(plan.scheduledDate))
                        .font(.caption.weight(.semibold).monospacedDigit())
                    Text("\(plan.durationMinutes)m")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(IBColors.secondaryText)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(IBColors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(IBColors.surface))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(IBColors.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onDeletePlan {
                Button(role: .destructive) { onDeletePlan(plan) } label: {
                    Label("Delete block", systemImage: "trash")
                }
            }
        }
        .accessibilityLabel("\(plan.subjectName), \(plan.durationMinutes) minutes, \(plan.scheduleLabel)")
    }

    private var weekRange: String {
        let formatter = IBLocalClock.formatter(dateFormat: "d MMM")
        return "\(formatter.string(from: currentWeekStart)) - \(formatter.string(from: weekDays.last ?? currentWeekStart))"
    }

    private func defaultScheduleDate(on day: Date) -> Date {
        let calendar = IBLocalClock.calendar
        let candidate = calendar.date(bySettingHour: 16, minute: 0, second: 0, of: day) ?? day
        if calendar.isDate(day, inSameDayAs: now), candidate < now {
            return IBLocalClock.nextQuarterHour()
        }
        return candidate
    }

    private func timeLabel(_ date: Date) -> String {
        IBLocalClock.formatter(dateFormat: "HH:mm").string(from: date)
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder)m" }
        if remainder == 0 { return "\(hours)h" }
        return "\(hours)h \(remainder)m"
    }

    private func subjectAbbrev(_ name: String) -> String {
        switch name {
        case "English B": return "ENG"
        case "Russian A Literature": return "RUS"
        case "Biology": return "BIO"
        case "Mathematics AA": return "MATH"
        case "Economics": return "ECO"
        case "Business Management": return "BUS"
        case "Life": return "LIFE"
        case "Advanced Mathematics": return "ADV MATH"
        case "Fundamentals of the Universe": return "UNIVERSE"
        default: return String(name.prefix(8)).uppercased()
        }
    }

    private func subjectColor(_ name: String) -> Color {
        switch name {
        case "English B": return IBColors.englishColor
        case "Russian A Literature": return IBColors.russianColor
        case "Biology": return IBColors.biologyColor
        case "Mathematics AA": return IBColors.mathColor
        case "Economics": return IBColors.economicsColor
        case "Business Management": return IBColors.businessColor
        case "Life": return Color(hex: "0EA5E9")
        case "Advanced Mathematics": return Color(hex: "8B5CF6")
        case "Fundamentals of the Universe": return Color(hex: "6366F1")
        default: return IBColors.secondaryText
        }
    }
}

// Retained as a pure compatibility helper for restored backups/tests that still
// reason about the former timeline geometry. The week board no longer depends
// on pixel offsets for interaction.
nonisolated enum CalendarTimelineLayout: Sendable {
    static func offset(hour: Int, minute: Int, firstHour: Int, hourHeight: CGFloat) -> CGFloat {
        let clampedMinute = min(max(minute, 0), 59)
        return (CGFloat(hour - firstHour) + CGFloat(clampedMinute) / 60) * hourHeight
    }

    static func blockHeight(durationMinutes: Int, hourHeight: CGFloat) -> CGFloat {
        max(CGFloat(max(durationMinutes, 0)) / 60 * hourHeight, 48)
    }
}
