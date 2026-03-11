import SwiftUI
import SwiftData

struct AnalyticsView: View {
    @Query(sort: \StudyActivity.date, order: .reverse) private var activities: [StudyActivity]
    @Query private var subjects: [Subject]
    @Query(sort: \ReviewSession.timestamp, order: .reverse) private var sessions: [ReviewSession]

    private var weeklyActivities: [StudyActivity] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        return activities.filter { $0.date >= weekAgo }
    }

    private var weeklySessions: [ReviewSession] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        return sessions.filter { $0.timestamp >= weekAgo }
    }

    private var activityRows: [(date: Date, cards: Int, xp: Int, minutes: Int)] {
        let grouped = Dictionary(grouping: weeklyActivities) { Calendar.current.startOfDay(for: $0.date) }
        return Array(grouped.map { date, entries in
            (
                date: date,
                cards: entries.reduce(0) { $0 + $1.cardsReviewed },
                xp: entries.reduce(0) { $0 + $1.xpEarned },
                minutes: Int(entries.reduce(0.0) { $0 + $1.minutesStudied })
            )
        }.sorted { $0.date > $1.date }.prefix(7))
    }

    private var retentionRows: [(date: Date, rate: Double)] {
        let grouped = Dictionary(grouping: weeklySessions) { Calendar.current.startOfDay(for: $0.timestamp) }
        return grouped.keys.sorted(by: >).map { date in
            (date: date, rate: ProficiencyTracker.retentionRate(from: grouped[date] ?? []))
        }
    }

    private var weeklyCards: Int { weeklyActivities.reduce(0) { $0 + $1.cardsReviewed } }
    private var weeklyXP: Int { weeklyActivities.reduce(0) { $0 + $1.xpEarned } }
    private var weeklyMinutes: Int { Int(weeklyActivities.reduce(0.0) { $0 + $1.minutesStudied }) }
    private var weeklyRetention: Int { Int(ProficiencyTracker.retentionRate(from: weeklySessions) * 100) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Week overview stats
                    statsHeader
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                    // Daily activity
                    activityCard
                        .padding(.horizontal, 24)

                    // Subject breakdown & Retention side by side
                    HStack(alignment: .top, spacing: 16) {
                        subjectBreakdownCard
                        retentionCard
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .background(.background)
            .navigationTitle("Analytics")
        }
    }

    // MARK: - Stats Header
    private var statsHeader: some View {
        HStack(spacing: 0) {
            StatCard(value: "\(weeklyCards)", label: "Cards Reviewed", color: IBColors.electricBlue, icon: "square.stack.fill")
            Divider().frame(height: 50)
            StatCard(value: "\(weeklyXP)", label: "XP Earned", color: .yellow, icon: "star.fill")
            Divider().frame(height: 50)
            StatCard(value: "\(weeklyMinutes)m", label: "Study Time", color: IBColors.success, icon: "clock.fill")
            Divider().frame(height: 50)
            StatCard(value: "\(weeklyRetention)%", label: "Retention", color: IBColors.englishColor, icon: "brain.head.profile")
        }
        .padding(.vertical, 16)
        .glassCard()
    }

    // MARK: - Activity
    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.tint)
                Text("Daily Activity")
                    .font(.headline)
                Spacer()
                Text("Last 7 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if activityRows.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "chart.bar")
                            .font(.title)
                            .foregroundStyle(.tertiary)
                        Text("No study activity this week.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
            } else {
                // Activity bars
                ForEach(activityRows, id: \.date) { row in
                    HStack(spacing: 12) {
                        Text(row.date, format: .dateTime.weekday(.abbreviated).day())
                            .font(.callout.weight(.medium))
                            .frame(width: 60, alignment: .leading)

                        MasteryBar(
                            progress: Double(row.cards) / max(Double(activityRows.map(\.cards).max() ?? 1), 1),
                            height: 8,
                            color: IBColors.electricBlue
                        )

                        HStack(spacing: 10) {
                            Label("\(row.cards)", systemImage: "square.stack")
                            Label("+\(row.xp)", systemImage: "star.fill")
                            Label("\(row.minutes)m", systemImage: "clock")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 200, alignment: .trailing)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .glassCard()
    }

    // MARK: - Subject Breakdown
    private var subjectBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "books.vertical.fill")
                    .foregroundStyle(.tint)
                Text("Subjects")
                    .font(.headline)
            }

            if subjects.isEmpty {
                Text("No subjects yet.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(subjects.sorted(by: { $0.name < $1.name }), id: \.id) { subject in
                    let mastery = ProficiencyTracker.masteryPercentage(for: subject)
                    let weak = ProficiencyTracker.weakTopics(for: subject)
                    let color = Color(hex: subject.accentColorHex)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color)
                                .frame(width: 3, height: 16)
                            Text(subject.name)
                                .font(.callout.weight(.medium))
                            Text(subject.level)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(mastery * 100))%")
                                .font(.callout.bold())
                                .foregroundStyle(color)
                        }
                        MasteryBar(progress: mastery, height: 5, color: color)

                        if !weak.isEmpty {
                            Text("Focus: \(weak.prefix(2).map(\.topicName).joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 2)
                    if subject.id != subjects.sorted(by: { $0.name < $1.name }).last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(16)
        .glassCard()
    }

    // MARK: - Retention
    private var retentionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.tint)
                Text("Daily Retention")
                    .font(.headline)
            }

            if retentionRows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                    Text("Complete more reviews to see retention data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                ForEach(retentionRows, id: \.date) { row in
                    HStack {
                        Text(row.date, format: .dateTime.weekday(.abbreviated).day())
                            .font(.callout)
                            .frame(width: 60, alignment: .leading)
                        MasteryBar(
                            progress: row.rate,
                            height: 8,
                            color: retentionColor(row.rate)
                        )
                        Text("\(Int(row.rate * 100))%")
                            .font(.callout.bold())
                            .foregroundStyle(retentionColor(row.rate))
                            .frame(width: 45, alignment: .trailing)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .glassCard()
    }

    private func retentionColor(_ rate: Double) -> Color {
        if rate >= 0.8 { return IBColors.success }
        if rate >= 0.5 { return IBColors.warning }
        return IBColors.danger
    }
}
