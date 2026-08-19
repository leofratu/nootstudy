import SwiftUI
import SwiftData

struct ActiveStudySessionView: View {
    let plan: StudyPlan
    let onComplete: (() -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ProgressionEventCenter.self) private var progressionEvents
    @Query private var profiles: [UserProfile]
    @Query private var subjects: [Subject]
    @Query(sort: \StudySession.endDate, order: .reverse) private var recentStudySessions: [StudySession]

    @State private var sessionStartDate = Date()
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
    @State private var flashcardError: String?
    @State private var flashcardBatchSize = 10
    @State private var flashcardTopicName = ""
    @State private var flashcardSubtopicName = ""
    @State private var flashcardDifficulty: CardDifficulty = .exam
    @State private var completedTaskIDs: Set<UUID> = []
    @State private var showRewardPulse = false
    @State private var previousStreak = 0
    @State private var completedStreak = 0
    @State private var revealedCards: Set<Int> = []
    @State private var examMarkdown = ""
    @State private var isGeneratingExam = false
    @State private var examResponse = ""
    @State private var examGradingMarkdown = ""
    @State private var isGradingExam = false
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

    private struct GeneratedFlashcard: Identifiable {
        let id = UUID()
        let topicName: String
        let subtopic: String
        let front: String
        let back: String
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
            set: { flashcardBatchSize = min(max($0, 1), 50) }
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
        ARIAService.normalizedDurationMinutes(elapsed / 60)
    }

