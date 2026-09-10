import SwiftUI
import SwiftData

struct NewStudySessionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var subjects: [Subject]

    @State private var step = 0
    @State private var selectedSubject: Subject?
    @State private var selectedTopics: Set<String> = []
    @State private var selectedSubtopicsByTopic: [String: Set<String>] = [:]
    @State private var scheduledDate = IBLocalClock.nextQuarterHour()
    @State private var durationMinutes = 60
    @State private var prepareFlashcards = true
    @State private var flashcardOnly = false
    @State private var flashcardTargetCount = 10
    @State private var flashcardDifficulty: CardDifficulty = .exam
    @State private var cardStudioOptions = CardGenerationOptions(count: 10, difficulty: .exam, style: .basic, tone: .exam, cognitiveSkills: [], useInternalTools: false)
    @State private var planMarkdown = ""
    @State private var planTasks: [StudyPlanTask] = []
    @State private var isGeneratingPlan = false
    @State private var planGenerationFailed = false
    @State private var saveError: String?
    @State private var chatMessages: [(role: String, text: String)] = []
    @State private var chatInput = ""
    @State private var isChatting = false
    // Bumped whenever the wizard's scope changes or a generation starts, so a
    // stale in-flight generation can never overwrite the plan for a subject /
    // topic selection the user has since changed.
    @State private var planGenerationID = UUID()
    @State private var hasInitializedSchedule = false
    private let initialScheduledDate: Date?

    private let durations = [30, 45, 60, 90, 120]
    private static let stepNames = ["Subject", "Topic", "Schedule", "Plan"]

    // Static so the schedule step does not allocate a DateFormatter per render.
    private static let endTimeFormatter: DateFormatter = {
        IBLocalClock.formatter(dateFormat: "HH:mm")
    }()

    init(initialScheduledDate: Date? = nil) {
        self.initialScheduledDate = initialScheduledDate
    }

    private var curriculum: [CurriculumUnit] {
        guard let subject = selectedSubject else { return [] }
        return SyllabusSeeder.curriculum(for: subject.name, level: subject.level)
    }

    private var selectedTopicList: [String] {
        selectedTopics.sorted()
    }

    private var selectedSubtopicList: [String] {
        selectedTopicList.flatMap { topicName in
            selectedSubtopics(for: topicName).sorted()
        }
    }

    private var selectedUnitList: [String] {
        curriculum.compactMap { unit in
            unit.topics.contains(where: { selectedTopics.contains($0.name) }) ? unit.name : nil
        }
    }

    private var recommendedFlashcardCount: Int {
        min(50, max(8, max(selectedSubtopicList.count, selectedTopicList.count) * 4))
    }

    private var selectedTopicSummary: String {
        if selectedTopicList.isEmpty {
            return "No topics selected"
        }
        if selectedTopicList.count == 1 {
            return selectedTopicList.first ?? ""
        }
        return "\(selectedTopicList.count) topics selected"
    }

    private var defaultSchedule: Date {
        IBLocalClock.nextQuarterHour()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Step indicator
                stepIndicator
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                Divider().padding(.top, 12)

                // Content
                ScrollView {
                    Group {
                        switch step {
                        case 0: subjectPicker
                        case 1: topicPicker
                        case 2: schedulePicker
                        case 3: planView
                        default: EmptyView()
                        }
                    }
                    .padding(24)
                }

                Divider()

                // Navigation
                navigationBar
                    .padding(16)
                    .background(.bar)
            }
            .background(.background)
            .navigationTitle("New Study Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                guard !hasInitializedSchedule else { return }
                hasInitializedSchedule = true
                scheduledDate = initialScheduledDate ?? defaultSchedule
            }
            .alert("Could Not Save Plan", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "Your study plan could not be saved.")
            }
        }
        .frame(minWidth: 600, minHeight: 550)
    }

    // MARK: - Step Indicator
    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.stepNames.enumerated()), id: \.offset) { index, name in
                HStack(spacing: 6) {
                    Circle()
                        .fill(index <= step ? IBColors.accent : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(index <= step ? .primary : .secondary)
                }
                if index < Self.stepNames.count - 1 {
                    Rectangle()
                        .fill(index < step ? IBColors.accent : Color.secondary.opacity(0.2))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Step 0: Subject
    private var subjectPicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What would you like to study?")
                .font(.title3.bold())
            Text("Pick a subject to focus on.")
                .font(.callout)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(subjects, id: \.id) { subject in
                    Button {
                        selectedSubject = subject
                        selectedTopics.removeAll()
                        selectedSubtopicsByTopic.removeAll()
                        planMarkdown = ""
                        planTasks = []
                        chatMessages.removeAll()
                        invalidatePlanGeneration()
                        IBHaptics.light()
                        withAnimation(IBAnimation.smooth) {
                            step = 1
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(IBColors.inkTertiary)
                                .frame(width: 10, height: 10)
                            Text(subject.name)
                                .font(.callout.weight(.medium))
                            Spacer()
                            Text(subject.level)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedSubject?.id == subject.id ? IBColors.inkTertiary.opacity(0.08) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(selectedSubject?.id == subject.id ? IBColors.inkTertiary : Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedSubject?.id == subject.id ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Step 1: Topic
    private var topicPicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose your unit and topics")
                .font(.title3.bold())
            if let subject = selectedSubject {
                Text("From \(subject.name) \(subject.level) curriculum")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if !selectedTopics.isEmpty {
                Text("\(selectedTopicList.count) topic\(selectedTopicList.count == 1 ? "" : "s") selected")
                    .font(.caption)
                    .foregroundStyle(IBColors.accent)
            }

            ForEach(curriculum, id: \.name) { unit in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(unit.name)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(unitTopicsSelected(in: unit) ? "Clear Unit" : "Select Unit") {
                            toggleUnit(unit)
                            IBHaptics.light()
                        }
                        .font(.caption2)
                        .buttonStyle(.borderless)
                    }

                    ForEach(unit.topics, id: \.name) { topic in
                        Button {
                            toggleTopic(topic.name)
                            IBHaptics.light()
                        } label: {
                            HStack {
                                Image(systemName: selectedTopics.contains(topic.name) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(
                                        selectedTopics.contains(topic.name)
                                            ? AnyShapeStyle(IBColors.accent)
                                            : AnyShapeStyle(.secondary)
                                    )
                                Text(topic.name)
                                    .font(.callout)
                                Spacer()
                                Text("\(topic.subtopics.count) subtopics")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if selectedTopics.contains(topic.name) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Optional subtopics:")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    if !selectedSubtopics(for: topic.name).isEmpty {
                                        Text("\(selectedSubtopics(for: topic.name).count) selected")
                                            .font(.caption2)
                                            .foregroundStyle(IBColors.accent)
                                    }
                                }
                                .padding(.bottom, 4)
                                
                                ForEach(topic.subtopics, id: \.self) { sub in
                                    Button {
                                        toggleSubtopic(topic: topic.name, subtopic: sub)
                                        IBHaptics.light()
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: selectedSubtopics(for: topic.name).contains(sub) ? "checkmark.square.fill" : "square")
                                                .font(.system(size: 12))
                                                .foregroundStyle(
                                                    selectedSubtopics(for: topic.name).contains(sub)
                                                        ? AnyShapeStyle(IBColors.accent)
                                                        : AnyShapeStyle(.tertiary)
                                                )
                                            Text(sub)
                                                .font(.caption)
                                                .foregroundStyle(selectedSubtopics(for: topic.name).contains(sub) ? .primary : .secondary)
                                            Spacer()
                                        }
                                        .padding(.vertical, 3)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                if !topic.subtopics.isEmpty {
                                    HStack(spacing: 8) {
                                        Button("Select All") {
                                            selectedSubtopicsByTopic[topic.name] = Set(topic.subtopics)
                                            IBHaptics.light()
                                        }
                                        .font(.caption2)
                                        .buttonStyle(.borderless)
                                        
                                        Button("Clear") {
                                            selectedSubtopicsByTopic[topic.name] = Set<String>()
                                            IBHaptics.light()
                                        }
                                        .font(.caption2)
                                        .buttonStyle(.borderless)
                                    }
                                    .padding(.top, 4)
                                }
                            }
                            .padding(.leading, 28)
                        }

                        if topic.name != unit.topics.last?.name {
                            Divider()
                        }
                    }
                }
                .padding(12)
                .glassCard()
            }
        }
    }

    // MARK: - Step 2: Schedule
    private var schedulePicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("When do you want to study?")
                .font(.title3.bold())
            Text("Times use your Mac's current clock and time zone.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    DatePicker("Date", selection: $scheduledDate, displayedComponents: .date)
                        .datePickerStyle(.compact)

                    DatePicker("Start", selection: $scheduledDate, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                }

                HStack(spacing: 8) {
                    Button("Start now") {
                        scheduledDate = IBLocalClock.nextQuarterHour()
                    }
                    .buttonStyle(.bordered)

                    Button("In 30 min") {
                        let base = IBLocalClock.nextQuarterHour()
                        scheduledDate = IBLocalClock.calendar.date(byAdding: .minute, value: 30, to: base) ?? base
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Text(IBLocalClock.timeZone.abbreviation(for: scheduledDate) ?? "Local")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Divider()

                Picker("Duration:", selection: $durationMinutes) {
                    ForEach(durations, id: \.self) { d in
                        Text("\(d) minutes").tag(d)
                    }
                }

                HStack(spacing: 10) {
                    Label(startTimeFormatted, systemImage: "play.circle")
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.tertiary)
                    Label(endTimeFormatted, systemImage: "stop.circle")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

                Label(
                    "Recall is handled by the daily flashcard queue (up to \(ReviewDailyLimitPolicy.maximumCards) cards), not extra calendar sessions.",
                    systemImage: "rectangle.stack.badge.play"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Divider()

                Toggle(isOn: $prepareFlashcards) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Prepare flashcards when the session opens", systemImage: "rectangle.on.rectangle.angled")
                            .font(.subheadline.weight(.medium))
                        Text("ARIA will open the scoped flashcard workspace for this session.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $flashcardOnly) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Flashcards-only session", systemImage: "rectangle.on.rectangle.fill")
                            .font(.subheadline.weight(.medium))
                        Text("Open directly into recall practice.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: flashcardOnly) { _, enabled in if enabled { prepareFlashcards = true } }

                CardStudioOptionsView(options: $cardStudioOptions)
                    .onChange(of: cardStudioOptions.count) { _, v in flashcardTargetCount = v }
                    .onChange(of: cardStudioOptions.difficulty) { _, v in flashcardDifficulty = v }
                    .onChange(of: flashcardTargetCount) { _, v in cardStudioOptions.count = v }
                    .onChange(of: flashcardDifficulty) { _, v in cardStudioOptions.difficulty = v }
                HStack {
                    Spacer()
                    Button("Use \(recommendedFlashcardCount) recommended") { cardStudioOptions.count = recommendedFlashcardCount; flashcardTargetCount = recommendedFlashcardCount }
                        .buttonStyle(.borderless).font(.caption)
                    Spacer()
                }
                Text("ARIA spreads this target across the selected sub-unit at the chosen IB level.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .glassCard()
            .environment(\.calendar, IBLocalClock.calendar)
            .environment(\.timeZone, IBLocalClock.timeZone)
        }
    }

    private var startTimeFormatted: String {
        Self.endTimeFormatter.string(from: scheduledDate)
    }

    private var endTimeFormatted: String {
        let end = IBLocalClock.calendar.date(byAdding: .minute, value: durationMinutes, to: scheduledDate) ?? scheduledDate
        return Self.endTimeFormatter.string(from: end)
    }

    // MARK: - Step 3: Plan
    private var planView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if planMarkdown.isEmpty && !isGeneratingPlan {
                // Generate prompt
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 30))
                        .foregroundStyle(IBColors.accent)
                    Text("Ready to generate your study plan!")
                        .font(.callout)
                    Text("ARIA will create a personalised plan for \(selectedTopicSummary) based on your current mastery and IB exam requirements.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)

                    Button {
                        generatePlan()
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Generate Plan with ARIA")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else if isGeneratingPlan {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("ARIA is creating your study plan…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                // Show plan
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(IBColors.accent)
                        Text("Your Study Plan")
                            .font(.headline)
                    }

                    FormattedMessageContent(text: planMarkdown)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()
                }

                // Chat to refine
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundStyle(IBColors.accent)
                        Text("Refine with ARIA")
                            .font(.headline)
                    }

                    ForEach(Array(chatMessages.enumerated()), id: \.offset) { _, msg in
                        HStack(alignment: .top) {
                            if msg.role == "user" { Spacer() }
                            FormattedMessageContent(text: msg.text)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(msg.role == "user" ? IBColors.accent.opacity(0.1) : Color.secondary.opacity(0.05))
                                )
                                .frame(maxWidth: 400, alignment: msg.role == "user" ? .trailing : .leading)
                            if msg.role == "model" { Spacer() }
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("Ask ARIA to modify the plan…", text: $chatInput)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { sendChatMessage() }

                        Button {
                            sendChatMessage()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.borderless)
                        .disabled(chatInput.isEmpty || isChatting)
                        .help("Send message")
                    }
                }
                .padding(16)
                .glassCard()
            }
        }
    }

    // MARK: - Navigation Bar
    private var navigationBar: some View {
        HStack {
            if step > 0 {
                Button {
                    withAnimation(IBAnimation.smooth) { step -= 1 }
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if step < 3 {
                Button {
                    // "Generate Plan" on the Schedule step kicks off ARIA and
                    // moves to the Plan step, which shows the spinner while the
                    // plan streams in — instead of advancing to an empty plan.
                    if step == 2 { generatePlan() }
                    withAnimation(IBAnimation.smooth) { step += 1 }
                } label: {
                    HStack {
                        Text(step == 2 ? "Generate Plan" : "Next")
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    (step == 0 && selectedSubject == nil) ||
                    (step == 1 && selectedTopics.isEmpty)
                )
            } else {
                Button {
                    saveSession()
                } label: {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("Schedule Session")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(planMarkdown.isEmpty || planGenerationFailed)
            }
        }
    }

    // MARK: - Logic
    private func generatePlan() {
        guard let subject = selectedSubject else { return }
        guard !isGeneratingPlan else { return }
        // A fresh generation invalidates anything still in flight, so a plan
        // streamed for an earlier subject/topic selection is discarded if the
        // user changed scope while it was running.
        let generationID = UUID()
        planGenerationID = generationID
        isGeneratingPlan = true

        Task {
            do {
                let unitPart = selectedUnitList.isEmpty ? "" : "\nUnits: \(selectedUnitList.joined(separator: ", "))"
                let subtopicPart = selectedSubtopicList.isEmpty ? "" : "\nFocus subtopics: \(selectedSubtopicList.joined(separator: ", "))"
                let prompt = """
                Create a detailed session plan for an IB \(subject.level) \(subject.name) student.
                Topics: \(selectedTopicList.joined(separator: ", "))\(unitPart)\(subtopicPart)
                Duration: \(durationMinutes) minutes
                Scheduled: \(scheduledDate.formatted())

                Return only one valid JSON object containing overview, objectives, and tasks.
                Every task must contain: id (UUID), title, minutes, activityType,
                topicName, subtopicName, instructions, successCriterion, and flashcardTarget.

                Requirements:
                - Allocate exactly \(durationMinutes) minutes.
                - Include every selected subunit.
                - Use at least \(durationMinutes <= 30 ? 4 : (durationMinutes <= 60 ? 6 : (durationMinutes <= 90 ? 8 : 10))) tasks.
                - Sequence understanding before testing: orient from a trusted resource, build a mental model, retrieve closed-note, correct with feedback, transfer to a new case, then complete an exit ticket.
                - Include IB command terms and mark-scheme actions where relevant.
                - Make every task executable without a follow-up question.
                """

                let systemPrompt = """
                You are ARIA, an IB study planner. Return only valid JSON matching this shape:
                {"overview":"...","objectives":["..."],"tasks":[{"id":"UUID","title":"...","minutes":10,"activityType":"active-recall","topicName":"...","subtopicName":"...","instructions":"...","successCriterion":"...","flashcardTarget":3}]}
                Build a complete duration-budgeted session, not a short outline.
                """

                let response = try await AIProviderService.generateContent(
                    messages: [GeminiMessage(role: "user", text: prompt)],
                    systemInstruction: systemPrompt
                )

                let decoded = (try? StudyPlanDraft.decode(from: response)) ?? StudyPlanDraft(
                    overview: "Build reliable recall across the selected scope and finish with a clear next review action.",
                    objectives: ["Explain the selected ideas without notes", "Apply them to an IB-style task"],
                    tasks: []
                )
                let draft = decoded.normalized(
                    durationMinutes: durationMinutes,
                    topicNames: selectedTopicList,
                    subtopicNames: selectedSubtopicList,
                    subjectName: subject.name
                )
                let renderedPlan = draft.markdown

                ARIAService.recordStudyPlanDraft(
                    subjectName: subject.name,
                    topicName: selectedTopicList.joined(separator: ", "),
                    subtopicName: selectedSubtopicList.joined(separator: ", "),
                    scheduledDate: scheduledDate,
                    durationMinutes: durationMinutes,
                    planMarkdown: renderedPlan
                )

                await MainActor.run {
                    guard generationID == planGenerationID else { return }
                    planMarkdown = renderedPlan
                    planTasks = draft.tasks
                    planGenerationFailed = false
                    isGeneratingPlan = false
                }
            } catch {
                await MainActor.run {
                    guard generationID == planGenerationID else { return }
                    planMarkdown = "Failed to generate plan: \(error.localizedDescription)\n\nTry again or write your own plan."
                    planGenerationFailed = true
                    isGeneratingPlan = false
                }
            }
        }
    }

    private func sendChatMessage() {
        guard !chatInput.isEmpty, !isChatting else { return }
        let userMsg = chatInput
        chatMessages.append((role: "user", text: userMsg))
        chatInput = ""
        isChatting = true

        Task {
            do {
                let prompt = """
                The current study plan is:
                \(planMarkdown)

                The user says: \(userMsg)

                Update the plan based on the request and return a replacement JSON object
                with overview, objectives, and typed tasks. Keep the total at exactly
                \(durationMinutes) minutes. Preserve these topics: \(selectedTopicList.joined(separator: ", ")).
                Preserve these subunits: \(selectedSubtopicList.joined(separator: ", ")).
                """

                let response = try await AIProviderService.generateContent(
                    messages: [GeminiMessage(role: "user", text: prompt)],
                    systemInstruction: "You are ARIA. Return only a complete valid JSON study plan with overview, objectives, and typed tasks."
                )

                let draft = try StudyPlanDraft.decode(from: response).normalized(
                    durationMinutes: durationMinutes,
                    topicNames: selectedTopicList,
                    subtopicNames: selectedSubtopicList,
                    subjectName: selectedSubject?.name ?? ""
                )
                let renderedPlan = draft.markdown

                ARIAService.recordStudyPlanRevision(
                    subjectName: selectedSubject?.name ?? "Unknown Subject",
                    topicName: selectedTopicList.joined(separator: ", "),
                    subtopicName: selectedSubtopicList.joined(separator: ", "),
                    userRequest: userMsg,
                    updatedPlanMarkdown: renderedPlan,
                    sourceReference: "NewStudySessionView.sendChatMessage"
                )

                await MainActor.run {
                    chatMessages.append((role: "model", text: "Plan updated! ✅"))
                    planMarkdown = renderedPlan
                    planTasks = draft.tasks
                    // A successful refine replaces the failed-draft text with a
                    // real plan, so the schedule button must unlock again.
                    planGenerationFailed = false
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

    private func saveSession() {
        guard let subject = selectedSubject else { return }

        let plan = StudyPlan(
            subjectName: subject.name,
            topicName: selectedTopicList.joined(separator: ", "),
            subtopicName: selectedSubtopicList.joined(separator: ", "),
            planMarkdown: planMarkdown,
            scheduledDate: scheduledDate,
            durationMinutes: durationMinutes,
            reviewScheduleOffsets: [],
            prepareFlashcards: prepareFlashcards,
            planTasks: planTasks,
            flashcardOnly: flashcardOnly,
            flashcardTargetCount: flashcardTargetCount,
            flashcardDifficulty: flashcardDifficulty
        )
        context.insert(plan)

        // Record to ARIA context
        ARIAService.recordStudyPlan(
            subjectName: subject.name,
            topicName: selectedTopicList.joined(separator: ", "),
            subtopicName: selectedSubtopicList.joined(separator: ", "),
            scheduledDate: scheduledDate,
            durationMinutes: durationMinutes,
            planMarkdown: planMarkdown
        )

        do {
            try context.save()
        } catch {
            // A failed save must not silently drop the freshly built plan.
            // Roll back the pending insert so a retry cannot duplicate it.
            saveError = "Could not save your study plan: \(error.localizedDescription)"
            context.rollback()
            return
        }
        IBHaptics.success()
        dismiss()
    }

    private func selectedSubtopics(for topicName: String) -> Set<String> {
        selectedSubtopicsByTopic[topicName] ?? []
    }

    private func invalidatePlanGeneration() {
        planGenerationID = UUID()
        isGeneratingPlan = false
        planGenerationFailed = false
    }

    private func toggleTopic(_ topicName: String) {
        invalidatePlanGeneration()
        if selectedTopics.contains(topicName) {
            selectedTopics.remove(topicName)
            selectedSubtopicsByTopic[topicName] = Set<String>()
        } else {
            selectedTopics.insert(topicName)
        }
    }

    private func toggleSubtopic(topic: String, subtopic: String) {
        invalidatePlanGeneration()
        var subtopics = selectedSubtopics(for: topic)
        if subtopics.contains(subtopic) {
            subtopics.remove(subtopic)
        } else {
            subtopics.insert(subtopic)
        }
        selectedSubtopicsByTopic[topic] = subtopics
    }

    private func unitTopicsSelected(in unit: CurriculumUnit) -> Bool {
        unit.topics.allSatisfy { selectedTopics.contains($0.name) }
    }

    private func toggleUnit(_ unit: CurriculumUnit) {
        invalidatePlanGeneration()
        if unitTopicsSelected(in: unit) {
            for topic in unit.topics {
                selectedTopics.remove(topic.name)
                selectedSubtopicsByTopic[topic.name] = Set<String>()
            }
        } else {
            for topic in unit.topics {
                selectedTopics.insert(topic.name)
            }
        }
    }
}
