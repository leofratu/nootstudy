import Charts
import SwiftData
import SwiftUI

struct EffectivenessView: View {
    @Query private var profiles: [UserProfile]
    @Query(sort: \StudyActivity.date, order: .reverse) private var activity: [StudyActivity]
    @State private var selectedMomentumDate: Date?

    private var profile: UserProfile? { profiles.first }

    private let methods: [(name: String, multiplier: Double, icon: String, color: Color, desc: String)] = [
        ("Re-reading notes", 1.0, "doc.text", Color.gray, "Passive review — lowest retention"),
        ("Highlighting", 1.05, "highlighter", Color.yellow.opacity(0.8), "Minimal active processing"),
        ("Summarising", 1.15, "list.bullet.rectangle", Color.orange, "Some elaboration benefit"),
        ("Teaching others", 1.4, "person.2.fill", Color.blue.opacity(0.7), "Feynman technique effect"),
        ("Practice testing", 1.5, "checkmark.circle", Color.green.opacity(0.8), "Active recall — strong yield"),
        ("IB Vault (SR + AR)", 1.7, "sparkles", IBColors.electricBlue, "Spaced repetition × active recall")
    ]

    private var personalMultiplier: Double {
        guard let p = profile else { return 1.7 }
        let streakBonus = min(Double(p.currentStreak) * 0.02, 0.3)
        let consistencyBonus = activity.count > 7 ? 0.1 : 0.0
        return 1.7 + streakBonus + consistencyBonus
    }

    private var streakBonus: Double {
        guard let p = profile else { return 0 }
        return min(Double(p.currentStreak) * 0.02, 0.3)
    }

    private var consistencyBonus: Double {
        activity.count > 7 ? 0.1 : 0.0
    }

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
            return momentumRows.min(by: {
                abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target))
            })
        }

        guard !momentumRows.isEmpty else { return nil }
        return momentumRows.last(where: { $0.minutes > 0 || $0.cards > 0 || $0.xp > 0 }) ?? momentumRows.last
    }

    private var activeDays: Int {
        momentumRows.filter { $0.minutes > 0 || $0.cards > 0 || $0.xp > 0 }.count
    }

    private var projectedRereadingHours: Double {
        personalMultiplier == 0 ? 0 : personalMultiplier
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Hero multiplier
                multiplierHero
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                momentumCard
                    .padding(.horizontal, 24)

                // Method comparison
                methodComparisonCard
                    .padding(.horizontal, 24)

                // Time equivalence
                timeCard
                    .padding(.horizontal, 24)

                // Science section
                scienceCard
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .background(.background)
        .navigationTitle("Effectiveness")
    }

    // MARK: - Multiplier Hero
    private var multiplierHero: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text(String(format: "%.1f×", personalMultiplier))
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                        .foregroundStyle(IBColors.electricBlue)
                    Text("Your Multiplier")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Divider().frame(height: 60)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(IBColors.electricBlue)
                        Text("Base method")
                        Spacer()
                        Text("1.7×")
                            .font(.callout.bold())
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("Streak bonus")
                        Spacer()
                        Text(String(format: "+%.2f×", streakBonus))
                            .font(.callout.bold())
                            .foregroundStyle(.orange)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("Consistency")
                        Spacer()
                        Text(String(format: "+%.2f×", consistencyBonus))
                            .font(.callout.bold())
                            .foregroundStyle(.green)
                    }
                }
                .font(.callout)
            }

            if let profile {
                HStack(spacing: 6) {
                    Text("🔥")
                    Text("\(profile.currentStreak) day streak")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
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
                Text("Focus Effect")
                    .font(.headline)
                Spacer()
                Text("Last 14 days")
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
                    .cornerRadius(6)

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
                    .symbolSize(selectedMomentumRow?.date == row.date ? 80 : 36)
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
                AxisMarks(values: .stride(by: .day, count: 2)) { value in
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
                        Text("\(activeDays) active days in the last 14")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    statPill(value: "\(Int(selectedMomentumRow.minutes))m", label: "Study", color: IBColors.electricBlue)
                    statPill(value: "\(selectedMomentumRow.cards)", label: "Cards", color: IBColors.success)
                    statPill(value: "+\(selectedMomentumRow.xp)", label: "XP", color: .yellow)
                }
            }
        }
        .padding(16)
        .glassCard()
    }

    // MARK: - Method Comparison
    private var methodComparisonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.tint)
                Text("Method Comparison")
                    .font(.headline)
            }

            Chart(methods, id: \.name) { method in
                BarMark(
                    x: .value("Multiplier", method.multiplier),
                    y: .value("Method", method.name)
                )
                .foregroundStyle(method.color.gradient)
                .cornerRadius(6)

                RuleMark(x: .value("Your multiplier", personalMultiplier))
                    .foregroundStyle(IBColors.electricBlue.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .frame(height: 220)
            .chartXAxis {
                AxisMarks(position: .bottom, values: .stride(by: 0.25)) { value in
                    AxisTick()
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                        .foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel()
                }
            }

            ForEach(methods, id: \.name) { method in
                HStack(spacing: 10) {
                    Image(systemName: method.icon)
                        .foregroundStyle(method.color)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(method.name)
                                .font(.callout.weight(.medium))
                            Spacer()
                            Text(String(format: "%.1f×", method.multiplier))
                                .font(.callout.bold())
                                .foregroundStyle(method.color)
                        }
                        MasteryBar(
                            progress: method.multiplier / 2.0,
                            height: 6,
                            color: method.color
                        )
                        Text(method.desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                if method.name != methods.last?.name {
                    Divider()
                }
            }
        }
        .padding(16)
        .glassCard()
    }

    // MARK: - Time Equivalence
    private var timeCard: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.title2)
                    .foregroundStyle(IBColors.electricBlue)
                Text("1 hour")
                    .font(.title3.bold())
                Text("with IB Vault")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                Text("≈")
                    .font(.title.bold())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40)

            VStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("\(Int((projectedRereadingHours * 60).rounded()))m")
                    .font(.title3.bold())
                Text("of re-reading")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .glassCard()
    }

    // MARK: - Science
    private var scienceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(.tint)
                Text("Learning Science")
                    .font(.headline)
            }

            Text("Practice testing and distributed practice are consistently high-utility learning strategies. IB Vault combines both by scheduling review and requiring retrieval instead of passive re-reading.")
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .glassCard()
    }

    private func statPill(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.callout.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.08))
        )
    }
}
