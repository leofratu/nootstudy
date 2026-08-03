import Charts
import SwiftData
import SwiftUI

struct EffectivenessView: View {
    @Query private var profiles: [UserProfile]
    @Query(sort: \StudyActivity.date, order: .reverse) private var activity: [StudyActivity]
    @State private var selectedMomentumDate: Date?

    private var profile: UserProfile? { profiles.first }

    private var momentumRows: [(date: Date, minutes: Double, cards: Int, xp: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let grouped = Dictionary(grouping: activity) { calendar.startOfDay(for: $0.date) }

        return (0..<14).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset - 13, to: today) else { return nil }
            let entries = grouped[date] ?? []
            return (
                date: date,
                minutes: entries.reduce(0.0) { $0 + $1.minutesStudied },
                cards: entries.reduce(0) { $0 + $1.cardsReviewed },
                xp: entries.reduce(0) { $0 + $1.xpEarned }
            )
        }
    }

    private var selectedMomentumRow: (date: Date, minutes: Double, cards: Int, xp: Int)? {
        if let selectedMomentumDate {
            let target = Calendar.current.startOfDay(for: selectedMomentumDate)
            return momentumRows.min {
                abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target))
            }
        }
        return momentumRows.last(where: { $0.minutes > 0 || $0.cards > 0 || $0.xp > 0 }) ?? momentumRows.last
    }

    private var activeDays: Int {
        momentumRows.filter { $0.minutes > 0 || $0.cards > 0 || $0.xp > 0 }.count
    }

    private var reviewDays: Int {
        momentumRows.filter { $0.cards > 0 }.count
    }

    private var totalMinutes: Int {
        Int(momentumRows.reduce(0.0) { $0 + $1.minutes }.rounded())
    }

    private var totalCards: Int {
        momentumRows.reduce(0) { $0 + $1.cards }
    }

    private var totalXP: Int {
        momentumRows.reduce(0) { $0 + $1.xp }
    }

    private var activeDayProgress: Double { Double(activeDays) / 14.0 }
    private var reviewDayProgress: Double { Double(reviewDays) / 14.0 }

    private var consistencyLabel: String {
        switch activeDays {
        case 0: return "No activity recorded yet"
        case 1...3: return "A starting rhythm"
        case 4...7: return "A developing routine"
        case 8...11: return "A consistent routine"
        default: return "A strong two-week rhythm"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                recordHero
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                momentumCard
                    .padding(.horizontal, 24)

                recordedOutcomesCard
                    .padding(.horizontal, 24)

                scienceCard
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .background(.background)
        .navigationTitle("Learning Record")
    }

    private var recordHero: some View {
        HStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(IBColors.electricBlue.opacity(0.12))
                    .frame(width: 58, height: 58)
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(IBColors.electricBlue)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Your last 14 days")
                    .font(.title2.bold())
                Text(consistencyLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let profile, profile.currentStreak > 0 {
                    Label("\(profile.currentStreak)-day current streak", systemImage: "flame.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(activeDays)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(IBColors.electricBlue)
                Text("active days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .glassCard()
    }

    private var momentumCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.xyaxis.line")
                    .foregroundStyle(.tint)
                Text("Study Momentum")
                    .font(.headline)
                Spacer()
                Text("Minutes and reviewed cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(momentumRows, id: \.date) { row in
                    BarMark(
                        x: .value("Day", row.date),
                        y: .value("Minutes", row.minutes)
                    )
                    .foregroundStyle(IBColors.electricBlue.opacity(0.28))
                    .cornerRadius(5)

                    LineMark(
                        x: .value("Day", row.date),
                        y: .value("Cards", Double(row.cards))
                    )
                    .foregroundStyle(IBColors.success)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Day", row.date),
                        y: .value("Cards", Double(row.cards))
                    )
                    .foregroundStyle(IBColors.success)
                    .symbolSize(selectedMomentumRow?.date == row.date ? 80 : 30)
                }

                if let selectedMomentumRow {
                    RuleMark(x: .value("Selected", selectedMomentumRow.date))
                        .foregroundStyle(Color.primary.opacity(0.2))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .frame(height: 220)
            .chartXSelection(value: $selectedMomentumDate)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) {
                    AxisTick()
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                        .foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }

            if let selectedMomentumRow {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedMomentumRow.date, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                            .font(.headline)
                        Text("Recorded study activity")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    metric(value: "\(Int(selectedMomentumRow.minutes))m", label: "Study", color: IBColors.electricBlue)
                    metric(value: "\(selectedMomentumRow.cards)", label: "Cards", color: IBColors.success)
                    metric(value: "+\(selectedMomentumRow.xp)", label: "XP", color: .yellow)
                }
            }
        }
        .padding(16)
        .glassCard()
    }

    private var recordedOutcomesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.tint)
                Text("Recorded Outcomes")
                    .font(.headline)
                Spacer()
                Text("No estimated multipliers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            progressRow(
                icon: "calendar.badge.checkmark",
                title: "Active study days",
                value: "\(activeDays) of 14",
                progress: activeDayProgress,
                color: IBColors.electricBlue
            )
            progressRow(
                icon: "rectangle.stack.badge.play.fill",
                title: "Days with active recall",
                value: "\(reviewDays) of 14",
                progress: reviewDayProgress,
                color: IBColors.success
            )

            Divider()

            HStack(spacing: 0) {
                summaryMetric(value: "\(totalMinutes)m", label: "Study time")
                Divider().frame(height: 42)
                summaryMetric(value: "\(totalCards)", label: "Cards reviewed")
                Divider().frame(height: 42)
                summaryMetric(value: "\(totalXP)", label: "Learning XP")
            }
        }
        .padding(16)
        .glassCard()
    }

    private var scienceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(.tint)
                Text("Learning Science")
                    .font(.headline)
            }

            Text("Practice testing and distributed practice are well-supported learning strategies. IBVault records your use of both without converting them into an invented performance multiplier.")
                .foregroundStyle(.secondary)

            if let researchURL = URL(string: "https://doi.org/10.1177/1529100612453266") {
                Link(destination: researchURL) {
                    Label("Dunlosky et al. research review", systemImage: "arrow.up.right.square")
                        .font(.callout.weight(.semibold))
                }
            }
        }
        .padding(16)
        .glassCard()
    }

    private func progressRow(
        icon: String,
        title: String,
        value: String,
        progress: Double,
        color: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title).font(.callout.weight(.semibold))
                    Spacer()
                    Text(value).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                MasteryBar(progress: progress, height: 7, color: color)
            }
        }
    }

    private func summaryMetric(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func metric(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.callout.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 48)
    }
}
