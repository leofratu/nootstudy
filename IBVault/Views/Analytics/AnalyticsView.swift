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

    var body: some View {
        NavigationStack {
            List {
                overviewSection
                activitySection
                subjectBreakdownSection
                retentionSection
            }
            .listStyle(.inset)
            .controlSize(.small)
            .navigationTitle("Analytics")
        }
    }

    private var overviewSection: some View {
        Section("Last 7 Days") {
            LabeledContent("Cards reviewed", value: "\(weeklyActivities.reduce(0) { $0 + $1.cardsReviewed })")
            LabeledContent("XP earned", value: "\(weeklyActivities.reduce(0) { $0 + $1.xpEarned })")
            LabeledContent("Study time", value: "\(Int(weeklyActivities.reduce(0.0) { $0 + $1.minutesStudied })) min")
            LabeledContent("Retention", value: "\(Int(ProficiencyTracker.retentionRate(from: weeklySessions) * 100))%")
        }
    }

    private var activitySection: some View {
        Section("Daily Activity") {
            if activityRows.isEmpty {
                Text("No study activity recorded this week.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(activityRows, id: \.date) { row in
                    HStack {
                        Text(row.date, format: .dateTime.weekday(.abbreviated).day())
                        Spacer()
                        Text("\(row.cards) cards")
                            .foregroundStyle(.secondary)
                        Text("\(row.xp) XP")
                            .foregroundStyle(.secondary)
                        Text("\(row.minutes)m")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var subjectBreakdownSection: some View {
        Section("Subjects") {
            ForEach(subjects, id: \.id) { subject in
                let mastery = ProficiencyTracker.masteryPercentage(for: subject)
                let weak = ProficiencyTracker.weakTopics(for: subject)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(subject.name)
                        Spacer()
                        Text("\(Int(mastery * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    Text(subject.level)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: mastery)
                    if !weak.isEmpty {
                        Text("Weak topics: \(weak.prefix(3).map(\.topicName).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var retentionSection: some View {
        Section("Retention") {
            if retentionRows.isEmpty {
                Text("Complete more reviews to see daily retention.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(retentionRows, id: \.date) { row in
                    LabeledContent(
                        row.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                        value: "\(Int(row.rate * 100))%"
                    )
                }
            }
        }
    }
}
