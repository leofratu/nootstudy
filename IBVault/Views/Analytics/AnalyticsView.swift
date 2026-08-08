import SwiftUI
import SwiftData

struct AnalyticsView: View {
    @Query private var subjects: [Subject]
    @Query(sort: \ReviewSession.timestamp, order: .reverse) private var reviewSessions: [ReviewSession]
    @Query(sort: \StudySession.endDate, order: .reverse) private var studySessions: [StudySession]
    @Query private var assessments: [AcademicAssessment]
    @Query private var mappings: [AcademicAssessmentMapping]
    @Query private var reports: [AcademicReportSnapshot]
    @State private var selectedRange: AnalyticsRange = .sevenDays

    private enum AnalyticsRange: String, CaseIterable, Identifiable {
        case sevenDays = "7 days"
        case thirtyDays = "30 days"
        case allTime = "All time"

        var id: String { rawValue }
        var dayCount: Int? {
            switch self {
            case .sevenDays: return 7
            case .thirtyDays: return 30
            case .allTime: return nil
            }
        }
    }

    private var cutoffDate: Date? {
        guard let dayCount = selectedRange.dayCount else { return nil }
        return IBLocalClock.calendar.date(byAdding: .day, value: -dayCount, to: IBLocalClock.now)
    }

    private var filteredStudySessions: [StudySession] {
        guard let cutoffDate else { return studySessions }
        return studySessions.filter { $0.endDate >= cutoffDate }
    }

    private var filteredReviewSessions: [ReviewSession] {
        guard let cutoffDate else { return reviewSessions }
        return reviewSessions.filter { $0.timestamp >= cutoffDate }
    }

    private var activityRows: [(date: Date, cards: Int, xp: Int, minutes: Int)] {
        let calendar = IBLocalClock.calendar
        let sessionsByDay = Dictionary(grouping: filteredStudySessions) { calendar.startOfDay(for: $0.endDate) }
        let reviewsByDay = Dictionary(grouping: filteredReviewSessions) { calendar.startOfDay(for: $0.timestamp) }
        let dates = Set(sessionsByDay.keys).union(reviewsByDay.keys)
        var rows: [(date: Date, cards: Int, xp: Int, minutes: Int)] = []
        rows.reserveCapacity(dates.count)
        for date in dates {
            let sessions = sessionsByDay[date] ?? []
            let reviews = reviewsByDay[date] ?? []
            let xp = sessions.reduce(into: 0) { total, session in total += session.xpEarned }
            let seconds = sessions.reduce(into: 0.0) { total, session in total += max(0, session.duration) }
            rows.append((
                date: date,
                cards: reviews.count,
                xp: xp,
                minutes: Int(seconds / 60)
            ))
        }
        rows.sort { $0.date > $1.date }
        return Array(rows.prefix(selectedRange.dayCount ?? 90))
    }

    private var retentionRows: [(date: Date, rate: Double)] {
        let grouped = Dictionary(grouping: filteredReviewSessions) { IBLocalClock.calendar.startOfDay(for: $0.timestamp) }
        return grouped.keys.sorted(by: >).map { date in
            (date: date, rate: ProficiencyTracker.retentionRate(from: grouped[date] ?? []))
        }
    }

    private var rangeCards: Int { filteredReviewSessions.count }
    private var rangeXP: Int { filteredStudySessions.reduce(0) { $0 + $1.xpEarned } }
    private var rangeMinutes: Int { Int(filteredStudySessions.reduce(0.0) { $0 + max(0, $1.duration) } / 60) }
    private var rangeRetention: Int? {
        guard !filteredReviewSessions.isEmpty else { return nil }
        return Int(ProficiencyTracker.retentionRate(from: filteredReviewSessions) * 100)
    }

    /// Sorted once per render with mastery/weak topics computed a single time
    /// per subject, instead of re-sorting subjects and re-scanning every card
    /// set for each tile.
    private var subjectBreakdownRows: [SubjectBreakdownRow] {
        subjects
            .sorted { $0.name < $1.name }
            .map { SubjectBreakdownRow(
                subject: $0,
                mastery: ProgressEvidenceService.score(
                    subjectName: $0.name,
                    courseLevel: $0.level,
                    cards: $0.cards,
                    assessments: assessments,
                    mappings: mappings,
                    reports: reports,
                    workSessions: studySessions
                ).blendedMastery ?? 0,
                weakTopics: ProficiencyTracker.weakTopics(for: $0)
            ) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    StudioPageHeader(
                        eyebrow: "Learning intelligence",
                        title: "Analytics",
                        subtitle: "Measure consistency, retrieval quality, and the subjects that need a different plan.",
                        symbol: "chart.xyaxis.line",
                        tint: IBColors.teal
                    ) {
                        Picker("Range", selection: $selectedRange) {
                            ForEach(AnalyticsRange.allCases) { range in
                                Text(range.rawValue).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 250)
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        StudioMetricTile(value: "\(rangeCards)", label: "Cards reviewed", symbol: "square.stack.fill", tint: IBColors.electricBlue, detail: selectedRange.rawValue)
                        StudioMetricTile(value: "\(rangeXP)", label: "XP earned", symbol: "bolt.fill", tint: IBColors.gold, detail: "Completed sessions")
                        StudioMetricTile(value: "\(rangeMinutes)m", label: "Study time", symbol: "clock.fill", tint: IBColors.teal, detail: "Completed sessions")
                        StudioMetricTile(value: rangeRetention.map { "\($0)%" } ?? "—", label: "Retention", symbol: "brain.head.profile", tint: IBColors.englishColor, detail: rangeRetention == nil ? "No rated reviews" : "Across rated cards")
                    }

                    activityCard

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)],
                        alignment: .leading,
                        spacing: 16
                    ) {
                        subjectBreakdownCard
                        retentionCard
                    }
                }
                .frame(maxWidth: 1240, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(IBColors.canvas)
            .navigationTitle("Analytics")
        }
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
                Text(selectedRange.rawValue)
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
                // Activity bars — hoist the peak so rows don't each re-scan the range.
                let peakCards = max(Double(activityRows.map(\.cards).max() ?? 1), 1)
                ForEach(activityRows, id: \.date) { row in
                    HStack(spacing: 12) {
                        Text(row.date, format: .dateTime.weekday(.abbreviated).day())
                            .font(.callout.weight(.medium))
                            .frame(width: 60, alignment: .leading)

                        MasteryBar(
                            progress: Double(row.cards) / peakCards,
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
        let rows = subjectBreakdownRows
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "books.vertical.fill")
                    .foregroundStyle(.tint)
                Text("Subjects")
                    .font(.headline)
            }

            if rows.isEmpty {
                Text("No subjects yet.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(rows, id: \.subject.id) { row in
                    let color = Color(hex: row.subject.accentColorHex)
                    let weak = row.weakTopics

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color)
                                .frame(width: 3, height: 16)
                            Text(row.subject.name)
                                .font(.callout.weight(.medium))
                            Text(row.subject.level)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(row.mastery * 100))%")
                                .font(.callout.bold())
                                .foregroundStyle(color)
                        }
                        MasteryBar(progress: row.mastery, height: 5, color: color)

                        if !weak.isEmpty {
                            Text("Focus: \(weak.prefix(2).map(\.topicName).joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 2)
                    if row.subject.id != rows.last?.subject.id {
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

// MARK: - Breakdown Row
/// Subject + per-render mastery/weak-topic snapshot used by the breakdown card.
private struct SubjectBreakdownRow {
    let subject: Subject
    let mastery: Double
    let weakTopics: [StudyCard]
}
