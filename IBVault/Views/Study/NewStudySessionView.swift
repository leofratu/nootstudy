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
    @State private var scheduledDate = Date()
    @State private var durationMinutes = 60
    @State private var revisitCount = 3
    @State private var planMarkdown = ""
    @State private var isGeneratingPlan = false
    @State private var chatMessages: [(role: String, text: String)] = []
    @State private var chatInput = ""
    @State private var isChatting = false

    private let durations = [30, 45, 60, 90, 120]
    private let revisitOptions = [0, 1, 2, 3, 4, 5]
    private let defaultReviewOffsets = [1, 3, 7, 14, 21]

    private var curriculum: [CurriculumUnit] {
        guard let subject = selectedSubject else { return [] }
        return SyllabusSeeder.curriculum(for: subject.name)
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

    private var selectedTopicSummary: String {
        if selectedTopicList.isEmpty {
            return "No topics selected"
        }
        if selectedTopicList.count == 1 {
            return selectedTopicList[0]
        }
        return "\(selectedTopicList.count) topics selected"
    }

    // Default schedule: today or tomorrow at 4pm
    private var defaultSchedule: Date {
        let cal = Calendar.current
        let now = Date()
        let hour = cal.component(.hour, from: now)
        var target = cal.startOfDay(for: now)
        if hour >= 16 {
            target = cal.date(byAdding: .day, value: 1, to: target)!
        }
        return cal.date(bySettingHour: 16, minute: 0, second: 0, of: target)!
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
                    .background(.ultraThinMaterial)
            }
            .background(.background)
            .navigationTitle("New Study Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                scheduledDate = defaultSchedule
            }
        }
        .frame(minWidth: 600, minHeight: 550)
    }

    // MARK: - Step Indicator
    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { i in
                HStack(spacing: 6) {
                    Circle()
                        .fill(i <= step ? IBColors.electricBlue : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Text(["Subject", "Topic", "Schedule", "Plan"][i])
                        .font(.caption)
                        .foregroundStyle(i <= step ? .primary : .secondary)
                }
                if i < 3 {
                    Rectangle()
                        .fill(i < step ? IBColors.electricBlue : Color.secondary.opacity(0.2))
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
                        chatMessages.removeAll()
                        IBHaptics.light()
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color(hex: subject.accentColorHex))
                                .frame(width: 10, height: 10)
                            Text(subject.name)
                                .font(.callout.weight(.medium))
                            Spacer()
                            Text(subject.level)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedSubject?.id == subject.id ? Color(hex: subject.accentColorHex).opacity(0.08) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(selectedSubject?.id == subject.id ? Color(hex: subject.accentColorHex) : Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
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
                    .foregroundStyle(IBColors.electricBlue)
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
                                            ? AnyShapeStyle(IBColors.electricBlue)
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
                                            .foregroundStyle(IBColors.electricBlue)
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
                                                        ? AnyShapeStyle(IBColors.electricBlue)
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
            Text("School finishes at 4pm — we'll default to after school.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                DatePicker("Date & Time", selection: $scheduledDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)

                Divider()

                Picker("Duration:", selection: $durationMinutes) {
                    ForEach(durations, id: \.self) { d in
                        Text("\(d) minutes").tag(d)
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Session ends at \(endTimeFormatted)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Picker("Auto revisit count", selection: $revisitCount) {
                        ForEach(revisitOptions, id: \.self) { count in
                            Text(count == 0 ? "No auto reviews" : "\(count) review\(count == 1 ? "" : "s")")
                                .tag(count)
                        }
                    }

                    if selectedReviewOffsets.isEmpty {
                        Text("No follow-up review sessions will be created automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Auto reviews: " + selectedReviewOffsets.map { "Day \($0)" }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .glassCard()
        }
    }

    private var endTimeFormatted: String {
        let end = Calendar.current.date(byAdding: .minute, value: durationMinutes, to: scheduledDate) ?? scheduledDate
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: end)
    }

    private var selectedReviewOffsets: [Int] {
        Array(defaultReviewOffsets.prefix(revisitCount))
    }

    // MARK: - Step 3: Plan
    private var planView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if planMarkdown.isEmpty && !isGeneratingPlan {
                // Generate prompt
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 30))
                        .foregroundStyle(IBColors.electricBlue)
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
                            .foregroundStyle(IBColors.electricBlue)
                        Text("Your Study Plan")
                            .font(.headline)
                    }

                    FormattedMessageContent(text: planMarkdown)
                        .textSelection(.enabled)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()
                }

                // Chat to refine
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundStyle(IBColors.electricBlue)
                        Text("Refine with ARIA")
                            .font(.headline)
                    }

                    ForEach(Array(chatMessages.enumerated()), id: \.offset) { _, msg in
                        HStack(alignment: .top) {
                            if msg.role == "user" { Spacer() }
                            FormattedMessageContent(text: msg.text)
                                .textSelection(.enabled)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(msg.role == "user" ? IBColors.electricBlue.opacity(0.1) : Color.secondary.opacity(0.05))
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
                    withAnimation(.easeInOut(duration: 0.2)) { step -= 1 }
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
                    withAnimation(.easeInOut(duration: 0.2)) { step += 1 }
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
                .disabled(planMarkdown.isEmpty)
            }
        }
    }

    // MARK: - Logic
    private func generatePlan() {
        guard let subject = selectedSubject else { return }
        isGeneratingPlan = true

        Task {
            do {
                guard let apiKey = KeychainService.loadAPIKey(), !apiKey.isEmpty else {
                    throw GeminiError.noAPIKey
                }

                let unitPart = selectedUnitList.isEmpty ? "" : "\nUnits: \(selectedUnitList.joined(separator: ", "))"
                let subtopicPart = selectedSubtopicList.isEmpty ? "" : "\nFocus subtopics: \(selectedSubtopicList.joined(separator: ", "))"
                let prompt = """
                Create a structured study plan for an IB \(subject.level) \(subject.name) student.
                Topics: \(selectedTopicList.joined(separator: ", "))\(unitPart)\(subtopicPart)
                Duration: \(durationMinutes) minutes
                Scheduled: \(scheduledDate.formatted())

                Create a practical, time-blocked study plan with:
                1. **Warm-up** (5 min): Quick recall of key concepts
                2. **Active Learning** (main block): Specific activities with time allocations
                3. **Practice** (15-20 min): Exam-style questions or applications
                4. **Review** (5 min): Summary and spaced repetition card review
                5. **Key objectives**: What the student should be able to do after this session

                Make it IB-exam focused. Include specific concepts to cover, practice question types, and mark scheme hints.
                Keep it concise and actionable — no fluff.
                """

                let systemPrompt = """
                You are ARIA, an IB study planner. Generate a structured, time-blocked study plan. Be specific about what to study and how. Reference IB exam requirements and mark schemes. Keep it practical and concise.
                """

                let response = try await GeminiService.generateContent(
                    messages: [GeminiMessage(role: "user", text: prompt)],
                    systemInstruction: systemPrompt,
                    apiKey: apiKey
                )

                ARIAService.recordStudyPlanDraft(
                    subjectName: subject.name,
                    topicName: selectedTopicList.joined(separator: ", "),
                    subtopicName: selectedSubtopicList.joined(separator: ", "),
                    scheduledDate: scheduledDate,
                    durationMinutes: durationMinutes,
                    planMarkdown: response
                )

                await MainActor.run {
                    planMarkdown = response
                    isGeneratingPlan = false
                }
            } catch {
                await MainActor.run {
                    planMarkdown = "Failed to generate plan: \(error.localizedDescription)\n\nTry again or write your own plan."
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
                guard let apiKey = KeychainService.loadAPIKey(), !apiKey.isEmpty else {
                    throw GeminiError.noAPIKey
                }

                let prompt = """
                The current study plan is:
                \(planMarkdown)

                The user says: \(userMsg)

                Update the study plan based on the user's request. Return the FULL updated plan.
                """

                let response = try await GeminiService.generateContent(
                    messages: [GeminiMessage(role: "user", text: prompt)],
                    systemInstruction: "You are ARIA. Update the study plan based on user feedback. Return the complete updated plan. Be concise.",
                    apiKey: apiKey
                )

                ARIAService.recordStudyPlanRevision(
                    subjectName: selectedSubject?.name ?? "Unknown Subject",
                    topicName: selectedTopicList.joined(separator: ", "),
                    subtopicName: selectedSubtopicList.joined(separator: ", "),
                    userRequest: userMsg,
                    updatedPlanMarkdown: response,
                    sourceReference: "NewStudySessionView.sendChatMessage"
                )

                await MainActor.run {
                    chatMessages.append((role: "model", text: "Plan updated! ✅"))
                    planMarkdown = response
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
            reviewScheduleOffsets: selectedReviewOffsets
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

        try? context.save()
        IBHaptics.success()
        dismiss()
    }

    private func selectedSubtopics(for topicName: String) -> Set<String> {
        selectedSubtopicsByTopic[topicName] ?? []
    }

    private func toggleTopic(_ topicName: String) {
        if selectedTopics.contains(topicName) {
            selectedTopics.remove(topicName)
            selectedSubtopicsByTopic[topicName] = Set<String>()
        } else {
            selectedTopics.insert(topicName)
        }
    }

    private func toggleSubtopic(topic: String, subtopic: String) {
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
