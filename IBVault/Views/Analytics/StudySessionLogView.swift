import SwiftUI
import SwiftData

struct StudySessionLogView: View {
    @Query(sort: \StudySession.startDate, order: .reverse) private var sessions: [StudySession]

    private var groupedSessions: [(date: Date, sessions: [StudySession])] {
        let grouped = Dictionary(grouping: sessions) { Calendar.current.startOfDay(for: $0.startDate) }
        return grouped.map { (date: $0.key, sessions: $0.value) }
            .sorted { $0.date > $1.date }
    }

    private var weeklyStats: (sessions: Int, cards: Int, minutes: Int) {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let recent = sessions.filter { $0.startDate >= weekAgo }
        let totalCards = recent.reduce(0) { $0 + $1.cardsReviewed }
        let totalMinutes = Int(recent.reduce(0.0) { $0 + $1.duration } / 60)
        return (recent.count, totalCards, totalMinutes)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Stats
                statsHeader
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                if sessions.isEmpty {
                    emptyState
                        .padding(.top, 40)
                } else {
                    ForEach(groupedSessions, id: \.date) { group in
                        daySection(group.date, sessions: group.sessions)
                            .padding(.horizontal, 24)
                    }
                }

                Spacer().frame(height: 24)
            }
        }
        .background(.background)
        .navigationTitle("Study Log")
    }

    // MARK: - Stats Header
    private var statsHeader: some View {
        HStack(spacing: 0) {
            let s = weeklyStats
            StatCard(value: "\(s.sessions)", label: "Sessions", color: IBColors.electricBlue, icon: "book.fill")
            Divider().frame(height: 40)
            StatCard(value: "\(s.cards)", label: "Cards", color: .orange, icon: "square.stack.fill")
            Divider().frame(height: 40)
            StatCard(value: "\(s.minutes)m", label: "Study Time", color: .green, icon: "clock.fill")
        }
        .padding(.vertical, 12)
        .glassCard()
    }

    // MARK: - Day Section
    private func daySection(_ date: Date, sessions: [StudySession]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(date, format: .dateTime.weekday(.wide).month().day())
                    .font(.headline)
                Spacer()
                Text("\(sessions.count) session\(sessions.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(sessions, id: \.id) { session in
                sessionRow(session)
            }
        }
        .padding(16)
        .glassCard()
    }

    private func sessionRow(_ session: StudySession) -> some View {
        HStack(spacing: 12) {
            // Subject indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(subjectColor(session.subjectName))
                .frame(width: 4, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.subjectName)
                        .font(.callout.weight(.semibold))
                    if !session.topicsCovered.isEmpty {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(session.scopeSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 8) {
                    Label("\(session.cardsReviewed) cards", systemImage: "square.stack")
                    Label(session.durationFormatted, systemImage: "clock")
                    Label("\(session.retentionPercent)%", systemImage: "brain.head.profile")
                    if session.xpEarned > 0 {
                        Label("+\(session.xpEarned) XP", systemImage: "star.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Retention badge
            retentionBadge(session.retentionPercent)
        }
        .padding(.vertical, 4)
    }

    private func retentionBadge(_ percent: Int) -> some View {
        let color: Color = percent >= 80 ? .green : percent >= 50 ? .orange : .red
        return Text("\(percent)%")
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
            .foregroundStyle(color)
    }

    private func subjectColor(_ name: String) -> Color {
        switch name {
        case "English B": return IBColors.englishColor
        case "Russian A Literature": return IBColors.russianColor
        case "Biology": return IBColors.biologyColor
        case "Mathematics AA": return IBColors.mathColor
        case "Economics": return IBColors.economicsColor
        case "Business Management": return IBColors.businessColor
        default: return .gray
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No study sessions yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Complete a review session to start logging your progress.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
