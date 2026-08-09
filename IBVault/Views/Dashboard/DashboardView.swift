import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(ReviewQueueManager.self) private var queueManager
    @Query private var profiles: [UserProfile]
    @Query(sort: \StudyCard.nextReviewDate) private var allCards: [StudyCard]
    @Query private var subjects: [Subject]
    @Query(sort: \StudySession.endDate, order: .reverse) private var studySessions: [StudySession]
    @Query private var academicAssessments: [AcademicAssessment]
    @Query private var academicMappings: [AcademicAssessmentMapping]
    @Query private var academicReports: [AcademicReportSnapshot]

    @State private var ariaService: ARIAService
    @State private var reviewScheduler = ReviewScheduler()
    @State private var showReview = false
    @State private var selectedSubjectForReview: Subject?
    @State private var greetingText = ""
    // Queue-health ratio cached alongside the due snapshot; computing it here
    // would re-scan every card in the store on every body evaluation.
    @State private var reviewProgress = 0.0

    private let metricColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    private struct EvidenceRow: Identifiable {
        let subject: Subject
        let evidence: ProgressEvidence

        var id: UUID { subject.id }
        var mastery: Double { evidence.blendedMastery ?? evidence.assessmentEvidence ?? 0 }
    }

    private var profile: UserProfile? { profiles.first }
    /// A single review-queue snapshot is shared with the sidebar and global
    /// review flow. Dashboard-local filtering previously allowed its count to
    /// disagree with the cards the review sheet could actually present.
    private var dueCards: [StudyCard] { queueManager.dueCards }

    private var sortedSubjects: [Subject] {
        subjects.sorted { $0.name < $1.name }
    }

    private var greeting: String {
        let hour = IBLocalClock.calendar.component(.hour, from: IBLocalClock.now)
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    init() {
        _ariaService = State(initialValue: ARIAServiceFactory.make())
    }

    var body: some View {
        // Scored once per render: ProgressEvidenceService.score walks cards,
        // assessments, mappings, reports, and sessions per subject, so letting
        // each section derive its own copy quadrupled that work per body pass.
        let evidence = evidenceRows
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    dashboardHeader
                    metricsGrid
                    assessmentCalibration(evidence: evidence)
                    focusGrid
                    subjectPortfolio(evidence: evidence)
                }
                .frame(maxWidth: 1240, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(IBColors.canvas)
            .navigationTitle("Today")
            .sheet(isPresented: $showReview, onDismiss: {
                reviewScheduler.analyze(context: context)
                // A completed review consumed the due queue; refresh the shared
                // queue snapshot so the sidebar badge is not stale until the
                // next tab change.
                recomputeDueCards()
            }) {
                ReviewSessionView(filterSubject: selectedSubjectForReview)
            }
            .task {
                reviewScheduler.analyze(context: context)
                recomputeDueCards()
            }
            .onChange(of: allCards) { _, _ in
                recomputeDueCards()
            }
            .onChange(of: studySessions) { _, _ in
                recomputeDueCards()
            }
        }
    }

    private func recomputeDueCards() {
        queueManager.refreshDueCards(context: context)
        recomputeReviewProgress()
        updateGreeting()
    }

    private func updateGreeting() {
        let readyCount: Int = queueManager.totalDueCount
        let deferredCount: Int = queueManager.deferredDueCount
        let greeting: String = ariaService.generateGreeting(
            readyCount: readyCount,
            deferredCount: deferredCount
        )
        greetingText = greeting
    }

    private func recomputeReviewProgress() {
        guard !allCards.isEmpty else {
            reviewProgress = 0
            return
        }
        let readyCount = allCards.filter { !$0.isDue }.count
        reviewProgress = min(1.0, max(0.0, Double(readyCount) / Double(allCards.count)))
    }

    private var dashboardHeader: some View {
        StudioPageHeader(
            eyebrow: "Today",
            title: "\(greeting), \(profile?.studentName.isEmpty == false ? profile?.studentName ?? "" : "there")",
            subtitle: headerSubtitle,
            symbol: "rectangle.3.group.fill"
        ) {
            if dueCards.isEmpty {
                NavigationLink {
                    StudyPlannerView()
                } label: {
                    Label("Plan a session", systemImage: "calendar.badge.plus")
                        .frame(minWidth: 132)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(IBColors.electricBlue)
            } else {
                Button {
                    selectedSubjectForReview = nil
                    showReview = true
                } label: {
                    Label("Start review", systemImage: "play.fill")
                        .frame(minWidth: 132)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(IBColors.electricBlue)
            }
        }
    }

    private var headerSubtitle: String {
        if !dueCards.isEmpty {
            return "\(dueCards.count) report-based cards are ready for spaced review."
        }
        if studySessions.isEmpty {
            return "Your report baseline is loaded. Start with a focused study block or build more recall cards."
        }
        return "Your queue is clear. Use the time to plan your next focused session."
    }

    private var subjectCountWithDue: Int {
        Set(dueCards.compactMap { $0.subject?.id }).count
    }

    private var evidenceRows: [EvidenceRow] {
        sortedSubjects.map { subject in
            EvidenceRow(
                subject: subject,
                evidence: ProgressEvidenceService.score(
                    subjectName: subject.name,
                    courseLevel: subject.level,
                    cards: subject.cards,
                    assessments: academicAssessments,
                    mappings: academicMappings,
                    reports: academicReports,
                    workSessions: studySessions
                )
            )
        }
    }

    private func scoredEvidenceCount(evidence: [EvidenceRow]) -> Int {
        evidence.reduce(0) { $0 + $1.evidence.scoredAssessmentCount }
    }

    private func averageEvidenceMastery(evidence: [EvidenceRow]) -> Int {
        let scored = evidence.filter { $0.evidence.assessmentEvidence != nil }
        guard !scored.isEmpty else { return 0 }
        let total = scored.reduce(0.0) { $0 + $1.mastery }
        return Int((total / Double(scored.count)) * 100)
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
                value: "\(Int(reviewProgress * 100))%",
                label: "Queue health",
                symbol: "checkmark.seal.fill",
                tint: IBColors.teal,
                detail: "Cards outside review"
            )
        }
    }

    private func assessmentCalibration(evidence: [EvidenceRow]) -> some View {
        let scoredCount = scoredEvidenceCount(evidence: evidence)
        let subjectCount = evidence.filter { $0.evidence.assessmentEvidence != nil }.count
        return HStack(alignment: .center, spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(IBColors.teal)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(IBGradient.tint(IBColors.teal))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(IBColors.teal.opacity(0.16), lineWidth: 1)
                        )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("Assessment baseline")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(IBColors.ink)
                Text(scoredCount == 0 ? "Add a report or assessment to calibrate subject mastery." : "Current subject mastery includes your scored reports and assessments.")
                    .font(.caption)
                    .foregroundStyle(IBColors.secondaryText)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(averageEvidenceMastery(evidence: evidence))%")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(IBColors.teal)
                Text("\(scoredCount) scored across \(subjectCount) subjects")
                    .font(.caption)
                    .foregroundStyle(IBColors.secondaryText)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .glassCard(cornerRadius: IBRadius.md)
    }

    private var focusGrid: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                reviewFocus
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                workspaceSignal
                    .frame(width: 330, alignment: .topLeading)
            }
            VStack(spacing: 16) {
                reviewFocus
                workspaceSignal
            }
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

            Text(greetingText)
                .font(.callout)
                .foregroundStyle(IBColors.ink)
                .lineSpacing(2)
                .textSelection(.enabled)
        }
        .padding(18)
        .glassCard()
    }

    private func subjectPortfolio(evidence: [EvidenceRow]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            StudioSectionHeader(
                "Your subjects",
                subtitle: "Mastery and review readiness at a glance",
                symbol: "books.vertical.fill",
                tint: IBColors.englishColor
            ) {
                HStack(spacing: 10) {
                    StudioPill(title: "\(sortedSubjects.count) ENROLLED", tint: IBColors.englishColor)
                    NavigationLink("View all") {
                        SubjectsGridView()
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(IBColors.electricBlue)
                }
            }

            if sortedSubjects.isEmpty {
                EmptyStateView(icon: "books.vertical", title: "No subjects yet", message: "Complete onboarding or add subjects to begin building a study plan.")
                    .frame(maxWidth: .infinity)
            } else {
                // Mastery comes from recall and imported assessment results;
                // legacy curriculum flags do not represent current evidence.
                // Reuse the render's single evidence pass instead of re-scoring.
                let masteryBySubject = Dictionary(
                    uniqueKeysWithValues: evidence.map { ($0.subject.id, $0.evidence.blendedMastery ?? 0) }
                )
                VStack(spacing: 0) {
                    ForEach(sortedSubjects, id: \.id) { subject in
                        NavigationLink {
                            SubjectDetailView(subject: subject)
                        } label: {
                            SubjectWorkspaceRow(subject: subject, dueCount: scopedDueCount(for: subject), mastery: masteryBySubject[subject.id] ?? 0)
                        }
                        .buttonStyle(.plain)
                        if subject.id != sortedSubjects.last?.id {
                            Divider().padding(.leading, 72)
                        }
                    }
                }
                .glassCard()
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
