import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \StudyCard.nextReviewDate) private var allCards: [StudyCard]
    @Query private var subjects: [Subject]
    @Query(sort: \StudySession.endDate, order: .reverse) private var studySessions: [StudySession]

    @State private var ariaService = ARIAService()
    @State private var reviewScheduler = ReviewScheduler()
    @State private var showReview = false
    @State private var selectedSubjectForReview: Subject?

    private let metricColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
    private let subjectColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    private var profile: UserProfile? { profiles.first }

    private var studiedScopes: [StudyScope] {
        StudySession.uniqueStudyScopes(from: studySessions)
    }

    private var dueCards: [StudyCard] {
        guard !studiedScopes.isEmpty else { return [] }
        return allCards.filter { card in
            card.isDue && studiedScopes.contains { $0.matches(card) }
        }
    }

    private var sortedSubjects: [Subject] {
        subjects.sorted { $0.name < $1.name }
    }

    private var reviewProgress: Double {
        guard !allCards.isEmpty else { return 0 }
        return Double(allCards.filter { !$0.isDue }.count) / Double(allCards.count)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    dashboardHeader
                    metricsGrid
                    focusGrid
                    subjectPortfolio
                }
                .frame(maxWidth: 1240, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(IBColors.canvas)
            .navigationTitle("Dashboard")
            .sheet(isPresented: $showReview) {
                ReviewSessionView(filterSubject: selectedSubjectForReview)
            }
            .task {
                reviewScheduler.analyze(context: context)
            }
        }
    }

    private var dashboardHeader: some View {
        StudioPageHeader(
            eyebrow: "Study workspace",
            title: "\(greeting), \(profile?.studentName.isEmpty == false ? profile?.studentName ?? "" : "there")",
            subtitle: headerSubtitle,
            symbol: "rectangle.3.group.fill"
        ) {
            Button {
                selectedSubjectForReview = nil
                showReview = true
            } label: {
                Label(dueCards.isEmpty ? "Plan a session" : "Start review", systemImage: dueCards.isEmpty ? "calendar.badge.plus" : "play.fill")
                    .frame(minWidth: 132)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(IBColors.electricBlue)
            .disabled(dueCards.isEmpty)
        }
    }

    private var headerSubtitle: String {
        if studySessions.isEmpty {
            return "Complete a study session to unlock a review plan built from your work."
        }
        if dueCards.isEmpty {
            return "Your queue is clear. Use the time to plan your next focused session."
        }
        return "\(dueCards.count) cards need your attention across \(subjectCountWithDue) subjects."
    }

    private var subjectCountWithDue: Int {
        Set(dueCards.compactMap { $0.subject?.id }).count
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: metricColumns, spacing: 12) {
            StudioMetricTile(
                value: "\(dueCards.count)",
                label: "Due now",
                symbol: "clock.badge.exclamationmark",
                tint: dueCards.isEmpty ? IBColors.success : IBColors.coral,
                detail: dueCards.isEmpty ? "Queue clear" : "Ready to review"
            )
            StudioMetricTile(
                value: "\(profile?.currentStreak ?? 0)d",
                label: "Study streak",
                symbol: "flame.fill",
                tint: IBColors.gold,
                detail: "\(profile?.longestStreak ?? 0)d personal best"
            )
            StudioMetricTile(
                value: "\(profile?.totalXP ?? 0)",
                label: "Learning XP",
                symbol: "bolt.fill",
                tint: IBColors.electricBlue,
                detail: profile?.achievedStep.displayName ?? "Building momentum"
            )
            StudioMetricTile(
                value: "\(Int(reviewProgress * 100))%",
                label: "Queue health",
                symbol: "checkmark.seal.fill",
                tint: IBColors.teal,
                detail: "Cards outside review"
            )
        }
    }

    private var focusGrid: some View {
        HStack(alignment: .top, spacing: 16) {
            reviewFocus
                .frame(maxWidth: .infinity, alignment: .topLeading)
            workspaceSignal
                .frame(width: 330, alignment: .topLeading)
        }
    }

    private var reviewFocus: some View {
        VStack(alignment: .leading, spacing: 16) {
            StudioSectionHeader(
                "Review queue",
                subtitle: dueCards.isEmpty ? "Nothing urgent right now" : "Prioritized by schedule",
                symbol: "brain.head.profile",
                tint: IBColors.electricBlue
            ) {
                StudioPill(title: dueCards.isEmpty ? "CLEAR" : "\(dueCards.count) DUE", tint: dueCards.isEmpty ? IBColors.success : IBColors.coral)
            }

            if dueCards.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(IBColors.success)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You are caught up")
                            .font(.callout.weight(.bold))
                        Text("New cards will appear here when they are ready for review.")
                            .font(.caption)
                            .foregroundStyle(IBColors.secondaryText)
                    }
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(reviewScheduler.schedules.prefix(4).enumerated()), id: \.element.id) { index, schedule in
                        Button {
                            selectedSubjectForReview = schedule.subject
                            showReview = true
                        } label: {
                            DashboardQueueRow(schedule: schedule)
                        }
                        .buttonStyle(.plain)

                        if index < min(reviewScheduler.schedules.count, 4) - 1 {
                            Divider().padding(.leading, 28)
                        }
                    }
                }

                Button {
                    selectedSubjectForReview = nil
                    showReview = true
                } label: {
                    Label("Review all due cards", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(18)
        .glassCard()
    }

    private var workspaceSignal: some View {
        VStack(alignment: .leading, spacing: 16) {
            StudioSectionHeader(
                "Study signal",
                subtitle: "ARIA's next suggestion",
                symbol: "sparkles",
                tint: IBColors.teal
            ) {
                EmptyView()
            }

            Text(ariaService.generateGreeting(context: context))
                .font(.callout)
                .foregroundStyle(IBColors.ink)
                .lineSpacing(2)
                .textSelection(.enabled)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                NavigationLink {
                    StudyPlannerView()
                } label: {
                    DashboardToolRow(symbol: "calendar.badge.clock", tint: IBColors.electricBlue, title: "Plan a study block", detail: "Set the next focused session")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    SmartRecommendationsView()
                } label: {
                    DashboardToolRow(symbol: "lightbulb.fill", tint: IBColors.gold, title: "See recommendations", detail: "Prioritize your next action")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    AnalyticsView()
                } label: {
                    DashboardToolRow(symbol: "chart.line.uptrend.xyaxis", tint: IBColors.teal, title: "Check momentum", detail: "Review learning performance")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .glassCard()
    }

    private var subjectPortfolio: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudioSectionHeader(
                "Your subjects",
                subtitle: "Mastery and review readiness at a glance",
                symbol: "books.vertical.fill",
                tint: IBColors.englishColor
            ) {
                StudioPill(title: "\(sortedSubjects.count) ENROLLED", tint: IBColors.englishColor)
            }

            if sortedSubjects.isEmpty {
                EmptyStateView(icon: "books.vertical", title: "No subjects yet", message: "Complete onboarding or add subjects to begin building a study plan.")
                    .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: subjectColumns, spacing: 12) {
                    ForEach(sortedSubjects, id: \.id) { subject in
                        NavigationLink {
                            SubjectDetailView(subject: subject)
                        } label: {
                            DashboardSubjectTile(subject: subject, dueCount: scopedDueCount(for: subject))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func scopedDueCount(for subject: Subject) -> Int {
        dueCards.filter { $0.subject?.id == subject.id }.count
    }
}

private struct DashboardQueueRow: View {
    let schedule: SubjectReviewSchedule

    private var tint: Color { Color(hex: schedule.subject.accentColorHex) }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(tint)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(schedule.subject.name)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(IBColors.ink)
                Text("\(schedule.subject.level) study queue")
                    .font(.caption)
                    .foregroundStyle(IBColors.secondaryText)
            }
            Spacer()
            Text("\(schedule.dueCards)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(IBColors.ink)
            Text("due")
                .font(.caption)
                .foregroundStyle(IBColors.secondaryText)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(IBColors.tertiaryText)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

private struct DashboardToolRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(IBColors.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(IBColors.secondaryText)
            }
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(IBColors.tertiaryText)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

private struct DashboardSubjectTile: View {
    let subject: Subject
    let dueCount: Int

    private var tint: Color { Color(hex: subject.accentColorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(subject.name)
                        .font(.headline)
                        .foregroundStyle(IBColors.ink)
                        .lineLimit(1)
                    StudioPill(title: subject.level, tint: tint)
                }
                Spacer()
                Text("\(Int(subject.masteryProgress * 100))%")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
            }

            MasteryBar(progress: subject.masteryProgress, height: 6, color: tint)

            HStack(spacing: 12) {
                Label("\(subject.cards.count) cards", systemImage: "square.stack")
                Spacer()
                Label(dueCount == 0 ? "Clear" : "\(dueCount) due", systemImage: dueCount == 0 ? "checkmark.circle" : "clock")
                    .foregroundStyle(dueCount == 0 ? IBColors.success : IBColors.coral)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(IBColors.secondaryText)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: IBRadius.card)
                .fill(IBColors.surface)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint)
                        .frame(width: 3)
                        .padding(.vertical, 16)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: IBRadius.card)
                        .stroke(IBColors.cardBorder, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
    }
}
