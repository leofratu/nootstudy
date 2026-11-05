import SwiftUI
import SwiftData

struct ActiveStudySessionView: View {
    let plan: StudyPlan
    let onComplete: (() -> Void)? = nil
    /// Opens with the offline paper loaded, so the harness can show the exam.
    private let startsWithOfflinePaper: Bool
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ProgressionEventCenter.self) private var progressionEvents
    @Query private var profiles: [UserProfile]
    @Query private var subjects: [Subject]
    @Query(sort: \StudySession.endDate, order: .reverse) private var recentStudySessions: [StudySession]

    @State private var sessionStartDate = Date()
    @State private var didStartSession = false
    @State private var sessionControlStatus: String?
    @State private var isUpdatingDuration = false
    @State private var showExitConfirmation = false
    // Set only when the plan is completed through the check-in, so leaving early
    // can never collect the completion bonus.
    @State private var earnedCompletionBonus = false
    // Frozen at completion so the completion screen shows a stable duration
    // instead of a timer that keeps counting while the user reads the results.
    @State private var completedElapsed: TimeInterval = 0
    @State private var chatMessages: [(role: String, text: String)] = []
    @State private var chatInput = ""
    @State private var isChatting = false
    @State private var sessionNotes = ""
    @State private var noteSaveStatus = ""
    @State private var selectedTab: SessionTab = .plan
    @State private var generatedCards: [GeneratedFlashcard] = []
    @State private var isGeneratingCards = false
    @State private var flashcardTask: Task<Void, Never>?
    @State private var flashcardError: String?
    @State private var flashcardBatchSize = 10
    @State private var flashcardTopicName = ""
    @State private var flashcardSubtopicName = ""
    @State private var flashcardSelection: Set<CardTopicSelection> = []
    @State private var flashcardDifficulty = CardGenerationOptions.preferred.difficulty
    @State private var cardStudioOptions = CardGenerationOptions.preferred
    @State private var completedTaskIDs: Set<UUID> = []
    @State private var showRewardPulse = false
    /// XP already paid to the profile for rated cards, so finishing doesn't pay it twice.
    @State private var recordedRatingXP = 0
    @State private var previousStreak = 0
    @State private var completedStreak = 0
    @State private var revealedCards: Set<Int> = []
    @State private var examMarkdown = ""
    @State private var savedTestID = UUID()
    @State private var testSaveStatus: String?
    @State private var isSavingTest = false
    @State private var isGeneratingExam = false
    @State private var examGenerationTask: Task<Void, Never>?
    @State private var examGenerationError: String?
    @State private var examMaximumMarks = 20
    @State private var examResponse = ""
    @State private var examMarkScheme = ""
    @State private var examGradingMarkdown = ""
    @State private var isGradingExam = false
    @State private var markingTask: Task<Void, Never>?
    @State private var examGradingError: String?
    @State private var isCompletingSession = false
    @State private var isSessionComplete = false
    @State private var didPrepareFlashcards = false
    @State private var activeSessionID = UUID()
    @State private var cardRatings: [UUID: RecallQuality] = [:]
    @State private var persistedCardIDs: [UUID: UUID] = [:]
    @State private var showCompletionCheckIn = false
    @State private var confidenceByScope: [String: Int] = [:]
    @State private var completionError: String?
    // IDs of generated flashcards already persisted, so "Save" / "Save All"
    // cannot write the same card twice and create duplicates in the subject.
    @State private var savedCardIDs: Set<UUID> = []

    private typealias GeneratedFlashcard = CardDraft

    init(plan: StudyPlan, initialTab: SessionTab = .plan, startsWithOfflinePaper: Bool = false) {
        self.plan = plan
        self.startsWithOfflinePaper = startsWithOfflinePaper
        _selectedTab = State(initialValue: initialTab)
    }

    private struct EvidenceScope: Identifiable {
        let topicName: String
        let subtopicName: String

        var id: String { "\(topicName)|\(subtopicName)" }
        var title: String { subtopicName.isEmpty ? topicName : subtopicName }
    }

    private var unsavedGeneratedCards: [GeneratedFlashcard] {
        generatedCards.filter { !savedCardIDs.contains($0.id) }
    }

    private var flashcardBatchBinding: Binding<Int> {
        Binding(
            get: { flashcardBatchSize },
            set: { flashcardBatchSize = min(max($0, 1), CardGenerationOptions.maximumCount) }
        )
    }

    private var flashcardTopics: [String] {
        let topics = plan.selectedTopicNames.isEmpty ? [plan.topicName] : plan.selectedTopicNames
        return topics.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var flashcardSubtopics: [String] {
        guard let subject = subjects.first(where: { $0.name == plan.subjectName }) else {
            return plan.selectedSubtopicNames
        }
        let syllabusSubtopics = SyllabusSeeder.subtopics(
            for: subject.name,
            level: subject.level,
            topicName: flashcardTopicName
        )
        let selected = plan.selectedSubtopicNames.filter { syllabusSubtopics.contains($0) }
        return selected.isEmpty ? syllabusSubtopics : selected
    }

    private var sessionResources: [LearningResource] {
        LearningResourceCatalog.resources(
            for: plan.subjectName,
            topicNames: plan.selectedTopicNames,
            limit: 4
        )
    }

    private var flashcardUnitName: String {
        SyllabusSeeder.unitName(
            for: plan.subjectName,
            level: subjects.first(where: { $0.name == plan.subjectName })?.level ?? "",
            topicName: flashcardTopicName
        ) ?? "Selected unit"
    }

    private var examRubricCriteria: [IBExamRubric.Criterion] {
        IBExamRubric.criteria(for: plan.subjectName)
    }

    private var reviewedCardCount: Int { cardRatings.count }

    private var completedTaskCount: Int {
        completedTaskIDs.intersection(Set(plan.planTasks.map(\.id))).count
    }

    private var nextTask: StudyPlanTask? {
        plan.planTasks.first { !completedTaskIDs.contains($0.id) }
    }

    private var sessionAdvice: String {
        guard let subject = subjects.first(where: { $0.name == plan.subjectName }) else {
            return "Start with the first task, then close your notes and explain the selected scope before moving on."
        }
        let cards = subject.cards.filter {
            $0.topicName.caseInsensitiveCompare(flashcardTopicName) == .orderedSame &&
                (flashcardSubtopicName.isEmpty || $0.subtopic.caseInsensitiveCompare(flashcardSubtopicName) == .orderedSame)
        }
        let due = cards.filter(\.isDue).count
        if due > 0 {
            return "Begin with \(due) due recall card\(due == 1 ? "" : "s") for this subunit. Rate the answer honestly before reading the explanation."
        }
        if cards.isEmpty {
            return "Build the baseline for this subunit: generate a small set, reveal each answer, and rate every recall before moving to exam transfer."
        }
        let technique = SubjectKnowledge.knowledge(for: subject.name)?.examTechnique.first
            ?? "Use the command term and show the reasoning needed for the mark scheme."
        return "Your existing cards are the warm-up. Next, use the plan's application task. Coach cue: \(technique)"
    }

    private var correctReviewedCardCount: Int {
        cardRatings.values.filter { $0 == .good || $0 == .easy }.count
    }

    private var evidenceScopes: [EvidenceScope] {
        let topics = plan.selectedTopicNames.isEmpty ? [plan.topicName] : plan.selectedTopicNames
        let subtopics = plan.selectedSubtopicNames
        guard !subtopics.isEmpty else {
            return topics.filter { !$0.isEmpty }.map { EvidenceScope(topicName: $0, subtopicName: "") }
        }
        guard let subject = subjects.first(where: { $0.name == plan.subjectName }) else {
            let fallbackTopic = topics.first ?? plan.topicName
            return subtopics.map { EvidenceScope(topicName: fallbackTopic, subtopicName: $0) }
        }
        return subtopics.map { subtopic in
            let topic = topics.first {
                SyllabusSeeder.subtopics(
                    for: subject.name,
                    level: subject.level,
                    topicName: $0
                ).contains(subtopic)
            } ?? topics.first ?? plan.topicName
            return EvidenceScope(topicName: topic, subtopicName: subtopic)
        }
    }

    private var liveElapsed: TimeInterval {
        max(0, Date().timeIntervalSince(sessionStartDate))
    }

    private var elapsed: TimeInterval {
        completedElapsed > 0 ? completedElapsed : liveElapsed
    }

    private var dedicatedMinutes: Int {
        max(0, Int(elapsed / 60))
    }

    private var dedicatedMinutesDouble: Double {
        max(0, elapsed / 60)
    }

    private var priorSubjectSessions: [StudySession] {
        Array(recentStudySessions.filter {
            $0.id != activeSessionID && $0.subjectName.caseInsensitiveCompare(plan.subjectName) == .orderedSame
        }.prefix(10))
    }

    private var recentAverageMinutes: Int? {
        guard !priorSubjectSessions.isEmpty else { return nil }
        let total = priorSubjectSessions.reduce(0.0) { $0 + max(0, $1.duration) / 60 }
        return Int((total / Double(priorSubjectSessions.count)).rounded())
    }

    private var recentAverageRetention: Int? {
        let reviewed = priorSubjectSessions.filter { $0.cardsReviewed > 0 }
        guard !reviewed.isEmpty else { return nil }
        return reviewed.reduce(0) { $0 + $1.retentionPercent } / reviewed.count
    }

    enum SessionTab: String, CaseIterable {
        case plan = "Focus"
        case chat = "Coach"
        case flashcards = "Recall"
        case exam = "Practice"
        case notes = "Notes"

        var icon: String {
            switch self {
            case .plan: return "doc.text.fill"
            case .chat: return "sparkles"
            case .flashcards: return "rectangle.on.rectangle.angled"
            case .exam: return "pencil.and.list.clipboard"
            case .notes: return "note.text"
            }
        }
    }

    var body: some View {
        NavigationStack {
            if isSessionComplete {
                completionView
            } else {
                sessionWorkspace
            }
        }
        .frame(minWidth: 780, minHeight: 580)
        .onAppear {
            startTimer()
            if sessionNotes.isEmpty, !plan.notes.isEmpty {
                sessionNotes = plan.notes
            }
            initializeFlashcardScope()
            prepareFlashcardsIfRequested()
            if startsWithOfflinePaper, examMarkdown.isEmpty { useOfflineExam() }
        }
        .onDisappear {
            flashcardTask?.cancel()
            markingTask?.cancel()
            examGenerationTask?.cancel()
            saveSessionNotes()
        }
        .interactiveDismissDisabled(!isSessionComplete)
        .confirmationDialog("Leave this study session?", isPresented: $showExitConfirmation, titleVisibility: .visible) {
            Button("Save progress & leave") { finishSession(markPlanComplete: false) }
            Button("Leave without logging", role: .destructive) { dismiss() }
            Button("Keep studying", role: .cancel) {}
        } message: {
            Text("Saving logs your time and practice answer. Either way the plan stays open, and cards you already rated keep their schedule, XP and streak credit.")
        }
        .sheet(isPresented: $showCompletionCheckIn) {
            completionCheckIn
        }
    }

    private var sessionWorkspace: some View {
        VStack(spacing: 0) {
            sessionHeader
            if let sessionControlStatus {
                Text(sessionControlStatus)
                    .font(IBTypography.caption)
                    .foregroundStyle(IBColors.inkSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .transition(.opacity)
            }

            HStack(spacing: 0) {
                sessionTabBar
                    .frame(width: 184)
                    .background(IBColors.canvasDeep)

                panelContent
                    .id(selectedTab)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(IBColors.canvas)
            }

            Rectangle().fill(IBColors.border).frame(height: 1)

            bottomBar
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(IBColors.surface)
        }
        .animation(IBAnimation.page, value: selectedTab)
        .animation(IBAnimation.smooth, value: sessionControlStatus)
    }

    private func prepareFlashcardsIfRequested() {
        guard (plan.prepareFlashcards == true || plan.flashcardOnly == true), !didPrepareFlashcards else { return }
        didPrepareFlashcards = true
        selectedTab = .flashcards
        flashcardBatchSize = min(max(plan.flashcardTargetCount ?? CardGenerationOptions.preferred.count, 1), CardGenerationOptions.maximumCount)
        cardStudioOptions.count = flashcardBatchSize
        if let raw = plan.flashcardDifficultyRaw, let value = CardDifficulty(rawValue: raw) {
            flashcardDifficulty = value
            cardStudioOptions.difficulty = value
        }
        generateFlashcards()
    }

    private func initializeFlashcardScope() {
        guard flashcardTopicName.isEmpty else { return }
        flashcardTopicName = flashcardTopics.first ?? plan.topicName
        flashcardSubtopicName = flashcardSubtopics.first ?? ""
        let level = subjects.first(where: { $0.name == plan.subjectName })?.level ?? ""
        flashcardSelection = Set(flashcardTopics.flatMap { topic -> [CardTopicSelection] in
            let valid = SyllabusSeeder.subtopics(for: plan.subjectName, level: level, topicName: topic)
            let selected = plan.selectedSubtopicNames.filter { valid.contains($0) }
            return selected.isEmpty ? [.init(topic: topic)] : selected.map { .init(topic: topic, subtopic: $0) }
        })
    }

    // MARK: - Header

    private var sessionHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(plan.subjectName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(IBColors.ink)
                    Text(plan.selectionSummary)
                        .font(IBTypography.caption)
                        .foregroundStyle(IBColors.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(plan.selectionSummary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SessionClockView(startDate: sessionStartDate, durationMinutes: plan.durationMinutes)

                Menu {
                    ForEach([15, 30, 60], id: \.self) { minutes in
                        Button("Add \(minutes) minutes") { extendSession(by: minutes) }
                    }
                } label: {
                    Text(isUpdatingDuration ? "Saving…" : "Extend")
                }
                .menuStyle(.button)
                .controlSize(.small)
                .fixedSize()
                .disabled(isUpdatingDuration || isCompletingSession)
                .help("Add time without restarting the session")

                Button(isCompletingSession ? "Saving…" : "Leave") { showExitConfirmation = true }
                    .controlSize(.small)
                    .disabled(isCompletingSession || isUpdatingDuration)
                    .help("Leave the session")
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .frame(height: 54)
            .background(IBColors.surface)

            SessionTimeLine(startDate: sessionStartDate, durationMinutes: plan.durationMinutes)

            SessionOvertimePrompt(
                startDate: sessionStartDate,
                durationMinutes: plan.durationMinutes,
                isBusy: isUpdatingDuration || isCompletingSession,
                onExtend: extendSession(by:),
                onFinish: prepareCompletionCheckIn
            )
        }
    }

    private func extendSession(by minutes: Int) {
        guard !isUpdatingDuration, !isCompletingSession else { return }
        isUpdatingDuration = true
        defer { isUpdatingDuration = false }
        let previousDuration = plan.durationMinutes
        let previousEnd = plan.scheduledEndDate
        do {
            let extensionValue = try StudySessionDuration.extending(plan, by: minutes)
            plan.durationMinutes = extensionValue.minutes
            plan.scheduledEndDate = extensionValue.endDate
            try context.save()
            sessionControlStatus = "Added \(minutes) minutes. Session target: \(plan.durationMinutes) minutes."
        } catch {
            plan.durationMinutes = previousDuration
            plan.scheduledEndDate = previousEnd
            sessionControlStatus = "Could not extend the session: \(error.localizedDescription)"
        }
    }

    // MARK: - Tab Bar

    private var sessionTabBar: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(SessionTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13))
                            .foregroundStyle(selectedTab == tab ? IBColors.accent : IBColors.inkTertiary)
                            .frame(width: 18)
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: selectedTab == tab ? .medium : .regular))
                            .foregroundStyle(selectedTab == tab ? IBColors.ink : IBColors.inkSecondary)
                        Spacer(minLength: 0)
                        if tab == .flashcards && !generatedCards.isEmpty {
                            Text("\(generatedCards.count)")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(IBColors.inkTertiary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: IBRadius.sm)
                            .fill(selectedTab == tab ? IBColors.ink.opacity(0.07) : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .hoverHighlight()
                }
                .buttonStyle(IBPressStyle())
            }

            if let nextTask {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Up next")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(IBColors.inkTertiary)
                    Button { startTask(nextTask) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nextTask.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(IBColors.ink)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                            Text("\(nextTask.minutes) min")
                                .font(IBTypography.caption)
                                .foregroundStyle(IBColors.inkSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(IBPressStyle())
                    .help("Open this step")
                }
                .padding(.horizontal, 8)
                .padding(.top, 20)
            } else if !plan.planTasks.isEmpty {
                Label("Plan complete", systemImage: "checkmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(IBColors.success)
                    .padding(.horizontal, 8)
                    .padding(.top, 20)
            }

            Spacer(minLength: 16)

            FocusRhythmView()
                .padding(.horizontal, 8)
                .padding(.bottom, 12)

            if !plan.planTasks.isEmpty {
                MasteryBar(progress: Double(completedTaskCount) / Double(max(plan.planTasks.count, 1)), height: 3)
                    .padding(.horizontal, 8)
                Text("\(completedTaskCount) of \(plan.planTasks.count) steps")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(IBColors.inkTertiary)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }

    // MARK: - Plan Panel

    private var planPanel: some View {
        // Kept in its own subview so the heavy markdown parse is isolated from
        // this parent body's re-evaluations (tab switches, chat updates, etc.).
        PlanPanelView(
            plan: plan,
            completedTaskIDs: $completedTaskIDs,
            advice: sessionAdvice,
            resources: sessionResources,
            onStartTask: startTask
        )
    }

    private func startTask(_ task: StudyPlanTask) {
        withAnimation(IBAnimation.snappy) {
            completedTaskIDs.remove(task.id)
            switch task.activityType.lowercased() {
            case let value where value.contains("flash") || value.contains("recall"):
                selectedTab = .flashcards
            case let value where value.contains("exam") || value.contains("practice"):
                selectedTab = .exam
            case let value where value.contains("chat") || value.contains("explain"):
                selectedTab = .chat
            default:
                selectedTab = .plan
            }
        }
        if !task.subtopicName.isEmpty {
            flashcardTopicName = task.topicName
            flashcardSubtopicName = task.subtopicName
            flashcardSelection = [.init(topic: task.topicName, subtopic: task.subtopicName)]
        } else if !task.topicName.isEmpty {
            flashcardTopicName = task.topicName
            flashcardSubtopicName = ""
            flashcardSelection = [.init(topic: task.topicName)]
        }
    }

    @ViewBuilder
    private var panelContent: some View {
        switch selectedTab {
        case .plan: planPanel
        case .chat: chatPanel
        case .flashcards: flashcardsPanel
        case .exam: examPanel
        case .notes: notesPanel
        }
    }

    // MARK: - Chat Panel (Full ARIA Context)

    private var chatPanel: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if chatMessages.isEmpty {
                        emptyChat
                    }

                    ForEach(Array(chatMessages.enumerated()), id: \.offset) { index, msg in
                        HStack(alignment: .top, spacing: 8) {
                            if msg.role == "user" { Spacer(minLength: 60) }

                            if msg.role == "model" {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12))
                                    .foregroundStyle(IBColors.accent)
                                    .frame(width: 18)
                                    .padding(.top, 3)
                            }

                            FormattedMessageContent(text: msg.text)
                                .padding(msg.role == "user" ? 10 : 0)
                                .background(
                                    RoundedRectangle(cornerRadius: IBRadius.lg)
                                        .fill(msg.role == "user" ? IBColors.surfaceRaised : Color.clear)
                                )

                            if msg.role == "model" { Spacer(minLength: 60) }
                        }
                    }

                    if isChatting {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(IBColors.accent.opacity(0.08))
                                    .frame(width: 26, height: 26)
                                ProgressView()
                                    .controlSize(.mini)
                            }
                            Text("ARIA is thinking…")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(16)
            }

            Rectangle().fill(IBColors.border).frame(height: 1)

            // Input
            HStack(spacing: 8) {
                TextField("Ask about \(plan.studyScope.title)…", text: $chatInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit { sendMessage() }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(chatInput.isEmpty ? IBColors.inkTertiary : IBColors.accent)
                }
                .buttonStyle(IBPressStyle())
                .disabled(chatInput.isEmpty || isChatting)
                .help("Send message")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(IBColors.surface)
        }
    }

    private var emptyChat: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask your coach")
                .font(IBTypography.sectionTitle)
                .foregroundStyle(IBColors.ink)

            VStack(alignment: .leading, spacing: 2) {
                quickPrompt("Explain \(plan.studyScope.title) simply")
                quickPrompt("Give me a practice question")
                quickPrompt("What are common exam mistakes here?")
                quickPrompt("How is this assessed in the IB exam?")
                quickPrompt("Create a mnemonic for key terms")
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    // MARK: - Flashcards Panel

    private var flashcardsPanel: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                flashcardGenerationToolbar
                cardStudioPanel
                flashcardScopeSection
                flashcardStatusSection
                flashcardList
                saveAllGeneratedCardsButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 60)
        }
    }

    private var cardStudioPanel: some View {
        CardStudioOptionsView(options: $cardStudioOptions, showsCount: true)
            .disabled(isGeneratingCards)
            .onChange(of: cardStudioOptions.count) { _, new in flashcardBatchSize = new }
            .onChange(of: cardStudioOptions.difficulty) { _, new in flashcardDifficulty = new }
            .onChange(of: flashcardBatchSize) { _, new in cardStudioOptions.count = new }
            .onChange(of: flashcardDifficulty) { _, new in cardStudioOptions.difficulty = new }
    }

    private var flashcardGenerationToolbar: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Session flashcards")
                    .font(IBTypography.sectionTitle)
            }
            Spacer()
            if isGeneratingCards {
                ProgressView().controlSize(.small)
                Button("Cancel") { flashcardTask?.cancel() }
            } else {
                Button(action: generateFlashcards) {
                    Text(generatedCards.isEmpty ? "Generate \(cardStudioOptions.count)" : "Add \(cardStudioOptions.count) more")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private var flashcardScopeSection: some View {
        if let subject = subjects.first(where: { $0.name == plan.subjectName }) {
            DisclosureGroup("Choose topics · \(flashcardSelection.count) selected") {
                TopicSelectionView(subject: subject, selection: $flashcardSelection).padding(.top, 16)
            }
            .disabled(isGeneratingCards)
        }
    }

    @ViewBuilder
    private var flashcardStatusSection: some View {
        if generatedCards.isEmpty && !isGeneratingCards {
            ContentUnavailableView(
                "No session flashcards",
                systemImage: "rectangle.on.rectangle.angled",
                description: Text("Choose a topic and subunit, then generate a focused batch.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        if let flashcardError, !flashcardError.isEmpty {
            Label(flashcardError, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(IBColors.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var flashcardList: some View {
        ForEach(Array(generatedCards.enumerated()), id: \.element.id) { index, card in
            flashcardRow(card, index: index)
        }
    }

    private func flashcardRow(_ card: GeneratedFlashcard, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            flashcardRowHeader(card, index: index)
            RecallCardView(card: card.makeCard(), revealed: Binding(
                get: { revealedCards.contains(index) },
                set: { if $0 { revealedCards.insert(index) } else { revealedCards.remove(index) } }
            )).id(card.id)
            flashcardAnswer(card, index: index)
        }
        .padding(.bottom, 8)
    }

    private func flashcardRowHeader(_ card: GeneratedFlashcard, index: Int) -> some View {
        HStack {
            Text("Card \(index + 1)").font(.caption2.bold()).foregroundStyle(.tertiary)
            Spacer()
            Text(card.topicName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            if savedCardIDs.contains(card.id) {
                Label("Saved", systemImage: "checkmark.circle.fill").font(.caption2).foregroundStyle(.secondary)
            } else {
                Button("Save") { saveCardToSubject(card) }
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func flashcardAnswer(_ card: GeneratedFlashcard, index: Int) -> some View {
        if revealedCards.contains(index) {
            if let rating = cardRatings[card.id] {
                Label("Rated \(rating.label)", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IBColors.success)
            } else {
                HStack(spacing: 8) {
                    Text("Recall").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    ForEach(RecallQuality.allCases, id: \.self) { quality in
                        QualityButton(label: quality.label, color: recallTint(quality)) { rateGeneratedCard(card, quality: quality) }
                            .frame(maxWidth: 96)
                    }
                }
            }
        } else if !(card.style == .multipleChoice &&
                    CardGeneratorService.validatedChoices(back: card.back, choices: card.choices) != nil) {
            Button("Reveal answer") {
                _ = withAnimation(IBAnimation.snappy) { revealedCards.insert(index) }
                IBHaptics.light()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func recallTint(_ quality: RecallQuality) -> Color {
        switch quality {
        case .again: return IBColors.danger
        case .hard: return IBColors.warning
        case .good, .easy: return IBColors.accent
        }
    }

    @ViewBuilder
    private var saveAllGeneratedCardsButton: some View {
        if unsavedGeneratedCards.count > 1 {
            Button("Save all \(unsavedGeneratedCards.count) cards", action: saveAllCards)
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: - Practice Exam Panel

    private var examPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                examToolbar
                    .disabled(isGradingExam)
                if let examGenerationError {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(examGenerationError)
                            .font(IBTypography.body13)
                            .foregroundStyle(IBColors.danger)
                            .textSelection(.enabled)
                        HStack(spacing: 8) {
                            Button("Try again", action: generateExam)
                                .buttonStyle(SecondaryButtonStyle())
                            Button("Use the offline paper", action: useOfflineExam)
                                .buttonStyle(SecondaryButtonStyle())
                        }
                        .disabled(isGeneratingExam)
                    }
                }
                examContent
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity)
        }
    }

    private var examToolbar: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Practice exam")
                    .font(IBTypography.sectionTitle)
                Text(examMarkdown.isEmpty
                     ? "A paper written for exactly this session's topics."
                     : "\(examMaximumMarks) marks")
                    .font(IBTypography.caption)
                    .foregroundStyle(IBColors.inkSecondary)
            }
            Spacer()
            if !examMarkdown.isEmpty && !isGeneratingExam {
                Button(isSavingTest ? "Saving…" : "Save to Library") { savePracticeTest() }
                    .controlSize(.small)
                    .disabled(isSavingTest)
                Menu("More") {
                    Button("New paper") {
                        clearExamWorkspace()
                        generateExam()
                    }
                    Button("Discard paper", role: .destructive, action: clearExamWorkspace)
                }
                .menuStyle(.button)
                .controlSize(.small)
                .fixedSize()
            }
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private var examContent: some View {
        if isGeneratingExam {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Writing your paper. This can take a few minutes.")
                    .font(IBTypography.body13)
                    .foregroundStyle(IBColors.inkSecondary)
                Spacer()
                Button("Cancel") { examGenerationTask?.cancel() }
                    .controlSize(.small)
            }
        } else if examMarkdown.isEmpty {
            if examGenerationError == nil {
                HStack(spacing: 8) {
                    Button("Generate paper", action: generateExam)
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Use the offline paper", action: useOfflineExam)
                        .buttonStyle(SecondaryButtonStyle())
                        .help("A simple paper built from your selected topics, with no AI needed")
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 24) {
                if let testSaveStatus {
                    Text(testSaveStatus).font(IBTypography.caption).foregroundStyle(IBColors.inkSecondary)
                }
                examPaper
                examResponseEditor
                examGradingResult
                DisclosureGroup("How this is marked") { examRubricOverview }
                    .font(IBTypography.body13)
                    .foregroundStyle(IBColors.inkSecondary)
            }
        }
    }

    private var examPaper: some View {
        FormattedMessageContent(text: examMarkdown)
            .textSelection(.enabled)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCard()
    }

    private var examRubricOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Practice criteria", systemImage: "list.bullet.clipboard")
                    .font(.headline)
                Spacer()
                Text("\(examMaximumMarks) marks")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(examRubricCriteria.enumerated()), id: \.offset) { _, criterion in
                HStack(alignment: .top, spacing: 12) {
                    Text(criterion.name)
                        .font(.callout.weight(.semibold))
                        .frame(width: 210, alignment: .leading)
                    Text(criterion.descriptor)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(criterion.weight)%")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(IBColors.accent)
                        .frame(width: 42, alignment: .trailing)
                }
                .padding(.vertical, 4)
                if criterion.name != examRubricCriteria.last?.name {
                    Divider()
                }
            }
        }
        .padding(.vertical, 12)
    }

    private var examResponseEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your answer")
                    .font(IBTypography.sectionTitle)
                Spacer()
                Text("\(examResponse.split(whereSeparator: \.isWhitespace).count) words")
                    .font(IBTypography.caption.monospacedDigit())
                    .foregroundStyle(IBColors.inkTertiary)
            }
            TextEditor(text: $examResponse)
                .font(.system(size: 13))
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 260)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: IBRadius.card).fill(IBColors.surface))
                .disabled(isGradingExam)
                .accessibilityLabel("Your exam answer")
                .onChange(of: examResponse) { _, _ in
                    examGradingMarkdown = ""
                    testSaveStatus = nil
                }
            DisclosureGroup(examMarkScheme.isEmpty ? "Add a mark scheme" : "Mark scheme") {
                TextEditor(text: $examMarkScheme)
                    .font(.system(size: 12))
                    .frame(minHeight: 120)
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .background(RoundedRectangle(cornerRadius: IBRadius.md).fill(IBColors.surfaceRaised))
                    .accessibilityLabel("Practice exam mark scheme")
                    .disabled(isGradingExam)
                    .padding(.top, 8)
                    .onChange(of: examMarkScheme) { _, _ in
                        examGradingMarkdown = ""
                        testSaveStatus = nil
                    }
            }
            .font(IBTypography.body13)
            .foregroundStyle(IBColors.inkSecondary)
            HStack {
                Text(examMarkScheme.isEmpty ? "Marked as a practice estimate" : "Marked against the scheme")
                    .font(IBTypography.caption)
                    .foregroundStyle(IBColors.inkTertiary)
                Spacer()
                if isGradingExam {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { markingTask?.cancel() }
                        .controlSize(.small)
                }
                Button("Mark my answer", action: gradeExamResponse)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(examResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGradingExam)
            }
        }
    }

    @ViewBuilder
    private var examGradingResult: some View {
        if let examGradingError {
            Text(examGradingError)
                .font(IBTypography.body13)
                .foregroundStyle(IBColors.danger)
                .textSelection(.enabled)
        }
        if !examGradingMarkdown.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Feedback")
                    .font(IBTypography.sectionTitle)
                FormattedMessageContent(text: examGradingMarkdown)
                    .textSelection(.enabled)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCard()
            .transition(.opacity)
        }
    }

    // MARK: - Notes Panel

    private var notesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SESSION NOTES")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)
                Spacer()
                Text("\(sessionNotes.count) chars")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.quaternary)
                if !noteSaveStatus.isEmpty {
                    Text(noteSaveStatus)
                        .font(.caption2)
                        .foregroundStyle(noteSaveStatus == "Saved" ? IBColors.success : IBColors.danger)
                }
                Button {
                    saveSessionNotes()
                } label: {
                    Label("Save notes", systemImage: "square.and.arrow.down")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            TextEditor(text: $sessionNotes)
                .font(.system(size: 13))
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.03))
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .task(id: sessionNotes) {
                    do {
                        try await Task.sleep(for: .milliseconds(700))
                    } catch {
                        return
                    }
                    saveSessionNotes()
                }
        }
    }

    private func saveSessionNotes() {
        guard plan.notes != sessionNotes else { return }
        let previousNotes = plan.notes
        plan.notes = sessionNotes
        do {
            try context.save()
            noteSaveStatus = "Saved"
        } catch {
            plan.notes = previousNotes
            noteSaveStatus = "Could not save: \(error.localizedDescription)"
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Text(bottomBarStatus)
                .font(IBTypography.caption.monospacedDigit())
                .foregroundStyle(IBColors.inkTertiary)
                .lineLimit(1)

            Spacer()

            if let nextTask {
                Button("Next: \(nextTask.title)") { startTask(nextTask) }
                    .lineLimit(1)
                    .controlSize(.small)
                    .help(nextTask.instructions)
            }

            Button(isCompletingSession ? "Saving…" : "Complete session") {
                prepareCompletionCheckIn()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isCompletingSession)
        }
    }

    private var bottomBarStatus: String {
        var parts: [String] = []
        if !generatedCards.isEmpty { parts.append("\(reviewedCardCount) of \(generatedCards.count) cards reviewed") }
        return parts.isEmpty ? "Session in progress" : parts.joined(separator: " · ")
    }

    private var completionCheckIn: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    StudioPageHeader(
                        eyebrow: "Session evidence",
                        title: "Check your recall",
                        symbol: "checkmark.seal",
                        tint: IBColors.inkTertiary
                    ) {
                        EmptyView()
                    }

                    ForEach(evidenceScopes) { scope in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(scope.title)
                                .font(.headline)
                            if !scope.subtopicName.isEmpty {
                                Text(scope.topicName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Picker(
                                "Recall confidence",
                                selection: Binding(
                                    get: { confidenceByScope[scope.id] ?? 0 },
                                    set: { confidenceByScope[scope.id] = $0 }
                                )
                            ) {
                                Text("Choose").tag(0)
                                Text("1 · Not yet").tag(1)
                                Text("2 · Fragile").tag(2)
                                Text("3 · Developing").tag(3)
                                Text("4 · Confident").tag(4)
                                Text("5 · Can teach it").tag(5)
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(14)
                        .surfaceCard()
                    }

                    HStack {
                        Label("\(reviewedCardCount) cards reviewed", systemImage: "rectangle.on.rectangle")
                        Spacer()
                        Label("\(dedicatedMinutes) minutes", systemImage: "clock")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    if let completionError {
                        Label(completionError, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(IBColors.danger)
                    }
                }
                .padding(24)
            }
            .frame(minWidth: 720, minHeight: 480)
            .navigationTitle("Complete Study Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep Studying") { showCompletionCheckIn = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Complete session") { completeSession() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!hasCompleteCheckIn || isCompletingSession)
                }
            }
        }
    }

    private var hasCompleteCheckIn: Bool {
        !evidenceScopes.isEmpty && evidenceScopes.allSatisfy { (confidenceByScope[$0.id] ?? 0) > 0 }
    }

    private func prepareCompletionCheckIn() {
        completionError = nil
        for scope in evidenceScopes where confidenceByScope[scope.id] == nil {
            confidenceByScope[scope.id] = 0
        }
        showCompletionCheckIn = true
    }

    private func quickPrompt(_ text: String) -> some View {
        Button {
            chatInput = text
            sendMessage()
        } label: {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(IBColors.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .hoverHighlight()
        }
        .buttonStyle(IBPressStyle())
    }

    // MARK: - Completion View

    private var completionView: some View {
        VStack(spacing: 20) {
            Spacer()
            completionHero
            completionStats
            completionComparisons
            completionReviewSchedule
            completionRank
            Button("Done", systemImage: "checkmark", action: dismiss.callAsFunction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(minWidth: 120)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .navigationTitle("Session Complete")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .onAppear {
            showRewardPulse = false
            withAnimation(IBAnimation.bounce.delay(0.12)) {
                showRewardPulse = true
            }
        }
    }

    private var completionHero: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(IBColors.success.opacity(0.06)).frame(width: 90, height: 90)
                Circle().fill(IBColors.success.opacity(0.1)).frame(width: 65, height: 65)
                Image(systemName: "checkmark.seal.fill").font(.system(size: 36)).foregroundStyle(IBColors.success)
            }
            .glow(color: IBColors.success, radius: 20)
            Text("Session Complete!").font(.system(size: 22, weight: .bold))
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.title2)
                    .foregroundStyle(IBColors.inkTertiary)
                    .symbolEffect(.bounce, value: showRewardPulse)
                Text("+").font(.title2.bold())
                AnimatedCounter(value: xpAwarded, font: .system(size: 30, weight: .black), color: IBColors.inkTertiary)
                Text("XP").font(.headline).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule().fill(IBColors.inkTertiary.opacity(0.10)))
            .scaleEffect(showRewardPulse ? 1 : 0.72)
            .opacity(showRewardPulse ? 1 : 0)
            .animation(IBAnimation.bounce, value: showRewardPulse)
        }
    }

    private var completionStats: some View {
        HStack(spacing: 0) {
            StatCard(value: "\(dedicatedMinutes)m", label: "Dedicated", color: IBColors.warning, icon: "clock.fill")
            Divider().frame(height: 44)
            StatCard(value: plan.subjectName, label: "Subject", color: subjectColor(plan.subjectName), icon: "book.fill")
            Divider().frame(height: 44)
            StatCard(value: "\(reviewedCardCount)", label: "Reviewed", color: IBColors.accent, icon: "rectangle.on.rectangle")
            Divider().frame(height: 44)
            StatCard(value: "+\(xpAwarded)xp", label: "Earned", color: IBColors.plum, icon: "star.fill")
        }
        .padding(.vertical, 12)
        .glassCard(cornerRadius: IBRadius.md)
        .frame(maxWidth: 550)
    }

    @ViewBuilder
    private var completionComparisons: some View {
        HStack(spacing: 12) {
            if let recentAverageMinutes {
                comparisonMetric(
                    value: dedicatedMinutes - recentAverageMinutes,
                    positiveLabel: "min above recent average",
                    negativeLabel: "min below recent average",
                    symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                )
            }
            if let recentAverageRetention, reviewedCardCount > 0 {
                comparisonMetric(
                    value: (correctReviewedCardCount * 100 / max(reviewedCardCount, 1)) - recentAverageRetention,
                    positiveLabel: "points above recent recall",
                    negativeLabel: "points below recent recall",
                    symbol: "chart.line.uptrend.xyaxis"
                )
            }
            if completedStreak > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    Label("\(completedStreak)-day streak", systemImage: "flame.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(IBColors.inkTertiary)
                    Text(completedStreak > previousStreak ? "+1 from this session" : "Maintained today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(IBColors.inkTertiary.opacity(0.08)))
            }
        }
        .frame(maxWidth: 550, alignment: .leading)
    }

    @ViewBuilder
    private var completionReviewSchedule: some View {
        Label(
            "Saved cards now come back through your review queue when they are due.",
            systemImage: "rectangle.stack.badge.play"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(IBColors.accent)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(IBColors.accent.opacity(0.04)))
    }

    @ViewBuilder
    private var completionRank: some View {
        if let profile = profiles.first {
            Label(profile.achievedStep.displayName, systemImage: profile.achievedStep.rank.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(IBColors.accent)
                .padding(10)
                .glassCard(cornerRadius: IBRadius.md)
        }
    }

    private func comparisonMetric(
        value: Int,
        positiveLabel: String,
        negativeLabel: String,
        symbol: String
    ) -> some View {
        let isPositive = value >= 0
        return VStack(alignment: .leading, spacing: 2) {
            Label("\(value >= 0 ? "+" : "")\(value)", systemImage: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(isPositive ? IBColors.success : IBColors.inkTertiary)
            Text(isPositive ? positiveLabel : negativeLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill((isPositive ? IBColors.success : IBColors.inkTertiary).opacity(0.08))
        )
    }

    // MARK: - Timer

    private func startTimer() {
        guard !didStartSession else { return }
        didStartSession = true
        sessionStartDate = Date()
    }

    // MARK: - Chat (Full ARIA Context)

    private func sendMessage() {
        guard !chatInput.isEmpty, !isChatting else { return }
        let userMsg = chatInput
        chatMessages.append((role: "user", text: userMsg))
        chatInput = ""
        isChatting = true

        Task {
            do {
                // Build full ARIA system prompt with context
                let aria = ARIAService()
                let systemPrompt = await aria.buildSystemPrompt(context: context, seedQuery: userMsg)

                // Build conversation history
                var messages: [GeminiMessage] = []

                // Add study plan context as first message
                messages.append(GeminiMessage(role: "user", text: """
                I'm in an active study session for \(plan.subjectName) focused on \(plan.selectionSummary).
                Duration: \(plan.durationMinutes) minutes. Time elapsed: \(Int(elapsed / 60)) minutes.
                
                My study plan:
                \(plan.planMarkdown.prefix(1500))
                \(sessionNotes.isEmpty ? "" : "\nMy notes so far: \(sessionNotes.prefix(500))")
                """))
                messages.append(GeminiMessage(role: "model", text: "Got it! I have full context on your study session. I'm here to help with \(plan.studyScope.title). What would you like to know?"))

                // Add chat history
                for msg in chatMessages {
                    messages.append(GeminiMessage(role: msg.role, text: msg.text))
                }

                let response = try await AIProviderService.generateContent(
                    messages: messages,
                    systemInstruction: systemPrompt
                )

                ARIAService.recordARIAChatExchange(
                    subjectName: plan.subjectName,
                    topicNames: plan.studyScope.topicNames,
                    userMessage: userMsg,
                    assistantReply: response,
                    sourceReference: "ActiveStudySessionView.sendMessage"
                )

                await MainActor.run {
                    chatMessages.append((role: "model", text: response))
                    isChatting = false
                }
            } catch {
                await MainActor.run {
                    chatMessages.append((role: "model", text: "Error: \(error.localizedDescription)"))
                    isChatting = false
                }
            }
        }
    }

    // MARK: - Flashcard Generation

    private func generateFlashcards() {
        guard !isGeneratingCards, let subject = subjects.first(where: { $0.name == plan.subjectName }) else { return }
        let jobs: [CardBatchJob]
        do {
            jobs = try CardBatchService.plan(scopes: Array(flashcardSelection),
                                             styles: [cardStudioOptions.style], count: cardStudioOptions.count)
        } catch { flashcardError = error.localizedDescription; return }
        isGeneratingCards = true
        flashcardError = nil
        let options = cardStudioOptions
        flashcardTask = Task { @MainActor in
            defer { isGeneratingCards = false; flashcardTask = nil }
            do {
                let batch = try await CardBatchService.generate(subject: subject, jobs: jobs, options: options,
                                                                context: context, reuseExisting: generatedCards.isEmpty) { _, _, _ in }
                try Task.checkCancellation()
                let present = Set(generatedCards.map(\.id))
                let reused = batch.reusedCards.filter { !present.contains($0.id) }
                generatedCards.append(contentsOf: reused.map(CardDraft.init))
                for card in reused {
                    savedCardIDs.insert(card.id)
                    persistedCardIDs[card.id] = card.id
                }
                generatedCards.append(contentsOf: batch.drafts.filter { !present.contains($0.id) })
                flashcardError = batch.issues.isEmpty ? nil : batch.issues.joined(separator: "\n")
                // Session cards are saved with their complete format metadata
                // before rating, and each draft is persisted only once.
                for card in batch.drafts { _ = saveCardToSubject(card) }
            } catch is CancellationError {
                // Cancellation leaves the existing set intact.
            } catch { flashcardError = error.localizedDescription }
        }
    }

    // MARK: - Exam Generation

    private func clearExamWorkspace() {
        guard !isGeneratingExam, !isGradingExam, !isSavingTest else { return }
        withAnimation(IBAnimation.smooth) {
            savedTestID = UUID()
            testSaveStatus = nil
            examMarkdown = ""
            examMarkScheme = ""
            examResponse = ""
            examGradingMarkdown = ""
            examGradingError = nil
            examGenerationError = nil
            examMaximumMarks = 20
        }
    }

    @discardableResult
    private func savePracticeTest() -> Bool {
        guard !isSavingTest, !examMarkdown.isEmpty else { return false }
        isSavingTest = true
        defer { isSavingTest = false }
        let test = SavedStudyTest(id: savedTestID, subject: plan.subjectName,
            level: subjects.first(where: { $0.name == plan.subjectName })?.level ?? "",
            topics: plan.selectedTopicNames, subtopics: plan.selectedSubtopicNames,
            question: examMarkdown, answer: examResponse, markScheme: examMarkScheme,
            feedback: examGradingMarkdown, maximumMarks: examMaximumMarks)
        do {
            _ = try StudyTestStore.save(test, context: context)
            testSaveStatus = "Saved to Library"
            return true
        } catch {
            testSaveStatus = "Couldn't save test: \(error.localizedDescription)"
            return false
        }
    }

    private func generateExam() {
        guard !isGeneratingExam, !isGradingExam else { return }
        isGeneratingExam = true
        examGenerationError = nil
        let level = subjects.first(where: { $0.name == plan.subjectName })?.level ?? ""

        examGenerationTask = Task { @MainActor in
            defer { isGeneratingExam = false; examGenerationTask = nil }
            do {
                let prompt = """
                Generate a rigorous Practice Exam paper for:
                Subject: \(plan.subjectName)
                Level: \(level)
                Units: \(plan.selectedUnitNames.joined(separator: ", "))
                Topics: \(plan.selectedTopicNames.joined(separator: ", "))
                \(plan.selectedSubtopicNames.isEmpty ? "" : "Focus subtopics: \(plan.selectedSubtopicNames.joined(separator: ", "))")
                
                Format rules:
                - Write original IB-style practice questions. Do not claim this is an official past paper.
                - Use clear sections (e.g., Section A: Short Answer, Section B: Extended Response / Essay).
                - Use rigorous IB command terms (Evaluate, Discuss, To what extent, Compare and contrast).
                - IMPORTANT: Include the exact marks available at the end of every question in brackets, e.g. [4 marks].
                - The paper must total exactly 24 marks. Do not repeat marks in headings or totals.
                - Include the complete data, passage or case needed to answer each question. Do not ask the student to invent the problem.
                - Keep answers and hints OUT of the question field. Put a complete question-by-question mark scheme in markScheme.
                - Ensure layout uses Markdown headings, numbered questions, bullets, and blockquotes effectively.
                - Avoid Markdown tables.
                - In the JSON, escape every LaTeX backslash as a double backslash, for example \\\\frac.
                Return ONLY JSON with these keys:
                {"question":"Markdown paper with [N marks] after each question","markScheme":"Markdown scheme","maximumMarks":24}
                """

                let response = try await AIProviderService.generateContent(
                    messages: [GeminiMessage(role: "user", text: prompt)],
                    systemInstruction: "You write original practice exams tailored to the supplied IB subject, level and curriculum scope. Return the requested JSON object with separate question and markScheme fields. Use valid LaTeX for equations.",
                    timeout: PracticeExamPaper.generationTimeout
                )
                try Task.checkCancellation()
                let paper = try PracticeExamPaper.parse(response)
                examMarkdown = IBExamRubric.displaySafeMarkdown(paper.question)
                examMarkScheme = IBExamRubric.displaySafeMarkdown(paper.markScheme)
                examMaximumMarks = paper.maximumMarks
            } catch is CancellationError {
                examGenerationError = "Exam generation cancelled. You can try again."
            } catch { examGenerationError = "Could not generate the paper: \(error.localizedDescription)" }
        }
    }

    private func useOfflineExam() {
        guard !isGeneratingExam, !isGradingExam else { return }
        let template = PracticeExamFallback.markdown(
            subject: plan.subjectName,
            level: subjects.first(where: { $0.name == plan.subjectName })?.level ?? "",
            unit: plan.selectedUnitNames.first ?? "Selected unit",
            topics: plan.selectedTopicNames,
            subtopics: plan.selectedSubtopicNames
        )
        let sections = template.components(separatedBy: "### Mark scheme and self-check")
        examMarkdown = sections[0]
        examMarkScheme = sections.count > 1 ? sections[1] : ""
        examMaximumMarks = IBExamRubric.totalMarks(in: examMarkdown)
        examGenerationError = nil
    }

    private func gradeExamResponse() {
        guard !isGradingExam else { return }
        let request = ExamMarkingRequest(subject: plan.subjectName,
            level: subjects.first(where: { $0.name == plan.subjectName })?.level ?? "",
            question: examMarkdown, answer: examResponse, markScheme: examMarkScheme,
            maximumMarks: examMaximumMarks)
        guard request.isValid else { examGradingError = ExamMarkingError.invalidRequest.localizedDescription; return }
        isGradingExam = true
        examGradingError = nil
        examGradingMarkdown = ""
        markingTask = Task { @MainActor in
            defer { isGradingExam = false; markingTask = nil }
            do {
                let result = try await ExamMarkingService.mark(request)
                try Task.checkCancellation()
                examGradingMarkdown = result.transcript(hasScheme: request.hasScheme)
                savePracticeTest()
            } catch is CancellationError {
                // Keep the response available for another attempt.
            } catch { examGradingError = error.localizedDescription }
        }
    }

    @discardableResult
    private func saveCardToSubject(_ generatedCard: GeneratedFlashcard) -> StudyCard? {
        guard let subject = subjects.first(where: { $0.name == plan.subjectName }) else { return nil }
        if let persistedID = persistedCardIDs[generatedCard.id],
           let existing = subject.cards.first(where: { $0.id == persistedID }) {
            return existing
        }
        if let existing = CardDuplicatePolicy.existingMatch(for: generatedCard, in: subject.cards) {
            savedCardIDs.insert(generatedCard.id)
            persistedCardIDs[generatedCard.id] = existing.id
            return existing
        }
        let card = generatedCard.makeCard(subject: subject)
        card.sourceStudyPlanID = plan.id
        card.sourceStudySessionID = activeSessionID
        context.insert(card)
        do {
            try context.save()
        } catch {
            // Do not leave a card that was never persisted: drop the pending
            // insert so the UI cannot claim a save that did not happen. The
            // failure is surfaced so the user knows the card was not saved.
            context.delete(card)
            flashcardError = "Could not save this flashcard: \(error.localizedDescription)"
            return nil
        }
        savedCardIDs.insert(generatedCard.id)
        persistedCardIDs[generatedCard.id] = card.id
        IBHaptics.success()
        return card
    }

    private func saveAllCards() {
        guard let subject = subjects.first(where: { $0.name == plan.subjectName }) else { return }
        let toSave = unsavedGeneratedCards
        guard !toSave.isEmpty else { return }
        var inserted: [StudyCard] = []
        for card in toSave {
            if let existing = CardDuplicatePolicy.existingMatch(for: card, in: subject.cards) {
                persistedCardIDs[card.id] = existing.id
                continue
            }
            let studyCard = card.makeCard(subject: subject)
            studyCard.sourceStudyPlanID = plan.id
            studyCard.sourceStudySessionID = activeSessionID
            context.insert(studyCard)
            inserted.append(studyCard)
            persistedCardIDs[card.id] = studyCard.id
        }
        do {
            try context.save()
        } catch {
            // Same reasoning as `saveCardToSubject`: a failed save must not be
            // presented as a completed batch.
            inserted.forEach(context.delete)
            for card in toSave { persistedCardIDs.removeValue(forKey: card.id) }
            flashcardError = "Could not save your flashcards: \(error.localizedDescription)"
            return
        }
        for card in toSave {
            savedCardIDs.insert(card.id)
        }
        IBHaptics.success()
    }

    private func rateGeneratedCard(_ generatedCard: GeneratedFlashcard, quality: RecallQuality) {
        guard cardRatings[generatedCard.id] == nil,
              let card = saveCardToSubject(generatedCard) else { return }
        do {
            let day = try ReviewDailyLimitPolicy.day(in: context)
            guard day.canReview(card) else {
                flashcardError = day.remaining == 0
                    ? "Today's \(day.maximum)-card allowance is complete. More reviews are available tomorrow."
                    : "This card or a matching copy has already been reviewed today."
                return
            }
            try FSRSScheduler.applyReview(to: card, quality: quality)
            let review = ReviewSession(
                cardID: card.id,
                subjectName: plan.subjectName,
                topicName: generatedCard.topicName,
                qualityRating: quality.rawValue,
                studySessionID: activeSessionID
            )
            FSRSScheduler.configure(review, quality: quality)
            context.insert(review)
            // A rated card counts today however the session ends, including
            // leaving without logging or revisiting a completed plan.
            var ratingXP = recordedRatingXP
            if let profile = profiles.first {
                if cardRatings.isEmpty { previousStreak = profile.currentStreak }
                profile.checkAndUpdateStreak()
                NotificationService.refreshStreakWarning(for: profile)
                completedStreak = profile.currentStreak
                // Priced from the running total so rounding matches xpAwarded.
                ratingXP = XPCalculator.xp(forQualities: Array(cardRatings.values) + [quality], intensity: profile.studyIntensity)
                profile.recordXP(ratingXP - recordedRatingXP)
            }
            try context.save()
            recordedRatingXP = ratingXP
            cardRatings[generatedCard.id] = quality
            IBHaptics.medium()
        } catch {
            context.rollback()
            flashcardError = "Could not record this review: \(error.localizedDescription)"
        }
    }

    // MARK: - Complete

    private var xpAwarded: Int {
        let intensity = profiles.first?.studyIntensity ?? .average
        let bonus = earnedCompletionBonus
            ? XPCalculator.completionBonus(forStudyMinutes: dedicatedMinutesDouble, intensity: intensity) : 0
        return XPCalculator.xp(
            forStudyMinutes: dedicatedMinutesDouble,
            intensity: intensity
        ) + XPCalculator.xp(forQualities: Array(cardRatings.values), intensity: intensity) + bonus
    }

    private func completeSession() {
        finishSession(markPlanComplete: true)
    }

    private func finishSession(markPlanComplete: Bool) {
        guard !isCompletingSession else { return }
        guard !markPlanComplete || hasCompleteCheckIn else {
            completionError = "Rate every selected topic or subunit before completing."
            return
        }
        guard !plan.isCompleted else {
            dismiss()
            return
        }
        isCompletingSession = true
        if !examMarkdown.isEmpty, !savePracticeTest() {
            isCompletingSession = false
            let message = testSaveStatus ?? "Could not save your practice answer. Try again."
            sessionControlStatus = message
            completionError = message
            return
        }
        // Freeze the elapsed time first: every XP / duration / startDate read
        // below (and on the completion screen) must use this single snapshot,
        // not a still-running clock.
        completedElapsed = max(0, IBLocalClock.now.timeIntervalSince(sessionStartDate))
        earnedCompletionBonus = markPlanComplete
        plan.isCompleted = markPlanComplete
        plan.notes = sessionNotes

        // Log StudySession
        let topics = plan.selectedTopicNames.isEmpty ? [plan.topicName] : plan.selectedTopicNames
        let minutesPerScope = evidenceScopes.isEmpty ? 0 : dedicatedMinutesDouble / Double(evidenceScopes.count)
        let evidence = (markPlanComplete ? evidenceScopes : []).map { scope in
            let scopedGeneratedIDs = generatedCards.filter {
                $0.topicName.caseInsensitiveCompare(scope.topicName) == .orderedSame &&
                    (scope.subtopicName.isEmpty || $0.subtopic.caseInsensitiveCompare(scope.subtopicName) == .orderedSame)
            }.map(\.id)
            let scopedRatings = scopedGeneratedIDs.compactMap { cardRatings[$0] }
            return StudySessionSubunitEvidence(
                topicName: scope.topicName,
                subtopicName: scope.subtopicName,
                minutes: minutesPerScope,
                confidenceRating: confidenceByScope[scope.id] ?? 1,
                cardsReviewed: scopedRatings.count,
                correctCount: scopedRatings.filter { $0 == .good || $0 == .easy }.count
            )
        }
        let reviewedStudyCardIDs = cardRatings.keys.compactMap { persistedCardIDs[$0] }
        let session = StudySession(
            id: activeSessionID,
            subjectName: plan.subjectName,
            topicsCovered: topics.joined(separator: ", "),
            subtopicsCovered: plan.selectedSubtopicNames.joined(separator: ", "),
            startDate: sessionStartDate,
            endDate: IBLocalClock.now,
            cardsReviewed: reviewedCardCount,
            correctCount: correctReviewedCardCount,
            xpEarned: xpAwarded,
            sourcePlanID: plan.id,
            notes: sessionNotes,
            subunitEvidence: evidence,
            reviewedCardIDs: reviewedStudyCardIDs
        )
        context.insert(session)

        // Award XP
        if let profile = profiles.first {
            // Ratings already moved the streak and kept the starting value.
            if cardRatings.isEmpty { previousStreak = profile.currentStreak }
            profile.recordXP(xpAwarded - recordedRatingXP)
            profile.checkAndUpdateStreak()
            NotificationService.refreshStreakWarning(for: profile)
            completedStreak = profile.currentStreak
        }

        let today = IBLocalClock.calendar.startOfDay(for: IBLocalClock.now)
        let predicate = #Predicate<StudyActivity> { $0.date == today }
        if let activity = try? context.fetch(FetchDescriptor(predicate: predicate)).first {
            activity.minutesStudied += dedicatedMinutesDouble
            activity.xpEarned += xpAwarded
            activity.cardsReviewed += reviewedCardCount
        } else {
            context.insert(StudyActivity(date: today, cardsReviewed: reviewedCardCount, minutesStudied: dedicatedMinutesDouble, xpEarned: xpAwarded))
        }

        do {
            try context.save()
            if markPlanComplete {
                ARIAService.recordPlannedStudySession(
                    subjectName: plan.subjectName,
                    topics: topics,
                    planMarkdown: plan.planMarkdown,
                    notes: sessionNotes,
                    xpEarned: xpAwarded,
                    durationMinutes: dedicatedMinutesDouble
                )
            }

            // Must run after the StudySession and StudyActivity records are in the
            // context, or this session's work is invisible to the engine.
            progressionEvents.enqueue(ProgressionService.recompute(context: context))

            IBHaptics.success()
            onComplete?()
            isCompletingSession = false
            showCompletionCheckIn = false
            if !markPlanComplete {
                dismiss()
                return
            }
            withAnimation(IBAnimation.smooth) {
                isSessionComplete = true
                showRewardPulse = true
            }
        } catch {
            // Discard this session's pending inserts (StudySession, StudyActivity,
            // XP) and the completion flag together so a retry cannot double-log.
            // This is safe on the shared context only because the sheet is modal
            // (no other UI is writing) and async work uses its own scratch
            // contexts, so there is no unrelated pending change to lose.
            context.rollback()
            completedElapsed = 0
            earnedCompletionBonus = false
            isCompletingSession = false
            let message = "Could not save the session: \(error.localizedDescription). Your work is still here so you can retry."
            completionError = message
            sessionControlStatus = message
        }
    }

    // MARK: - Helpers

    private func subjectColor(_ name: String) -> Color {
        switch name {
        case "English B": return IBColors.englishColor
        case "Russian A Literature": return IBColors.russianColor
        case "Biology": return IBColors.biologyColor
        case "Mathematics AA": return IBColors.mathColor
        case "Economics": return IBColors.economicsColor
        case "Business Management": return IBColors.businessColor
        case "Advanced Mathematics": return Color(hex: "8B5CF6")
        case "Fundamentals of the Universe": return Color(hex: "6366F1")
        case "Life", "Founder Academy", "Startups & Venture Capital": return Color(hex: "0EA5E9")
        default: return .gray
        }
    }

    private func subjectIcon(_ name: String) -> String {
        switch name {
        case "English B": return "text.book.closed.fill"
        case "Russian A Literature": return "book.fill"
        case "Biology": return "leaf.fill"
        case "Mathematics AA": return "function"
        case "Economics": return "chart.line.uptrend.xyaxis"
        case "Business Management": return "briefcase.fill"
        case "Advanced Mathematics": return "function"
        case "Fundamentals of the Universe": return "moon.stars.fill"
        case "Life", "Founder Academy", "Startups & Venture Capital": return "rocket.fill"
        default: return "book.fill"
        }
    }
}

nonisolated enum StudySessionDuration {
    struct Extension: Equatable, Sendable {
        let minutes: Int
        let endDate: Date
    }

    enum AdjustmentError: LocalizedError {
        case invalidDuration
        var errorDescription: String? { "Choose a positive extension with a total session length of at most 24 hours." }
    }

    static func extending(_ plan: StudyPlan, by additionalMinutes: Int) throws -> Extension {
        let (minutes, overflow) = plan.durationMinutes.addingReportingOverflow(additionalMinutes)
        guard !plan.isCompleted, additionalMinutes > 0, !overflow, (1...1440).contains(minutes) else {
            throw AdjustmentError.invalidDuration
        }
        return Extension(minutes: minutes, endDate: plan.scheduledEndDate.addingTimeInterval(Double(additionalMinutes) * 60))
    }
}

nonisolated struct PracticeExamPaper: Codable, Equatable, Sendable {
    let question: String
    let markScheme: String
    let maximumMarks: Int

    /// A whole paper is long work: Codex was measured taking over 200 seconds at
    /// default effort, so the 120 second default made generation fail outright.
    static let generationTimeout: TimeInterval = 420

    enum GenerationError: LocalizedError {
        case invalidPaper
        var errorDescription: String? { "The provider returned no usable questions. Try generating it again." }
    }

    /// Accepts what providers really return. A paper with one miscounted mark is
    /// still a paper the student can sit, so only a paper with no questions is
    /// rejected. The total printed on the questions wins over the declared one,
    /// because that is what the student reads and what gets marked.
    static func parse(_ response: String) throws -> PracticeExamPaper {
        let object = ProviderJSON.object(in: response) ?? [:]
        var question = ProviderJSON.firstString(in: object, keys: ["question", "paper", "questions", "exam"]) ?? ""
        var markScheme = ProviderJSON.firstString(in: object, keys: ["markScheme", "mark_scheme", "markscheme", "scheme"]) ?? ""
        if question.isEmpty, object.isEmpty {
            // No JSON at all: the provider wrote the paper as plain Markdown.
            let parts = splitPlainPaper(response)
            question = parts.question
            markScheme = parts.scheme
        }
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty, question.count <= 20_000, markScheme.count <= 30_000 else {
            throw GenerationError.invalidPaper
        }
        let printed = IBExamRubric.questionMarks(in: question)
        let declared = ProviderJSON.int(object["maximumMarks"]) ?? ProviderJSON.int(object["totalMarks"])
        guard let marks = resolvedMarks(printed: printed, declared: declared) else {
            throw GenerationError.invalidPaper
        }
        return PracticeExamPaper(question: question, markScheme: markScheme, maximumMarks: marks)
    }

    private static func resolvedMarks(printed: Int?, declared: Int?) -> Int? {
        let valid = 1...100
        if let printed, let declared, valid.contains(declared), printed == declared * 2 {
            // The paper total was printed in the same style as a question.
            return declared
        }
        if let printed, valid.contains(printed) { return printed }
        if let declared, valid.contains(declared) { return declared }
        return nil
    }

    private static func splitPlainPaper(_ response: String) -> (question: String, scheme: String) {
        let text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = text.range(of: #"(?im)^\s*(#+\s*|\*\*)?mark\s*scheme"#, options: .regularExpression) else {
            return (text, "")
        }
        return (String(text[..<range.lowerBound]), String(text[range.lowerBound...]))
    }
}

nonisolated enum FlashcardBatchAllocator: Sendable {
    static func counts(total: Int, topicCount: Int) -> [Int] {
        guard topicCount > 0 else { return [] }
        let safeTotal = max(total, topicCount)
        let base = safeTotal / topicCount
        let remainder = safeTotal % topicCount
        return (0..<topicCount).map { base + ($0 < remainder ? 1 : 0) }
    }
}

nonisolated enum IBExamRubric: Sendable {
    struct Criterion: Sendable {
        let name: String
        let weight: Int
        let descriptor: String
    }

    static func shortName(for subject: String) -> String {
        switch normalized(subject) {
        case let name where name.contains("literature"): return "Literature criteria A-D"
        case let name where name.contains("english b"): return "Language B criteria"
        case let name where name.contains("mathematics"): return "Mathematics method rubric"
        case let name where name.contains("economics"): return "Economics response rubric"
        case let name where name.contains("business"): return "Business response rubric"
        case let name where name.contains("biology"): return "Biology response rubric"
        case let name where name.contains("theory of knowledge"): return "TOK essay criteria"
        default: return "IB knowledge and evaluation rubric"
        }
    }

    static func criteria(for subject: String) -> [Criterion] {
        switch normalized(subject) {
        case let name where name.contains("literature"):
            return [
                Criterion(name: "A: Knowledge, understanding and interpretation", weight: 25, descriptor: "Accurate knowledge of the work and a convincing interpretation supported by references."),
                Criterion(name: "B: Analysis and evaluation", weight: 25, descriptor: "Analysis of authorial choices and evaluation of how those choices construct meaning."),
                Criterion(name: "C: Focus and organization", weight: 25, descriptor: "A sustained response to the question with coherent, balanced paragraph development."),
                Criterion(name: "D: Language", weight: 25, descriptor: "Clear, varied, accurate and appropriately formal language.")
            ]
        case let name where name.contains("english b"):
            return [
                Criterion(name: "A: Language", weight: 33, descriptor: "Range and accuracy of vocabulary, grammar, register and sentence structure."),
                Criterion(name: "B: Message", weight: 34, descriptor: "Relevant ideas are developed clearly and address every part of the task."),
                Criterion(name: "C: Conceptual understanding", weight: 33, descriptor: "Text type, audience, purpose, tone and conventions are handled effectively.")
            ]
        case let name where name.contains("mathematics"):
            return [
                Criterion(name: "Method and reasoning", weight: 40, descriptor: "Valid mathematical method, visible working and logically connected steps."),
                Criterion(name: "Accuracy", weight: 30, descriptor: "Correct manipulation, values, notation, units and appropriate precision."),
                Criterion(name: "Communication", weight: 15, descriptor: "Definitions, diagrams, notation and reasoning are presented unambiguously."),
                Criterion(name: "Interpretation", weight: 15, descriptor: "The result is interpreted in context and checked for reasonableness.")
            ]
        case let name where name.contains("economics"):
            return [
                Criterion(name: "Knowledge and understanding", weight: 20, descriptor: "Accurate definitions, theory and economic terminology."),
                Criterion(name: "Application", weight: 25, descriptor: "Theory, examples and diagrams are applied directly to the question or case."),
                Criterion(name: "Analysis", weight: 30, descriptor: "A complete causal chain explains how and why outcomes occur."),
                Criterion(name: "Evaluation", weight: 25, descriptor: "Balanced judgement considers assumptions, stakeholders, time frames and limitations.")
            ]
        case let name where name.contains("business"):
            return [
                Criterion(name: "Knowledge and understanding", weight: 20, descriptor: "Accurate business tools, theories and terminology."),
                Criterion(name: "Application", weight: 25, descriptor: "Arguments use the organization, figures and context supplied by the case."),
                Criterion(name: "Analysis", weight: 30, descriptor: "Effects are explained through connected business reasoning rather than assertion."),
                Criterion(name: "Evaluation", weight: 25, descriptor: "A justified recommendation weighs alternatives, stakeholders and constraints.")
            ]
        case let name where name.contains("biology"):
            return [
                Criterion(name: "Knowledge and understanding", weight: 30, descriptor: "Correct biological terminology, processes and factual detail."),
                Criterion(name: "Application", weight: 25, descriptor: "Knowledge is applied to unfamiliar contexts, data, calculations or diagrams."),
                Criterion(name: "Analysis", weight: 25, descriptor: "Evidence and relationships are interpreted through a complete scientific explanation."),
                Criterion(name: "Communication", weight: 20, descriptor: "Labels, units, working and conclusions are precise and scientifically clear.")
            ]
        case let name where name.contains("theory of knowledge"):
            return [
                Criterion(name: "Focus on the title", weight: 25, descriptor: "The response remains tightly focused on the knowledge question and key terms."),
                Criterion(name: "Perspectives and examples", weight: 25, descriptor: "Contrasting perspectives use specific, relevant real-world examples."),
                Criterion(name: "Analysis and evaluation", weight: 30, descriptor: "Claims and counterclaims are examined with implications and limitations."),
                Criterion(name: "Organization and sources", weight: 20, descriptor: "The argument is coherent and sources or examples are acknowledged appropriately.")
            ]
        default:
            return [
                Criterion(name: "Knowledge and understanding", weight: 25, descriptor: "Accurate subject knowledge and terminology."),
                Criterion(name: "Application", weight: 25, descriptor: "Knowledge is applied directly to the task and selected scope."),
                Criterion(name: "Analysis", weight: 25, descriptor: "Reasoning is explicit, connected and supported."),
                Criterion(name: "Evaluation and communication", weight: 25, descriptor: "The response reaches a justified conclusion and communicates it clearly.")
            ]
        }
    }

    static func markdown(for subject: String, level: String) -> String {
        let rows = criteria(for: subject).map {
            "- **\($0.name) (\($0.weight)%)**: \($0.descriptor)"
        }
        return (["\(subject) \(level) criteria:"] + rows).joined(separator: "\n")
    }

    static func totalMarks(in paper: String) -> Int {
        questionMarks(in: paper) ?? 20
    }

    static func questionMarks(in paper: String) -> Int? {
        // Counts "[4 marks]", "(4 marks)" and "[4]", ignoring LaTeX so that an
        // array index or matrix like $[2]$ is never read as a mark.
        let prose = paper.replacingOccurrences(of: #"\$\$[\s\S]*?\$\$|\$[^$\n]*\$|\\\[[\s\S]*?\\\]|\\\([\s\S]*?\\\)"#, with: " ", options: .regularExpression)
        let pattern = #"\[(\d+)\s*(?:marks?)?\]|\((\d+)\s*marks?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(prose.startIndex..<prose.endIndex, in: prose)
        let matches = regex.matches(in: prose, range: range)
        guard !matches.isEmpty else { return nil }
        var total = 0
        for match in matches {
            let group = match.range(at: 1).location == NSNotFound ? 2 : 1
            guard let markRange = Range(match.range(at: group), in: prose),
                  let marks = Int(prose[markRange]), (1...100).contains(marks),
                  total <= 100 - marks else { return nil }
            total += marks
        }
        return total
    }

    static func displaySafeMarkdown(_ source: String) -> String {
        var output: [String] = []
        var tableHeaders: [String] = []
        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else {
                tableHeaders = []
                output.append(line)
                continue
            }
            let cells = trimmed
                .dropFirst()
                .dropLast()
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let isSeparator = cells.allSatisfy { cell in
                !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" || $0.isWhitespace }
            }
            if isSeparator { continue }
            if tableHeaders.isEmpty {
                tableHeaders = cells
                output.append("**\(cells.joined(separator: " · "))**")
                continue
            }
            let details = cells.enumerated().dropFirst().map { index, value in
                let label = index < tableHeaders.count ? tableHeaders[index] : "Detail"
                return "**\(label):** \(value)"
            }
            let title = cells.first ?? "Criterion"
            output.append("- **\(title)**")
            output.append(contentsOf: details.map { "  - \($0)" })
        }
        return output.joined(separator: "\n")
    }

    static func localFeedback(
        subject: String,
        level: String,
        answer: String,
        totalMarks: Int,
        scopeTerms: [String]
    ) -> String {
        let normalizedAnswer = normalized(answer)
        let wordCount = answer.split(whereSeparator: \.isWhitespace).count
        let scopeKeywords = Set(scopeTerms.flatMap(tokens).filter { $0.count >= 4 })
        let matchedScope = scopeKeywords.filter { normalizedAnswer.contains($0) }.count
        let scopeCoverage = scopeKeywords.isEmpty ? 0.5 : min(Double(matchedScope) / Double(scopeKeywords.count), 1)
        let reasoning = markerCoverage(in: normalizedAnswer, markers: ["because", "therefore", "thus", "leads to", "results in", "which means", "as a result"])
        let evaluation = markerCoverage(in: normalizedAnswer, markers: ["however", "although", "limitation", "depends", "whereas", "on the other hand", "overall", "conclusion"])
        let evidence = markerCoverage(in: normalizedAnswer, markers: ["for example", "evidence", "data", "figure", "case", "diagram", "equation", "calculation"])
        let development = min(Double(wordCount) / 320.0, 1)
        let paragraphCount = answer.split(separator: "\n", omittingEmptySubsequences: true).count
        let organization = min(Double(paragraphCount) / 4.0, 1)

        let scored = criteria(for: subject).map { criterion -> (Criterion, Int, String) in
            let key = normalized(criterion.name)
            let fraction: Double
            let evidenceText: String
            if key.contains("evaluation") || key.contains("perspective") {
                fraction = development * 0.25 + evaluation * 0.5 + evidence * 0.25
                evidenceText = "Evaluation markers: \(Int((evaluation * 100).rounded()))%; evidence markers: \(Int((evidence * 100).rounded()))%."
            } else if key.contains("analysis") || key.contains("method") || key.contains("reasoning") {
                fraction = development * 0.2 + reasoning * 0.55 + scopeCoverage * 0.25
                evidenceText = "Reasoning markers: \(Int((reasoning * 100).rounded()))%; scope coverage: \(Int((scopeCoverage * 100).rounded()))%."
            } else if key.contains("application") || key.contains("interpretation") || key.contains("message") {
                fraction = development * 0.2 + scopeCoverage * 0.4 + evidence * 0.4
                evidenceText = "Scope coverage: \(Int((scopeCoverage * 100).rounded()))%; applied evidence markers: \(Int((evidence * 100).rounded()))%."
            } else if key.contains("organization") || key.contains("communication") || key.contains("language") {
                fraction = development * 0.35 + organization * 0.4 + reasoning * 0.25
                evidenceText = "\(paragraphCount) developed paragraph(s); \(wordCount) words."
            } else {
                fraction = development * 0.45 + scopeCoverage * 0.4 + reasoning * 0.15
                evidenceText = "Matched \(matchedScope)/\(scopeKeywords.count) scope term(s); \(wordCount) words."
            }
            let indicator = min(max(Int((fraction * 5).rounded()), 0), 5)
            return (criterion, indicator, evidenceText)
        }

        let weightedFraction = scored.reduce(0.0) { total, item in
            total + (Double(item.1) / 5.0) * (Double(item.0.weight) / 100.0)
        }
        let awarded = min(max(Int((weightedFraction * Double(max(totalMarks, 1))).rounded()), 0), max(totalMarks, 1))
        let percentage = Int((weightedFraction * 100).rounded())
        let grade = approximateGrade(for: percentage)
        let criterionSections = scored.map {
            """
            ### \($0.0.name) — \($0.1)/5
            - **Weight:** \($0.0.weight)%
            - **Detected evidence:** \($0.2)
            - **To reach the next band:** add precise subject evidence, make the reasoning explicit, and answer the command term directly.
            """
        }.joined(separator: "\n\n")
        let weakest = scored.min { $0.1 < $1.1 }?.0.name ?? "Analysis"

        return """
        ## Result
        - **Estimated mark:** \(awarded)/\(max(totalMarks, 1)) (\(percentage)%)
        - **Approximate IB grade:** \(grade)/7
        - This is a local rubric estimate; official grade boundaries and examiner judgement can differ.

        ## Criterion grading
        \(criterionSections)

        ## Next actions
        1. Strengthen **\(weakest)** with a direct claim followed by subject-specific evidence and explicit reasoning.
        2. Answer each command term separately and show every method, diagram label, example, or textual reference needed for marks.
        3. Finish with a justified conclusion that states the conditions or limitations affecting the answer.
        """
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
    }

    private static func tokens(_ value: String) -> [String] {
        normalized(value).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func markerCoverage(in answer: String, markers: [String]) -> Double {
        let matches = markers.filter { answer.contains($0) }.count
        return min(Double(matches) / 3.0, 1)
    }

    private static func approximateGrade(for percentage: Int) -> Int {
        switch percentage {
        case 80...: return 7
        case 70...: return 6
        case 60...: return 5
        case 50...: return 4
        case 40...: return 3
        case 25...: return 2
        default: return 1
        }
    }
}

nonisolated enum PracticeExamFallback: Sendable {
    static func markdown(
        subject: String,
        level: String,
        unit: String,
        topics: [String],
        subtopics: [String]
    ) -> String {
        let topic = topics.first ?? "the selected topic"
        let subtopic = subtopics.first ?? topic
        let commandTerms = SubjectKnowledge.knowledge(for: subject)?.commandTerms ?? ["Explain", "Apply", "Evaluate"]
        let explain = commandTerms.first(where: { $0.caseInsensitiveCompare("Explain") == .orderedSame }) ?? "Explain"
        let evaluate = commandTerms.first(where: {
            $0.caseInsensitiveCompare("Evaluate") == .orderedSame ||
                $0.caseInsensitiveCompare("Discuss") == .orderedSame
        }) ?? "Evaluate"
        return """
        ## \(subject) \(level) Practice Set
        **Unit:** \(unit)

        **Focus:** \(subtopic)

        ### Section A - Retrieval and application
        1. Define the central idea in **\(subtopic)** and distinguish it from one related concept. **[3 marks]**
        2. \(explain) the reasoning, mechanism, or method behind **\(subtopic)**. Show each step needed for a complete response. **[5 marks]**
        3. Apply **\(topic)** to a new situation. State any assumption, label any diagram, and show working where relevant. **[6 marks]**

        ### Section B - Extended response
        4. \(evaluate) the claim that **\(subtopic)** is the most important factor in this part of the course. Use evidence, a counterargument, and a justified conclusion. **[8 marks]**

        ### Mark scheme and self-check
        - Q1: precise definition, valid distinction, correct terminology.
        - Q2: complete causal or logical chain; no missing link between evidence and conclusion.
        - Q3: correct application, method, units or labels, and interpretation.
        - Q4: balanced argument, course-specific evidence, limitation, and conditional judgement.

        > Local practice paper generated because the configured AI provider was unavailable. Your answers and marks still count toward this session when recorded in notes and the completion check-in.
        """
    }
}

// The session header's ticking clock. It owns its own Timer + elapsed state so
// the parent body is NOT re-evaluated every second. If `elapsed` lived in the
// parent, the whole workspace (including the chat / flashcard / exam panels)
// would reconstruct once per tick and FormattedMessageContent would re-parse
// every message, card and exam block every second.
private struct SessionClockView: View {
    let startDate: Date
    let durationMinutes: Int

    var body: some View {
        TimelineView(.periodic(from: startDate, by: 1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startDate))
            let isOver = elapsed > Double(durationMinutes * 60)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%02d:%02d", Int(elapsed) / 60, Int(elapsed) % 60))
                    .font(.system(size: 15, weight: .medium).monospacedDigit())
                    .foregroundStyle(isOver ? IBColors.warning : IBColors.ink)
                Text("of \(durationMinutes) min")
                    .font(IBTypography.caption)
                    .foregroundStyle(IBColors.inkTertiary)
            }
            .fixedSize()
        }
    }
}

/// Elapsed time as one quiet line under the header, in place of a ring and pill.
private struct SessionTimeLine: View {
    let startDate: Date
    let durationMinutes: Int

    var body: some View {
        TimelineView(.periodic(from: startDate, by: 5)) { context in
            let target = max(Double(durationMinutes * 60), 1)
            let fraction = min(max(context.date.timeIntervalSince(startDate) / target, 0), 1)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(IBColors.border)
                    Rectangle()
                        .fill(fraction >= 1 ? IBColors.warning : IBColors.accent)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 2)
            .accessibilityHidden(true)
        }
    }
}

/// Appears once the planned time is up so extending is one click, with nothing
/// reset. The session never ends by itself.
private struct SessionOvertimePrompt: View {
    let startDate: Date
    let durationMinutes: Int
    let isBusy: Bool
    let onExtend: (Int) -> Void
    let onFinish: () -> Void

    var body: some View {
        TimelineView(.periodic(from: startDate, by: 5)) { context in
            if context.date.timeIntervalSince(startDate) > Double(durationMinutes * 60) {
                HStack(spacing: 8) {
                    Text("Your planned time is up. Your progress is safe; keep going for as long as you like.")
                        .font(IBTypography.caption)
                        .foregroundStyle(IBColors.inkSecondary)
                    Spacer()
                    Button("+15 min") { onExtend(15) }.controlSize(.small)
                    Button("+30 min") { onExtend(30) }.controlSize(.small)
                    Button("Finish", action: onFinish).controlSize(.small)
                }
                .disabled(isBusy)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(IBColors.warning.opacity(0.10))
            }
        }
    }
}

/// A recovery-friendly focus rhythm for learners who find short Pomodoro
/// intervals too fragmented. It defaults to 45 minutes of focus followed by a
/// 15-minute break and never changes the study plan's recorded duration.
private struct FocusRhythmView: View {
    private enum Phase {
        case focus
        case breakTime

        var title: String { self == .focus ? "Focus" : "Break" }
        var duration: Int { self == .focus ? 45 * 60 : 15 * 60 }
    }

    @State private var phase: Phase = .focus
    @State private var remaining = 45 * 60
    @State private var isRunning = false
    @State private var cycle = 1

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(phase.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(IBColors.inkTertiary)
                Text(format(remaining))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(isRunning ? IBColors.ink : IBColors.inkSecondary)
            }
            Spacer(minLength: 0)
            Button {
                isRunning.toggle()
            } label: {
                Image(systemName: isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(IBColors.inkSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .hoverHighlight()
            }
            .buttonStyle(IBPressStyle())
            .help(isRunning ? "Pause focus rhythm" : "Start focus rhythm")
            .accessibilityLabel(isRunning ? "Pause focus rhythm" : "Start focus rhythm")

            Button {
                advance()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(IBColors.inkSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .hoverHighlight()
            }
            .buttonStyle(IBPressStyle())
            .help("Skip to the next focus or break phase")
            .accessibilityLabel("Skip to the next phase")
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard isRunning else { continue }
                if remaining > 0 {
                    remaining -= 1
                } else {
                    advance()
                }
            }
        }
    }

    private func advance() {
        phase = phase == .focus ? .breakTime : .focus
        remaining = phase.duration
        if phase == .focus { cycle += 1 }
        isRunning = false
    }

    private func format(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

// Rendered from ActiveStudySessionView.planPanel; kept as a separate struct so
// the markdown is isolated from this parent body's re-evaluations (tab
// switches, chat updates, etc.).
private struct PlanPanelView: View {
    let plan: StudyPlan
    @Binding var completedTaskIDs: Set<UUID>
    let advice: String
    let resources: [LearningResource]
    let onStartTask: (StudyPlanTask) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !resources.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Start with a trusted source", systemImage: "book.pages")
                                .font(.headline)
                            Spacer()
                            Text("Read, model, then retrieve")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(resources) { resource in
                            Link(destination: resource.url) {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "arrow.up.right.square")
                                        .foregroundStyle(IBColors.accent)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(resource.title)
                                            .font(.callout.weight(.semibold))
                                        Text("\(resource.provider) · \(resource.purpose)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Open \(resource.title)")
                        }
                    }
                    .padding(.bottom, 4)

                    Divider()
                }

                if !plan.planTasks.isEmpty {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Session sequence")
                                .font(.title3.bold())
                            Text("\(completedTaskIDs.count) of \(plan.planTasks.count) complete · \(plan.planTasks.reduce(0) { $0 + $1.minutes }) minutes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(IBColors.inkTertiary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Coach cue")
                                .font(.caption.weight(.bold))
                            Text(advice)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(IBColors.inkTertiary.opacity(0.08))
                    )

                    ForEach(Array(plan.planTasks.enumerated()), id: \.element.id) { index, task in
                        HStack(alignment: .top, spacing: 14) {
                            Button {
                                withAnimation(IBAnimation.snappy) {
                                    if completedTaskIDs.contains(task.id) {
                                        completedTaskIDs.remove(task.id)
                                    } else {
                                        completedTaskIDs.insert(task.id)
                                    }
                                }
                            } label: {
                                Image(systemName: completedTaskIDs.contains(task.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(completedTaskIDs.contains(task.id) ? IBColors.success : IBColors.accent)
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                            .help(completedTaskIDs.contains(task.id) ? "Mark task incomplete" : "Mark task complete")

                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(task.title)
                                        .font(.headline)
                                        .strikethrough(completedTaskIDs.contains(task.id), color: .secondary)
                                    Spacer()
                                    Label("\(task.minutes) min", systemImage: "clock")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(task.subtopicName.isEmpty ? task.topicName : "\(task.topicName) · \(task.subtopicName)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(IBColors.accent)
                                Text(task.instructions)
                                    .font(.callout)
                                    .lineSpacing(3)
                                Label(task.successCriterion, systemImage: "checkmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if task.flashcardTarget > 0 {
                                    Label("\(task.flashcardTarget) flashcards", systemImage: "rectangle.on.rectangle")
                                        .font(.caption)
                                        .foregroundStyle(IBColors.inkTertiary)
                                }

                                Button {
                                    onStartTask(task)
                                } label: {
                                    Label(completedTaskIDs.contains(task.id) ? "Revisit task" : "Start this task", systemImage: "arrow.right.circle")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(IBColors.accent)
                            }
                        }
                        .padding(.vertical, 12)
                        if index < plan.planTasks.count - 1 {
                            Divider()
                        }
                    }
                } else if plan.planMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Session Ready")
                            .font(.system(size: 18, weight: .bold))
                        Text("This session does not have a generated plan yet. You can still use ARIA, take notes, and generate flashcards for \(plan.selectionSummary).")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(cornerRadius: IBRadius.md)
                } else {
                    FormattedMessageContent(text: plan.planMarkdown)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(cornerRadius: IBRadius.md)
                }
            }
            .padding(20)
        }
    }
}
