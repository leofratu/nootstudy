import SwiftUI
import os
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(ReviewQueueManager.self) private var queueManager
    @Query private var profiles: [UserProfile]
    @Query private var subjects: [Subject]
    @Query(sort: \StudySession.endDate, order: .reverse) private var studySessions: [StudySession]
    @Query private var academicAssessments: [AcademicAssessment]
    @Query private var academicMappings: [AcademicAssessmentMapping]
    @Query private var academicReports: [AcademicReportSnapshot]

    @State private var ariaService: ARIAService
    @State private var showReview = false
    @State private var selectedSubjectForReview: Subject?
    @State private var greetingText = ""
    @State private var cachedEvidence: [EvidenceRow] = []
    @State private var dueRefreshTask: Task<Void, Never>?

    private let metricColumns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)

    private struct EvidenceRow: Identifiable {
        let subject: Subject
        let evidence: ProgressEvidence
        var id: UUID { subject.id }
        var mastery: Double { evidence.blendedMastery ?? evidence.assessmentEvidence ?? 0 }
    }

    private var profile: UserProfile? { profiles.first }
    private var dueCards: [StudyCard] { queueManager.dueCards }
    private var dueBacklogCount: Int { queueManager.totalDueBacklogCount }

    private var sortedSubjects: [Subject] {
        subjects.sorted { $0.name < $1.name }
    }

    private var greeting: String {
        let hour = IBLocalClock.calendar.component(.hour, from: IBLocalClock.now)
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    private var newCardsCount: Int {
        queueManager.newCardCount
    }

    init() {
        _ariaService = State(initialValue: ARIAServiceFactory.make())
    }

    var body: some View {
        let evidence = evidenceRows
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    dashboardHeader
                    metricsGrid
                    focusGrid
                    subjectPortfolio(evidence: evidence)
                    footerRows(evidence: evidence)
                }
                .frame(maxWidth: 1080, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(IBColors.canvas)
            .navigationTitle("Today")
            .sheet(isPresented: $showReview, onDismiss: {
                recomputeDueCards()
                refreshEvidenceIfNeeded()
            }) {
                ReviewSessionView(filterSubject: selectedSubjectForReview)
            }
            .task {
                await Task.yield()
                guard !Task.isCancelled else { return }
                recomputeDueCards()
                refreshEvidenceIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in scheduleDueRefresh() }
            .onChange(of: studySessions) { _, _ in scheduleDueRefresh() }
            .onChange(of: subjects) { _, _ in refreshEvidenceIfNeeded() }
            .onChange(of: academicAssessments) { _, _ in refreshEvidenceIfNeeded() }
            .onChange(of: academicMappings) { _, _ in refreshEvidenceIfNeeded() }
            .onChange(of: academicReports) { _, _ in refreshEvidenceIfNeeded() }
            .onDisappear { dueRefreshTask?.cancel() }
        }
    }

    private func recomputeDueCards() {
        queueManager.ensureLoaded(context: context)
        updateGreeting()
    }

    private func updateGreeting() {
        let readyCount: Int = queueManager.totalDueCount
        let greeting: String = ariaService.generateGreeting(readyCount: readyCount, deferredCount: queueManager.deferredDueCount)
        greetingText = greeting
    }

    private var dashboardHeader: some View {
        StudioPageHeader(
            eyebrow: "Today",
            title: "\(greeting), \(profile?.studentName.isEmpty == false ? profile?.studentName ?? "" : "there")",
            subtitle: headerSubtitle,
            symbol: "rectangle.3.group"
        ) {
            HStack(spacing: 8) {
                NavigationLink { CardStudioView() } label: { Text("Create flashcards") }
                    .buttonStyle(SecondaryButtonStyle())
                if dueCards.isEmpty {
                    NavigationLink { StudyPlannerView() } label: { Text("Plan a session") }
                        .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button("Start review") {
                        selectedSubjectForReview = nil
                        showReview = true
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    private var headerSubtitle: String {
        if let error = queueManager.lastRefreshError { return error }
        if queueManager.remainingDailyAllowance == 0 {
            return "You've hit your daily limit. Your remaining cards will wait until tomorrow."
        }
        if !dueCards.isEmpty {
            return "\(dueCards.count) cards are ready for review."
        }
        if studySessions.isEmpty {
            return "Pick a topic, make a set, and build your understanding."
        }
        return "Your queue is clear. Use the time to plan your next focused session."
    }

    private var subjectCountWithDue: Int {
        Set(dueCards.compactMap { $0.subject?.id }).count
    }

    private var evidenceRows: [EvidenceRow] {
        cachedEvidence
    }

    private func refreshEvidenceIfNeeded() {
        let state = PerformanceSignposts.signposter.beginInterval("dashboard.evidence")
        defer { PerformanceSignposts.signposter.endInterval("dashboard.evidence", state) }
        let scores = ProgressEvidenceService.scoreBySubject(subjects: subjects,
            assessments: academicAssessments, mappings: academicMappings,
            reports: academicReports, workSessions: studySessions)
        cachedEvidence = sortedSubjects.compactMap { subject in
            scores[subject.id].map { EvidenceRow(subject: subject, evidence: $0) }
        }
    }

    private func scheduleDueRefresh() {
        dueRefreshTask?.cancel()
        dueRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            if Task.isCancelled { return }
            recomputeDueCards()
            refreshEvidenceIfNeeded()
        }
    }

    private func footerRows(evidence: [EvidenceRow]) -> some View {
        let scoredCount = scoredEvidenceCount(evidence: evidence)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(scoredCount == 0
                     ? "Add a report or assessment to calibrate subject mastery."
                     : "Mastery includes \(scoredCount) scored assessments, averaging \(averageEvidenceMastery(evidence: evidence))%.")
                    .foregroundStyle(IBColors.inkTertiary)
            }
            HStack(spacing: 6) {
                Text("Worked outside Noot?")
                    .foregroundStyle(IBColors.inkTertiary)
                NavigationLink("Add tutoring, Anki or reading") { ExternalActivityView() }
                    .buttonStyle(.link)
            }
        }
        .font(IBTypography.caption)
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
        LazyVGrid(columns: metricColumns, spacing: 16) {
            StudioMetricTile(
                value: "\(queueManager.reviewedTodayCount)",
                label: "of \(queueManager.dailyGoal) card goal",
                symbol: "rectangle.stack"
            )
            StudioMetricTile(
                value: "\(dueBacklogCount)",
                label: "Cards due",
                symbol: "tray"
            )
            StudioMetricTile(
                value: "\(newCardsCount)",
                label: "Not yet studied",
                symbol: "sparkles"
            )
            StudioMetricTile(
                value: "\(profile?.currentStreak ?? 0)",
                label: "Day streak",
                symbol: "flame"
            )
        }
    }

    private var focusGrid: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                reviewFocus.frame(maxWidth: .infinity, alignment: .topLeading)
                workspaceSignal.frame(width: 300, alignment: .topLeading)
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
                subtitle: dueCards.isEmpty ? nil : "Pick a subject, or start with everything",
                symbol: "brain.head.profile"
            ) {
                EmptyView()
            }

            if dueCards.isEmpty {
                Text(queueManager.remainingDailyAllowance == 0
                     ? "You've hit today's limit. It resets tomorrow."
                     : "You're caught up. Cards appear here when they are ready.")
                    .font(IBTypography.body13)
                    .foregroundStyle(IBColors.inkSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(subjectsWithDueCards.prefix(5), id: \.id) { subject in
                        Button {
                            selectedSubjectForReview = subject
                            showReview = true
                        } label: {
                            DashboardQueueRow(subject: subject, dueCount: queueManager.dueCount(for: subject))
                        }
                        .buttonStyle(IBPressStyle())
                    }
                }
            }
        }
        .padding(20)
        .surfaceCard()
    }

    private var subjectsWithDueCards: [Subject] {
        sortedSubjects
            .filter { queueManager.dueCount(for: $0) > 0 }
            .sorted { queueManager.dueCount(for: $0) > queueManager.dueCount(for: $1) }
    }

    private var workspaceSignal: some View {
        VStack(alignment: .leading, spacing: 16) {
            StudioSectionHeader(
                "Coach's note",
                symbol: "sparkles"
            ) {
                EmptyView()
            }
            Text(studySignalText)
                .font(IBTypography.body13)
                .foregroundStyle(IBColors.inkSecondary)
                .lineSpacing(2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .surfaceCard()
    }

    private var studySignalText: String {
        let trimmed = greetingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let fallback = fallbackStudySignal { return fallback }
        return "You're making steady progress — pick a subject below to keep the momentum."
    }

    private var fallbackStudySignal: String? {
        if queueManager.remainingDailyAllowance == 0 {
            return "You've hit your daily limit. Take a break; the backlog can wait."
        }
        if !dueCards.isEmpty {
            let subjectCount = subjectCountWithDue
            if subjectCount > 1 {
                return "You have \(dueCards.count) cards ready today across \(subjectCount) subjects."
            }
            return "You have \(dueCards.count) cards ready to review."
        }
        if let weakest = evidenceRows.min(by: { $0.mastery < $1.mastery }), weakest.mastery < 0.7 {
            return "\(weakest.subject.name) is your current focus (\(Int(weakest.mastery*100))% mastery). Generate a few fresh cards or review its weakest subunit."
        }
        if let first = sortedSubjects.first {
            return "\(first.name) is ready for a deeper dive. Create a focused session to build new recall breadth."
        }
        return nil
    }

    private func subjectPortfolio(evidence: [EvidenceRow]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            StudioSectionHeader(
                "Subjects",
                symbol: "books.vertical"
            ) {
                NavigationLink("View all") {
                    SubjectsGridView()
                }
                .buttonStyle(.link)
                .font(IBTypography.caption)
            }

            if sortedSubjects.isEmpty {
                EmptyStateView(icon: "books.vertical", title: "No subjects yet", message: "Complete onboarding or add subjects to begin building a study plan.")
                    .frame(maxWidth: .infinity)
            } else {
                let masteryBySubject = Dictionary(uniqueKeysWithValues: evidence.map { ($0.subject.id, $0.evidence.blendedMastery ?? 0) })
                LazyVStack(spacing: 0) {
                    ForEach(sortedSubjects, id: \.id) { subject in
                        NavigationLink {
                            SubjectDetailView(subject: subject)
                        } label: {
                            SubjectWorkspaceRow(subject: subject, dueCount: scopedDueCount(for: subject), mastery: masteryBySubject[subject.id] ?? 0)
                                .hoverHighlight(cornerRadius: IBRadius.card)
                        }
                        .buttonStyle(IBPressStyle())
                    }
                }
                .surfaceCard()
            }
        }
    }

    private func scopedDueCount(for subject: Subject) -> Int {
        dueCards.filter { $0.subject?.id == subject.id }.count
    }
}

private struct DashboardQueueRow: View {
    let subject: Subject
    let dueCount: Int
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(IBColors.subjectColor(for: subject.name))
                .frame(width: 7, height: 7)
            Text(subject.name)
                .font(.system(size: 13))
                .foregroundStyle(IBColors.ink)
            Text(subject.level)
                .font(IBTypography.caption11)
                .foregroundStyle(IBColors.inkTertiary)
            Spacer()
            Text("\(dueCount)")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(IBColors.inkSecondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(IBColors.inkTertiary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .hoverHighlight()
    }
}