    private var dedicatedMinutesDouble: Double {
        Double(dedicatedMinutes)
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
        case chat = "ARIA Coach"
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
        }
        .onDisappear {
            saveSessionNotes()
        }
        .sheet(isPresented: $showCompletionCheckIn) {
            completionCheckIn
        }
    }

    private var sessionWorkspace: some View {
        VStack(spacing: 0) {
            sessionHeader
                .padding(16)

            Divider()

            HStack(spacing: 0) {
                sessionTabBar
                    .frame(width: 190)
                    .background(IBColors.surface.opacity(0.72))

                Divider()

                panelContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            bottomBar
                .padding(14)
                .background(.bar)
        }
    }

    private func prepareFlashcardsIfRequested() {
        guard (plan.prepareFlashcards == true || plan.flashcardOnly == true), !didPrepareFlashcards else { return }
        didPrepareFlashcards = true
        selectedTab = .flashcards
        flashcardBatchSize = min(max(plan.flashcardTargetCount ?? 10, 5), 50)
        if let raw = plan.flashcardDifficultyRaw, let value = CardDifficulty(rawValue: raw) { flashcardDifficulty = value }
        generateFlashcards()
    }

    private func initializeFlashcardScope() {
        guard flashcardTopicName.isEmpty else { return }
        flashcardTopicName = flashcardTopics.first ?? plan.topicName
        flashcardSubtopicName = flashcardSubtopics.first ?? ""
    }

    // MARK: - Header

    private var sessionHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(subjectColor(plan.subjectName).opacity(0.1))
                    .frame(width: 42, height: 42)
                Image(systemName: subjectIcon(plan.subjectName))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(subjectColor(plan.subjectName))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(plan.subjectName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("FOCUS SESSION")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(subjectColor(plan.subjectName))
                }
                Text(plan.selectionSummary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Timer + progress ring live in their own subview so the parent
            // body is not re-evaluated every second.
            SessionTimerView(startDate: sessionStartDate, durationMinutes: plan.durationMinutes)

            FocusRhythmView()

            Button { dismiss() } label: {
                Label("Close", systemImage: "xmark")
            }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Close study session")
                .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: - Tab Bar

    private var sessionTabBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WORKSPACE")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .padding(.top, 14)

            ForEach(SessionTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 18)
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                        if tab == .flashcards && !generatedCards.isEmpty {
                            Text("\(generatedCards.count)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(IBColors.electricBlue))
                                .foregroundStyle(.white)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedTab == tab ? IBColors.electricBlue.opacity(0.11) : Color.clear)
                    )
                    .foregroundStyle(
                        selectedTab == tab
                            ? AnyShapeStyle(IBColors.electricBlue)
                            : AnyShapeStyle(.secondary)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }

            Divider().padding(.horizontal, 12).padding(.vertical, 6)

            if let nextTask {
                VStack(alignment: .leading, spacing: 6) {
                    Text("UP NEXT")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                    Text(nextTask.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                    Label("\(nextTask.minutes) min", systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button("Open task", systemImage: "arrow.right.circle") { startTask(nextTask) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.horizontal, 14)
            } else if !plan.planTasks.isEmpty {
                Label("Plan complete", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IBColors.success)
                    .padding(.horizontal, 14)
            }

            Spacer()

            ProgressView(value: Double(completedTaskCount), total: Double(max(plan.planTasks.count, 1)))
                .tint(IBColors.electricBlue)
                .padding(.horizontal, 14)
            Text("\(completedTaskCount) of \(plan.planTasks.count) steps")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
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
        } else if !task.topicName.isEmpty {
            flashcardTopicName = task.topicName
            flashcardSubtopicName = ""
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
                VStack(alignment: .leading, spacing: 10) {
                    if chatMessages.isEmpty {
                        emptyChat
                    }

                    ForEach(Array(chatMessages.enumerated()), id: \.offset) { index, msg in
                        HStack(alignment: .top, spacing: 8) {
                            if msg.role == "user" { Spacer(minLength: 60) }

                            if msg.role == "model" {
                                ZStack {
                                    Circle()
                                        .fill(IBColors.electricBlue.opacity(0.08))
                                        .frame(width: 26, height: 26)
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 11))
                                        .foregroundStyle(IBColors.electricBlue)
                                }
                                .padding(.top, 2)
                            }

                            FormattedMessageContent(text: msg.text)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(msg.role == "user"
                                              ? IBColors.electricBlue.opacity(0.08)
                                              : Color.secondary.opacity(0.04))
                                )

                            if msg.role == "model" { Spacer(minLength: 60) }
                        }
                    }

                    if isChatting {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(IBColors.electricBlue.opacity(0.08))
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

            Divider()

            // Input
            HStack(spacing: 8) {
                TextField("Ask ARIA about \(plan.studyScope.title)…", text: $chatInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .onSubmit { sendMessage() }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(
                            chatInput.isEmpty
                                ? AnyShapeStyle(.tertiary)
                                : AnyShapeStyle(IBColors.electricBlue)
                        )
                }
                .buttonStyle(.borderless)
                .disabled(chatInput.isEmpty || isChatting)
                .help("Send message")
            }
            .padding(12)
            .glassCard(cornerRadius: IBRadius.md)
        }
    }

    private var emptyChat: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 30)

            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundStyle(.tertiary)

            Text("Chat with ARIA")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text("Full context — ARIA knows your grades,\nprogress, and study history.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            VStack(spacing: 6) {
                quickPrompt("Explain \(plan.studyScope.title) simply")
                quickPrompt("Give me a practice question")
                quickPrompt("What are common exam mistakes here?")
                quickPrompt("How is this assessed in the IB exam?")
                quickPrompt("Create a mnemonic for key terms")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Flashcards Panel

    private var flashcardsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                flashcardGenerationToolbar
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

    private var flashcardGenerationToolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Session flashcards")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Generate a focused batch, review it, then add more without leaving the session.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isGeneratingCards {
                ProgressView().controlSize(.small)
            } else {
                HStack(spacing: 5) {
                    Text("Cards")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Count", value: flashcardBatchBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 46)
                    Stepper("Card count", value: flashcardBatchBinding, in: 1...50)
                        .labelsHidden()
                    Picker("IB difficulty", selection: $flashcardDifficulty) {
                        ForEach(CardDifficulty.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 110)
                }
                Button(action: generateFlashcards) {
                    Label(
                        generatedCards.isEmpty ? "Generate \(flashcardBatchSize)" : "Add \(flashcardBatchSize) More",
                        systemImage: "sparkles"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: IBRadius.md)
    }

    @ViewBuilder
    private var flashcardScopeSection: some View {
        if !flashcardTopics.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Scope")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Unit").font(.caption2).foregroundStyle(.tertiary)
                        Text(flashcardUnitName).font(.caption.weight(.medium)).lineLimit(1)
                    }
                    .frame(maxWidth: 180, alignment: .leading)
                    Picker("Topic", selection: $flashcardTopicName) {
                        ForEach(flashcardTopics, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(maxWidth: 220)
                    .onChange(of: flashcardTopicName) { _, _ in
                        flashcardSubtopicName = flashcardSubtopics.first ?? ""
                    }
                    Picker("Subunit", selection: $flashcardSubtopicName) {
                        Text("All subunits").tag("")
                        ForEach(flashcardSubtopics, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(maxWidth: 240)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(IBColors.electricBlue.opacity(0.045)))
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
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(IBColors.danger.opacity(0.06)))
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
            FormattedMessageContent(text: card.front)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(IBColors.electricBlue.opacity(0.04)))
            flashcardAnswer(card, index: index)
        }
        .padding(12)
        .glassCard(cornerRadius: IBRadius.md)
    }

    private func flashcardRowHeader(_ card: GeneratedFlashcard, index: Int) -> some View {
        HStack {
            Text("Card \(index + 1)").font(.caption2.bold()).foregroundStyle(.tertiary)
            Spacer()
            Text(card.topicName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            if savedCardIDs.contains(card.id) {
                Label("Saved", systemImage: "checkmark.circle.fill").font(.caption2).foregroundStyle(.secondary)
            } else {
                Button("Save", systemImage: "plus.circle.fill") { saveCardToSubject(card) }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
    }

    @ViewBuilder
    private func flashcardAnswer(_ card: GeneratedFlashcard, index: Int) -> some View {
        if revealedCards.contains(index) {
            FormattedMessageContent(text: card.back)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.03)))
            if let rating = cardRatings[card.id] {
                Label("Rated \(rating.label)", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IBColors.success)
            } else {
                HStack(spacing: 8) {
                    Text("Recall").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    ForEach(RecallQuality.allCases, id: \.self) { quality in
                        Button(quality.label) { rateGeneratedCard(card, quality: quality) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(recallTint(quality))
                    }
                }
            }
        } else {
            Button("Reveal answer", systemImage: "eye") {
                _ = withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { revealedCards.insert(index) }
                IBHaptics.light()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .frame(maxWidth: .infinity)
        }
    }

    private func recallTint(_ quality: RecallQuality) -> Color {
        switch quality {
        case .again: return IBColors.danger
        case .hard: return IBColors.warning
        case .good, .easy: return IBColors.electricBlue
        }
    }

    @ViewBuilder
    private var saveAllGeneratedCardsButton: some View {
        if unsavedGeneratedCards.count > 1 {
            Button("Save All \(unsavedGeneratedCards.count) Cards", systemImage: "square.and.arrow.down", action: saveAllCards)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Practice Exam Panel

    private var examPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                examToolbar
                examContent
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 60)
        }
    }

    private var examToolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Practice Exam")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Generate, answer, and grade against subject-specific IB criteria.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isGeneratingExam {
                ProgressView().controlSize(.small)
            } else if examMarkdown.isEmpty {
                Button("Generate Exam", systemImage: "sparkles", action: generateExam)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                Button("New Exam", systemImage: "arrow.clockwise") {
                    clearExamWorkspace()
                    generateExam()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button("Discard", systemImage: "trash", role: .destructive, action: clearExamWorkspace)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: IBRadius.md)
    }

    @ViewBuilder
    private var examContent: some View {
        if examMarkdown.isEmpty && !isGeneratingExam {
            ContentUnavailableView(
                "No practice exam",
                systemImage: "pencil.and.outline",
                description: Text("Generate a scoped paper, write your response, then grade it with IB-aligned criteria.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else if !examMarkdown.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                examPaper
                examRubricOverview
                examResponseEditor
                examGradingResult
            }
        }
    }

    private var examPaper: some View {
        FormattedMessageContent(text: examMarkdown)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: IBRadius.md)
    }

    private var examRubricOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("IB grading criteria", systemImage: "list.bullet.clipboard")
                    .font(.headline)
                Spacer()
                Text("\(IBExamRubric.totalMarks(in: examMarkdown)) marks")
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
                        .foregroundStyle(IBColors.electricBlue)
                        .frame(width: 42, alignment: .trailing)
                }
                .padding(.vertical, 4)
                if criterion.name != examRubricCriteria.last?.name {
                    Divider()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(IBColors.electricBlue.opacity(0.045))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(IBColors.electricBlue.opacity(0.12)))
        )
    }

    private var examResponseEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Your response", systemImage: "square.and.pencil")
                    .font(.headline)
                Spacer()
                Text("\(examResponse.split(whereSeparator: \.isWhitespace).count) words")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            TextEditor(text: $examResponse)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 240)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.035)))
            HStack {
                Text("Rubric: \(IBExamRubric.shortName(for: plan.subjectName))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isGradingExam {
                    ProgressView().controlSize(.small)
                }
                Button("Grade with IB Rubric", systemImage: "checkmark.seal", action: gradeExamResponse)
                    .buttonStyle(.borderedProminent)
                    .disabled(examResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGradingExam)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8).fill(IBColors.surface))
    }

    @ViewBuilder
    private var examGradingResult: some View {
        if let examGradingError {
            Label(examGradingError, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(IBColors.danger)
        }
        if !examGradingMarkdown.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("IB rubric feedback", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(IBColors.success)
                FormattedMessageContent(text: examGradingMarkdown)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 8).fill(IBColors.success.opacity(0.055)))
        }
    }

    // MARK: - Notes Panel

    private var notesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SESSION NOTES")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)
                Spacer()
                Text("\(sessionNotes.count) chars")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.quaternary)
                if !noteSaveStatus.isEmpty {
                    Text(noteSaveStatus)
                        .font(.caption2)
                        .foregroundStyle(IBColors.success)
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
        plan.notes = sessionNotes
        do {
            try context.save()
            noteSaveStatus = "Saved"
        } catch {
            noteSaveStatus = "Not saved"
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            // Session status
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                Text("Session active")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if !generatedCards.isEmpty {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(generatedCards.count) generated · \(reviewedCardCount) reviewed")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            if !plan.planTasks.isEmpty {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(completedTaskCount)/\(plan.planTasks.count) steps")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(completedTaskCount == plan.planTasks.count ? IBColors.success : .secondary)
            }

            Spacer()

            if let nextTask {
                Button {
                    startTask(nextTask)
                } label: {
                    Label("Next: \(nextTask.title)", systemImage: "arrow.right.circle")
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(nextTask.instructions)
            }

            Button {
                prepareCompletionCheckIn()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                    Text("Complete Session")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(Color.white)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isCompletingSession ? IBColors.secondaryText : IBColors.success)
                )
            }
            .buttonStyle(.plain)
            .disabled(isCompletingSession)
        }
    }

    private var completionCheckIn: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    StudioPageHeader(
                        eyebrow: "Session evidence",
                        title: "Check your recall",
                        subtitle: "Rate what you can explain without notes. Each answer updates only its matching topic or subunit.",
                        symbol: "checkmark.seal",
                        tint: IBColors.teal
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
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(IBColors.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(IBColors.cardBorder, lineWidth: 1)
                                )
                        )
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
                    Button {
                        completeSession()
                    } label: {
                        Text("Complete Session")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(hasCompleteCheckIn && !isCompletingSession ? IBColors.success : IBColors.secondaryText)
                            )
                    }
                    .buttonStyle(.plain)
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
                .font(.system(size: 11))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(IBColors.electricBlue.opacity(0.06))
                        .overlay(Capsule().strokeBorder(IBColors.electricBlue.opacity(0.12), lineWidth: 0.5))
                )
                .foregroundStyle(IBColors.electricBlue)
        }
        .buttonStyle(.plain)
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
                Circle().fill(.green.opacity(0.06)).frame(width: 90, height: 90)
                Circle().fill(.green.opacity(0.1)).frame(width: 65, height: 65)
                Image(systemName: "checkmark.seal.fill").font(.system(size: 36)).foregroundStyle(.green)
            }
            .glow(color: .green, radius: 20)
            Text("Session Complete!").font(.system(size: 22, weight: .bold, design: .rounded))
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.title2)
                    .foregroundStyle(IBColors.gold)
                    .symbolEffect(.bounce, value: showRewardPulse)
                Text("+").font(.title2.bold())
                AnimatedCounter(value: xpAwarded, font: .system(size: 30, weight: .black, design: .rounded), color: IBColors.gold)
                Text("XP").font(.headline).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule().fill(IBColors.gold.opacity(0.10)))
            .scaleEffect(showRewardPulse ? 1 : 0.72)
            .opacity(showRewardPulse ? 1 : 0)
            .animation(IBAnimation.bounce, value: showRewardPulse)
        }
    }

    private var completionStats: some View {
        HStack(spacing: 0) {
            StatCard(value: "\(dedicatedMinutes)m", label: "Dedicated", color: .orange, icon: "clock.fill")
            Divider().frame(height: 44)
            StatCard(value: plan.subjectName, label: "Subject", color: subjectColor(plan.subjectName), icon: "book.fill")
            Divider().frame(height: 44)
            StatCard(value: "\(reviewedCardCount)", label: "Reviewed", color: IBColors.electricBlue, icon: "rectangle.on.rectangle")
            Divider().frame(height: 44)
            StatCard(value: "+\(xpAwarded)xp", label: "Earned", color: .purple, icon: "star.fill")
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
                        .foregroundStyle(IBColors.streakOrange)
                    Text(completedStreak > previousStreak ? "+1 from this session" : "Maintained today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(IBColors.streakOrange.opacity(0.08)))
            }
        }
        .frame(maxWidth: 550, alignment: .leading)
    }

    @ViewBuilder
    private var completionReviewSchedule: some View {
        Label(
            "Saved cards now return through the daily recall queue, capped at \(ReviewDailyLimitPolicy.maximumCards) cards.",
            systemImage: "rectangle.stack.badge.play"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(IBColors.electricBlue)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(IBColors.electricBlue.opacity(0.04)))
    }

    @ViewBuilder
    private var completionRank: some View {
        if let profile = profiles.first {
            Label(profile.achievedStep.displayName, systemImage: profile.achievedStep.rank.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(IBColors.electricBlue)
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
                .foregroundStyle(isPositive ? IBColors.success : IBColors.coral)
            Text(isPositive ? positiveLabel : negativeLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill((isPositive ? IBColors.success : IBColors.coral).opacity(0.08))
        )
    }

    // MARK: - Timer

    private func startTimer() {
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
        isGeneratingCards = true

        Task {
            do {
                await MainActor.run {
                    flashcardError = nil
                }

                var generatedBatch: [GeneratedFlashcard] = []
                guard let subject = subjects.first(where: { $0.name == plan.subjectName }) else {
                    throw NSError(
                        domain: "IBVault.ActiveStudySessionView",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Could not find the subject needed to save generated flashcards."]
                    )
                }

                let generatedCardsForScope = try await CardGeneratorService.generateCards(
                    subject: subject,
                    topicName: flashcardTopicName,
                    subtopic: flashcardSubtopicName,
                    count: flashcardBatchSize,
                    localStartingIndex: generatedCards.count,
                    context: context,
                    preferredDifficulty: flashcardDifficulty
                )
                generatedBatch.append(contentsOf: generatedCardsForScope.map {
                    GeneratedFlashcard(
                        topicName: $0.topicName,
                        subtopic: $0.subtopic,
                        front: $0.front,
                        back: $0.back
                    )
                })

                var seenSignatures = Set(generatedCards.map { "\($0.front)|\($0.back)" })
                generatedBatch = generatedBatch.filter {
                    seenSignatures.insert("\($0.front)|\($0.back)").inserted
                }

                guard !generatedBatch.isEmpty else {
                    throw NSError(
                        domain: "IBVault.ActiveStudySessionView",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "ARIA returned text, but no valid FRONT/BACK flashcards could be parsed. Try again."]
                    )
                }

                ARIAService.recordFlashcardGeneration(
                    subjectName: plan.subjectName,
                    topicName: plan.topicName,
                    subtopicName: plan.subtopicName,
                    generatedCards: generatedBatch.map { ($0.front, $0.back) },
                    sourceReference: "ActiveStudySessionView.generateFlashcards"
                )

                await MainActor.run {
                    generatedCards.append(contentsOf: generatedBatch)
                    // Persist the generated batch immediately. A session can
                    // be dismissed before the learner taps Save, so generated
                    // cards must not exist only in transient view state.
                    for card in generatedBatch where !savedCardIDs.contains(card.id) {
                        _ = saveCardToSubject(card)
                    }
                    isGeneratingCards = false
                }
            } catch {
                await MainActor.run {
                    flashcardError = error.localizedDescription
                    isGeneratingCards = false
                }
            }
        }
    }

    // MARK: - Exam Generation

    private func clearExamWorkspace() {
        withAnimation(.easeInOut) {
            examMarkdown = ""
            examResponse = ""
            examGradingMarkdown = ""
            examGradingError = nil
        }
    }

    private func generateExam() {
        isGeneratingExam = true
        examMarkdown = ""
        examResponse = ""
        examGradingMarkdown = ""
        examGradingError = nil

        let remoteAvailable: Bool = switch AIConfiguration.provider {
        case .gemini: KeychainService.hasAPIKey
        case .junali: KeychainService.hasJunaliAPIKey
        case .codexCLI: true
        }
        guard remoteAvailable else {
            examMarkdown = PracticeExamFallback.markdown(
                subject: plan.subjectName,
                level: subjects.first(where: { $0.name == plan.subjectName })?.level ?? "",
                unit: plan.selectedUnitNames.first ?? "Selected unit",
                topics: plan.selectedTopicNames,
                subtopics: plan.selectedSubtopicNames
            )
            isGeneratingExam = false
            return
        }

        Task {
            do {
                let prompt = """
                Generate a rigorous Practice Exam paper for:
                Subject: \(plan.subjectName)
                Units: \(plan.selectedUnitNames.joined(separator: ", "))
                Topics: \(plan.selectedTopicNames.joined(separator: ", "))
                \(plan.selectedSubtopicNames.isEmpty ? "" : "Focus subtopics: \(plan.selectedSubtopicNames.joined(separator: ", "))")
                
                Format rules:
                - Output should mimic a true IB past paper format.
                - Use clear sections (e.g., Section A: Short Answer, Section B: Extended Response / Essay).
                - Use rigorous IB command terms (Evaluate, Discuss, To what extent, Compare and contrast).
                - IMPORTANT: Include the exact marks available at the end of every question in brackets, e.g. [4 marks].
                - Distribute marks realistically (total of ~20-30 marks).
                - Do NOT include the answers in the main exam block, just the questions. Provide a small "Mark Scheme / Hints" section at the very end.
                - Ensure layout uses Markdown headings, numbered questions, bullets, and blockquotes effectively.
                - Never use Markdown tables because the native exam workspace intentionally renders criteria as structured rows.
                """

                let response = try await AIProviderService.generateContent(
                    messages: [GeminiMessage(role: "user", text: prompt)],
                    systemInstruction: "You are an exacting IB examiner. Generate rigorous practice exams tailored to the student's stated subject level, with valid LaTeX for equations and a concise mark scheme."
                )

                await MainActor.run {
                    examMarkdown = IBExamRubric.displaySafeMarkdown(response)
                    isGeneratingExam = false
                }
            } catch {
                await MainActor.run {
                    examMarkdown = PracticeExamFallback.markdown(
                        subject: plan.subjectName,
                        level: subjects.first(where: { $0.name == plan.subjectName })?.level ?? "",
                        unit: plan.selectedUnitNames.first ?? "Selected unit",
                        topics: plan.selectedTopicNames,
                        subtopics: plan.selectedSubtopicNames
                    )
                    isGeneratingExam = false
                }
            }
        }
    }

    private func gradeExamResponse() {
        let answer = examResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty, !examMarkdown.isEmpty else { return }
        isGradingExam = true
        examGradingError = nil
        examGradingMarkdown = ""

        let subject = plan.subjectName
        let level = subjects.first(where: { $0.name == subject })?.level ?? ""
        let rubric = IBExamRubric.markdown(for: subject, level: level)
        let totalMarks = IBExamRubric.totalMarks(in: examMarkdown)
        let scopeTerms = plan.selectedTopicNames + plan.selectedSubtopicNames
        let remoteAvailable: Bool = switch AIConfiguration.provider {
        case .gemini: KeychainService.hasAPIKey
        case .junali: KeychainService.hasJunaliAPIKey
        case .codexCLI: true
        }

        guard remoteAvailable else {
            examGradingMarkdown = IBExamRubric.localFeedback(
                subject: subject,
                level: level,
                answer: answer,
                totalMarks: totalMarks,
                scopeTerms: scopeTerms
            )
            isGradingExam = false
            return
        }

        Task {
            do {
                let prompt = """
                Grade this learner response as an exacting \(subject) \(level) IB examiner.

                IB-aligned rubric:
                \(rubric)

                Practice paper (maximum \(totalMarks) marks):
                \(examMarkdown.prefix(14_000))

                Learner response:
                \(answer.prefix(14_000))

                Return concise Markdown with exactly these sections:
                ## Result
                - estimated mark as X/\(totalMarks) and percentage
                - approximate IB grade 1-7, explicitly labelled as an estimate rather than an official boundary result
                ## Criterion grading
                For every criterion use a separate ### heading followed by bullets for weight, awarded performance, brief quoted evidence, and what prevented the next band. Do not use a Markdown table.
                ## Question-level feedback
                Award marks question by question where the paper permits it. Do not award unsupported content.
                ## Next actions
                Three concrete changes that would gain marks on a rewrite.

                Apply the command terms and subject conventions. For mathematics require visible method; for sciences require correct terminology and data handling; for economics and business require application and evaluation; for language and literature require textual analysis, organization, and language quality. Never invent evidence that is absent from the response.
                """
                let response = try await AIProviderService.generateContent(
                    messages: [GeminiMessage(role: "user", text: prompt)],
                    systemInstruction: "You are an IB examiner applying the supplied subject rubric consistently. Grade only the learner response, distinguish correctness from writing length, and explain every deduction."
                )
                await MainActor.run {
                    examGradingMarkdown = IBExamRubric.displaySafeMarkdown(response)
                    isGradingExam = false
                }
            } catch {
                await MainActor.run {
                    examGradingMarkdown = IBExamRubric.localFeedback(
                        subject: subject,
                        level: level,
                        answer: answer,
                        totalMarks: totalMarks,
                        scopeTerms: scopeTerms
                    )
                    examGradingError = "AI grading was unavailable; showing the local rubric estimate."
                    isGradingExam = false
                }
            }
        }
    }

    @discardableResult
    private func saveCardToSubject(_ generatedCard: GeneratedFlashcard) -> StudyCard? {
        guard let subject = subjects.first(where: { $0.name == plan.subjectName }) else { return nil }
        if let persistedID = persistedCardIDs[generatedCard.id],
           let existing = subject.cards.first(where: { $0.id == persistedID }) {
            return existing
        }
        let card = StudyCard(
            topicName: generatedCard.topicName,
            subtopic: generatedCard.subtopic,
            front: generatedCard.front,
            back: generatedCard.back,
            subject: subject,
            sourceStudyPlanID: plan.id,
            sourceStudySessionID: activeSessionID
        )
        subject.cards.append(card)
        do {
            try context.save()
        } catch {
            // Do not leave a card that was never persisted: drop the pending
            // insert so the UI cannot claim a save that did not happen. The
            // failure is surfaced so the user knows the card was not saved.
            context.rollback()
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
        for card in toSave {
            let studyCard = StudyCard(
                topicName: card.topicName,
                subtopic: card.subtopic,
                front: card.front,
                back: card.back,
                subject: subject,
                sourceStudyPlanID: plan.id,
                sourceStudySessionID: activeSessionID
            )
            subject.cards.append(studyCard)
            persistedCardIDs[card.id] = studyCard.id
        }
        do {
            try context.save()
        } catch {
            // Same reasoning as `saveCardToSubject`: a failed save must not be
            // presented as a completed batch.
            context.rollback()
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
            try context.save()
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
        return XPCalculator.xp(
            forStudyMinutes: dedicatedMinutesDouble,
            intensity: intensity
        ) + XPCalculator.xp(forQualities: Array(cardRatings.values), intensity: intensity)
    }

    private func completeSession() {
        guard !isCompletingSession else { return }
        guard hasCompleteCheckIn else {
            completionError = "Rate every selected topic or subunit before completing."
            return
        }
        guard !plan.isCompleted else {
            dismiss()
            return
        }
        isCompletingSession = true
        // Freeze the elapsed time first: every XP / duration / startDate read
        // below (and on the completion screen) must use this single snapshot,
        // not a still-running clock.
        completedElapsed = max(0, IBLocalClock.now.timeIntervalSince(sessionStartDate))
        plan.isCompleted = true
        plan.notes = sessionNotes

        // Log StudySession
        let topics = plan.selectedTopicNames.isEmpty ? [plan.topicName] : plan.selectedTopicNames
        let minutesPerScope = evidenceScopes.isEmpty ? 0 : dedicatedMinutesDouble / Double(evidenceScopes.count)
        let evidence = evidenceScopes.map { scope in
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
            previousStreak = profile.currentStreak
            profile.recordXP(xpAwarded)
            profile.checkAndUpdateStreak()
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

        // Record to ARIA context
        ARIAService.recordPlannedStudySession(
            subjectName: plan.subjectName,
            topics: topics,
            planMarkdown: plan.planMarkdown,
            notes: sessionNotes,
            xpEarned: xpAwarded,
            durationMinutes: dedicatedMinutesDouble
        )

        do {
            try context.save()

            // Must run after the StudySession and StudyActivity records are in the
            // context, or this session's work is invisible to the engine.
            progressionEvents.enqueue(ProgressionService.recompute(context: context))

            IBHaptics.success()
            onComplete?()
            isCompletingSession = false
            showCompletionCheckIn = false
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
            isCompletingSession = false
            completionError = "Could not save the session. Your check-in is still here so you can retry."
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
        let pattern = #"\[(\d+)\s*marks?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return 20 }
        let range = NSRange(paper.startIndex..<paper.endIndex, in: paper)
        let total = regex.matches(in: paper, range: range).reduce(into: 0) { sum, match in
            guard match.numberOfRanges > 1,
                  let markRange = Range(match.range(at: 1), in: paper),
                  let marks = Int(paper[markRange]) else { return }
            sum += marks
        }
        return total > 0 ? total : 20
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
private struct SessionTimerView: View {
    let startDate: Date
    let durationMinutes: Int

    @State private var elapsed: TimeInterval = 0

    private var timeFormatted: String {
        let mins = Int(elapsed) / 60
        let secs = Int(elapsed) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private var timerColor: Color {
        let target = Double(durationMinutes * 60)
        if elapsed > target { return .red }
        if elapsed > target * 0.8 { return .orange }
        return IBColors.electricBlue
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: elapsed > Double(durationMinutes * 60) ? "exclamationmark.triangle.fill" : "timer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(timerColor)
                Text(timeFormatted)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(timerColor)
                Text("/ \(durationMinutes)m")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(timerColor.opacity(0.06))
                    .overlay(Capsule().strokeBorder(timerColor.opacity(0.15), lineWidth: 0.5))
            )

            ProgressRing(
                progress: min(elapsed / Double(durationMinutes * 60), 1.0),
                lineWidth: 4,
                size: 38,
                color: timerColor
            )
        }
        // Async loop is MainActor-isolated and cancels on disappear, so it is
        // Swift-6-safe (no Timer @Sendable closure mutating @State) and keeps
        // the ticking clock out of the parent body.
        .task {
            elapsed = max(0, IBLocalClock.now.timeIntervalSince(startDate))
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                elapsed = max(0, IBLocalClock.now.timeIntervalSince(startDate))
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

        var title: String { self == .focus ? "Focus 45" : "Break 15" }
        var icon: String { self == .focus ? "brain.head.profile" : "figure.walk" }
        var tint: Color { self == .focus ? IBColors.electricBlue : IBColors.teal }
        var duration: Int { self == .focus ? 45 * 60 : 15 * 60 }
    }

    @State private var phase: Phase = .focus
    @State private var remaining = 45 * 60
    @State private var isRunning = false
    @State private var cycle = 1

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: phase.icon)
                .foregroundStyle(phase.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(phase.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(phase.tint)
                Text(format(remaining))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button {
                isRunning.toggle()
            } label: {
                Image(systemName: isRunning ? "pause.fill" : "play.fill")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help(isRunning ? "Pause focus rhythm" : "Start focus rhythm")

            Button {
                advance()
            } label: {
                Image(systemName: "forward.end.fill")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Skip to the next focus or break phase")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(phase.tint.opacity(0.07))
                .overlay(Capsule().strokeBorder(phase.tint.opacity(0.16), lineWidth: 0.5))
        )
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(phase.title), \(format(remaining)), cycle \(cycle)")
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
                                        .foregroundStyle(IBColors.electricBlue)
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
                            .foregroundStyle(IBColors.gold)
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
                            .fill(IBColors.gold.opacity(0.08))
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
                                    .foregroundStyle(completedTaskIDs.contains(task.id) ? IBColors.success : IBColors.electricBlue)
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
                                    .foregroundStyle(IBColors.electricBlue)
                                Text(task.instructions)
                                    .font(.callout)
                                    .lineSpacing(3)
                                Label(task.successCriterion, systemImage: "checkmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if task.flashcardTarget > 0 {
                                    Label("\(task.flashcardTarget) flashcards", systemImage: "rectangle.on.rectangle")
                                        .font(.caption)
                                        .foregroundStyle(IBColors.teal)
                                }

                                Button {
                                    onStartTask(task)
                                } label: {
                                    Label(completedTaskIDs.contains(task.id) ? "Revisit task" : "Start this task", systemImage: "arrow.right.circle")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(IBColors.electricBlue)
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
                            .font(.system(size: 18, weight: .bold, design: .rounded))
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
