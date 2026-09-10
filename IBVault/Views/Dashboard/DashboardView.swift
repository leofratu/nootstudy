import SwiftUI
import os
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
    @State private var cachedEvidence: [EvidenceRow] = []
    @State private var evidenceFingerprint = ""
    @State private var dueRefreshTask: Task<Void, Never>?

    private let metricColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

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
        allCards.filter { $0.totalReviewCount == 0 }.count
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
                    externalWorkPrompt
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
                recomputeDueCards()
            }) {
                ReviewSessionView(filterSubject: selectedSubjectForReview)
            }
            .task {
                reviewScheduler.analyze(context: context)
                recomputeDueCards()
                refreshEvidenceIfNeeded()
            }
            .onChange(of: allCards) { _, _ in scheduleDueRefresh() }
            .onChange(of: studySessions) { _, _ in scheduleDueRefresh() }
            .onChange(of: subjects) { _, _ in refreshEvidenceIfNeeded() }
            .onChange(of: academicAssessments) { _, _ in refreshEvidenceIfNeeded() }
            .onChange(of: academicMappings) { _, _ in refreshEvidenceIfNeeded() }
            .onChange(of: academicReports) { _, _ in refreshEvidenceIfNeeded() }
        }
    }

    private func recomputeDueCards() {
        queueManager.refreshDueCards(context: context)
        updateGreeting()
    }

    private func updateGreeting() {
        let readyCount: Int = queueManager.totalDueCount
        let greeting: String = ariaService.generateGreeting(readyCount: readyCount, deferredCount: 0)
        greetingText = greeting
    }

    private var dashboardHeader: some View {
        StudioPageHeader(
            eyebrow: "Today",
            title: "\(greeting), \(profile?.studentName.isEmpty == false ? profile?.studentName ?? "" : "there")",
            subtitle: headerSubtitle,
            symbol: "rectangle.3.group"
        ) {
            if dueCards.isEmpty {
                NavigationLink {
                    StudyPlannerView()
                } label: {
                    Label("Plan a session", systemImage: "calendar.badge.plus")
                        .frame(minWidth: 132)
                }
                .buttonStyle(PrimaryButtonStyle())
                .controlSize(.large)
            } else {
                Button {
                    selectedSubjectForReview = nil
                    showReview = true
                } label: {
                    Label("Start review", systemImage: "play.fill")
                        .frame(minWidth: 132)
                }
                .buttonStyle(PrimaryButtonStyle())
                .controlSize(.large)
            }
        }
    }

    private var headerSubtitle: String {
        if dueBacklogCount > 0 {
            return "\(dueBacklogCount) flashcards are due and available for review."
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
        if !cachedEvidence.isEmpty { return cachedEvidence }
        if sortedSubjects.isEmpty { return [] }
        let state = PerformanceSignposts.signposter.beginInterval("dashboard.evidence")
        defer { PerformanceSignposts.signposter.endInterval("dashboard.evidence", state) }
        return sortedSubjects.map { subject in
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

    private var evidenceFingerprintValue: String {
        let subjectKey = sortedSubjects.map { "\($0.id.uuidString)-\($0.cards.count)-\($0.level)" }.joined(separator: "|")
        return "\(subjectKey)#\(academicAssessments.count)#\(academicMappings.count)#\(academicReports.count)#\(studySessions.count)"
    }

    private func refreshEvidenceIfNeeded() {
        let fingerprint = evidenceFingerprintValue
        guard fingerprint != evidenceFingerprint else { return }
        evidenceFingerprint = fingerprint
        let state = PerformanceSignposts.signposter.beginInterval("dashboard.evidence")
        defer { PerformanceSignposts.signposter.endInterval("dashboard.evidence", state) }
        cachedEvidence = sortedSubjects.map { subject in
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

    private func scheduleDueRefresh() {
        dueRefreshTask?.cancel()
        dueRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
            recomputeDueCards()
        }
    }

    private var externalWorkPrompt: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(IBColors.inkTertiary)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 7).fill(IBColors.surfaceHover).overlay(RoundedRectangle(cornerRadius: 7).stroke(IBColors.border, lineWidth: 1)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Worked outside Noot?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(IBColors.ink)
                Text("Add tutoring, Anki, or reading so it counts toward your history.")
                    .font(IBTypography.caption11)
                    .foregroundStyle(IBColors.inkSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            NavigationLink {
                ExternalActivityView()
            } label: {
                Label("Add work", systemImage: "plus")
            }
            .buttonStyle(SecondaryButtonStyle())
            .controlSize(.small)
            .accessibilityLabel("Add external work")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .surfaceCard(cornerRadius: IBRadius.md)
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
                value: "\(dueBacklogCount)",
                label: "Due today",
                symbol: "rectangle.stack",
                detail: dueBacklogCount == 0 ? "No cards due" : "\(dueBacklogCount) to review"
            )
            StudioMetricTile(
                value: "\(profile?.currentStreak ?? 0)d",
                label: "Study streak",
                symbol: "flame",
                detail: "\(profile?.longestStreak ?? 0)d best"
            )
            StudioMetricTile(
                value: "\(newCardsCount)",
                label: "New cards",
                symbol: "sparkles",
                detail: newCardsCount == 0 ? "No new cards" : "Not yet studied"
            )
        }
    }

    private func assessmentCalibration(evidence: [EvidenceRow]) -> some View {
        let scoredCount = scoredEvidenceCount(evidence: evidence)
        let subjectCount = evidence.filter { $0.evidence.assessmentEvidence != nil }.count
        let isEmpty = scoredCount == 0
        return HStack(alignment: .center, spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(IBColors.inkTertiary)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(IBColors.surfaceHover).overlay(RoundedRectangle(cornerRadius: 10).stroke(IBColors.border, lineWidth: 1)))

            VStack(alignment: .leading, spacing: 3) {
                Text("Assessment baseline")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(IBColors.ink)
                Text(isEmpty ? "Add a report or assessment to calibrate subject mastery." : "Current subject mastery includes your scored reports and assessments.")
                    .font(IBTypography.caption11)
                    .foregroundStyle(IBColors.inkSecondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(averageEvidenceMastery(evidence: evidence))%")
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                    .foregroundStyle(isEmpty ? IBColors.inkSecondary : IBColors.ink)
                Text("\(scoredCount) scored · \(subjectCount) subjects")
                    .font(IBTypography.caption11)
                    .foregroundStyle(IBColors.inkTertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .surfaceCard(cornerRadius: IBRadius.md)
    }

    private var focusGrid: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                reviewFocus.frame(maxWidth: .infinity, alignment: .topLeading)
                workspaceSignal.frame(width: 330, alignment: .topLeading)
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
                symbol: "brain.head.profile"
            ) {
                StudioPill(title: dueCards.isEmpty ? "CLEAR" : "\(dueCards.count) DUE", semantic: .neutral)
            }

            if dueCards.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 26))
                        .foregroundStyle(IBColors.inkTertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You are caught up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(IBColors.ink)
                        Text("New cards will appear here when they are ready for review.")
                            .font(IBTypography.caption11)
                            .foregroundStyle(IBColors.inkSecondary)
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
                            Rectangle().fill(IBColors.border).frame(height: 1).padding(.leading, 28)
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
                .buttonStyle(PrimaryButtonStyle())
                .controlSize(.large)
            }
        }
        .padding(18)
        .surfaceCard()
    }

    private var workspaceSignal: some View {
        VStack(alignment: .leading, spacing: 16) {
            StudioSectionHeader(
                "Study signal",
                subtitle: "ARIA's next suggestion",
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
        .padding(18)
        .surfaceCard()
    }

    private var studySignalText: String {
        let trimmed = greetingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let fallback = fallbackStudySignal { return fallback }
        return "You're making steady progress — pick a subject below to keep the momentum."
    }

    private var fallbackStudySignal: String? {
        if dueBacklogCount > 0 {
            let subjectCount = subjectCountWithDue
            if subjectCount > 1 {
                return "You have \(dueBacklogCount) cards due across \(subjectCount) subjects. Start with the top queue item to clear the most urgent cards first."
            }
            return "You have \(dueBacklogCount) cards due. A quick 15-minute review now will keep your queue healthy."
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
                "Your subjects",
                subtitle: "Mastery and review readiness at a glance",
                symbol: "books.vertical"
            ) {
                HStack(spacing: 10) {
                    StudioPill(title: "\(sortedSubjects.count) ENROLLED", semantic: .neutral)
                    NavigationLink("View all") {
                        SubjectsGridView()
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(IBColors.accent)
                }
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
                        }
                        .buttonStyle(.plain)
                        if subject.id != sortedSubjects.last?.id {
                            Rectangle().fill(IBColors.border).frame(height: 1).padding(.leading, 72)
                        }
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
    let schedule: SubjectReviewSchedule
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(IBColors.inkTertiary)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(schedule.subject.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(IBColors.ink)
                Text("\(schedule.subject.level) · study queue")
                    .font(IBTypography.caption11)
                    .foregroundStyle(IBColors.inkTertiary)
            }
            Spacer()
            Text("\(schedule.dueCards)")
                .font(.system(size: 20, weight: .semibold).monospacedDigit())
                .foregroundStyle(IBColors.ink)
            Text("due")
                .font(IBTypography.caption11)
                .foregroundStyle(IBColors.inkTertiary)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(IBColors.inkTertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
