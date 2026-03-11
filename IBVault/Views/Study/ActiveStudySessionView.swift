import SwiftUI
import SwiftData

struct ActiveStudySessionView: View {
    let plan: StudyPlan
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @Query private var subjects: [Subject]

    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer?
    @State private var chatMessages: [(role: String, text: String)] = []
    @State private var chatInput = ""
    @State private var isChatting = false
    @State private var showCompletion = false
    @State private var sessionNotes = ""
    @State private var selectedTab: SessionTab = .plan
    @State private var generatedCards: [(front: String, back: String)] = []
    @State private var isGeneratingCards = false
    @State private var showFlashcardPreview = false

    enum SessionTab: String, CaseIterable {
        case plan = "Plan"
        case chat = "ARIA"
        case flashcards = "Flashcards"
        case notes = "Notes"

        var icon: String {
            switch self {
            case .plan: return "doc.text.fill"
            case .chat: return "sparkles"
            case .flashcards: return "rectangle.on.rectangle.angled"
            case .notes: return "note.text"
            }
        }
    }

    var body: some View {
        NavigationStack {
            if showCompletion {
                completionView
            } else {
                VStack(spacing: 0) {
                    // Top bar
                    sessionHeader
                        .padding(16)

                    Divider()

                    // Tab bar
                    sessionTabBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    // Content
                    TabView(selection: $selectedTab) {
                        planPanel.tag(SessionTab.plan)
                        chatPanel.tag(SessionTab.chat)
                        flashcardsPanel.tag(SessionTab.flashcards)
                        notesPanel.tag(SessionTab.notes)
                    }
                    .tabViewStyle(.automatic)

                    Divider()

                    // Bottom bar
                    bottomBar
                        .padding(14)
                        .background(.ultraThinMaterial)
                }
            }
        }
        .frame(minWidth: 780, minHeight: 580)
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
    }

    // MARK: - Header

    private var sessionHeader: some View {
        HStack(spacing: 14) {
            // Subject indicator
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(subjectColor(plan.subjectName).opacity(0.1))
                    .frame(width: 42, height: 42)
                Image(systemName: subjectIcon(plan.subjectName))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(subjectColor(plan.subjectName))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(plan.subjectName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(plan.topicName + (plan.subtopicName.isEmpty ? "" : " → \(plan.subtopicName)"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Timer
            timerView

            // Progress ring
            ProgressRing(
                progress: min(elapsed / Double(plan.durationMinutes * 60), 1.0),
                lineWidth: 4,
                size: 38,
                color: timerColor
            )

            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private var timerView: some View {
        HStack(spacing: 5) {
            Image(systemName: elapsed > Double(plan.durationMinutes * 60) ? "exclamationmark.triangle.fill" : "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(timerColor)
            Text(timeFormatted)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(timerColor)
            Text("/ \(plan.durationMinutes)m")
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
    }

    // MARK: - Tab Bar

    private var sessionTabBar: some View {
        HStack(spacing: 2) {
            ForEach(SessionTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11))
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: .medium))
                        if tab == .flashcards && !generatedCards.isEmpty {
                            Text("\(generatedCards.count)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(IBColors.electricBlue))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(selectedTab == tab ? IBColors.electricBlue.opacity(0.08) : Color.clear)
                    )
                    .foregroundStyle(
                        selectedTab == tab
                            ? AnyShapeStyle(IBColors.electricBlue)
                            : AnyShapeStyle(.secondary)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }

    // MARK: - Plan Panel

    private var planPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(plan.planMarkdown)
                    .font(.system(size: 13, weight: .regular))
                    .textSelection(.enabled)
                    .lineSpacing(3)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
                    )
            }
            .padding(20)
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

                    ForEach(chatMessages.indices, id: \.self) { i in
                        let msg = chatMessages[i]
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

                            Text(msg.text)
                                .font(.system(size: 13))
                                .lineSpacing(2)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(msg.role == "user"
                                              ? IBColors.electricBlue.opacity(0.08)
                                              : Color.secondary.opacity(0.04))
                                )
                                .textSelection(.enabled)

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
                TextField("Ask ARIA about \(plan.topicName)…", text: $chatInput)
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
            }
            .padding(12)
            .background(.ultraThinMaterial)
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
                quickPrompt("Explain \(plan.topicName) simply")
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
                // Generate button
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Flashcards")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("Generate cards from your study plan and topic")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isGeneratingCards {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button {
                            generateFlashcards()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11))
                                Text(generatedCards.isEmpty ? "Generate Cards" : "Generate More")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
                )

                // Cards
                if generatedCards.isEmpty && !isGeneratingCards {
                    VStack(spacing: 10) {
                        Image(systemName: "rectangle.on.rectangle.angled")
                            .font(.system(size: 30, weight: .ultraLight))
                            .foregroundStyle(.tertiary)
                        Text("No flashcards yet")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("ARIA will generate exam‑focused cards\nfrom your current topic.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }

                ForEach(generatedCards.indices, id: \.self) { i in
                    let card = generatedCards[i]
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Card \(i + 1)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.tertiary)
                                .textCase(.uppercase)
                            Spacer()
                            Button {
                                saveCardToSubject(front: card.front, back: card.back)
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 10))
                                    Text("Save")
                                        .font(.system(size: 10, weight: .medium))
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }

                        Text(card.front)
                            .font(.system(size: 13, weight: .medium))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(IBColors.electricBlue.opacity(0.04))
                            )

                        Text(card.back)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.secondary.opacity(0.03))
                            )
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.02), radius: 4, y: 1)
                    )
                }

                // Save all
                if generatedCards.count > 1 {
                    Button {
                        saveAllCards()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Save All \(generatedCards.count) Cards")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
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
                Text("\(generatedCards.count) cards generated")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                completeSession()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                    Text("Complete Session")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
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

            ZStack {
                Circle()
                    .fill(.green.opacity(0.06))
                    .frame(width: 90, height: 90)
                Circle()
                    .fill(.green.opacity(0.1))
                    .frame(width: 65, height: 65)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.green)
            }
            .glow(color: .green, radius: 20)

            Text("Session Complete!")
                .font(.system(size: 22, weight: .bold, design: .rounded))

            // Stats
            HStack(spacing: 0) {
                StatCard(value: "\(Int(elapsed / 60))m", label: "Studied", color: .orange, icon: "clock.fill")
                Divider().frame(height: 44)
                StatCard(value: plan.subjectName, label: "Subject", color: subjectColor(plan.subjectName), icon: "book.fill")
                Divider().frame(height: 44)
                StatCard(value: "\(generatedCards.count)", label: "Cards", color: IBColors.electricBlue, icon: "rectangle.on.rectangle")
                Divider().frame(height: 44)
                StatCard(value: "+\(xpAwarded)xp", label: "Earned", color: .purple, icon: "star.fill")
            }
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
            )
            .frame(maxWidth: 550)

            // Spaced repetition notice
            if !scheduledReviews.isEmpty {
                VStack(spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                            .foregroundStyle(IBColors.electricBlue)
                        Text("Spaced Repetition Reviews Scheduled")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    ForEach(scheduledReviews, id: \.self) { date in
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(IBColors.electricBlue.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(IBColors.electricBlue.opacity(0.1), lineWidth: 0.5)
                        )
                )
            }

            // Rank progress
            if let profile = profiles.first {
                HStack(spacing: 8) {
                    Text(profile.rank.emoji)
                        .font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.rank.rawValue)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        ProgressView(value: profile.progressToNextRank)
                            .tint(IBColors.electricBlue)
                            .frame(width: 120)
                    }
                    if let next = profile.rank.next {
                        Text("→ \(next.emoji) \(next.rawValue)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                )
            }

            Button {
                dismiss()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                    Text("Done")
                }
                .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)

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
    }

    // MARK: - Timer

    private var timeFormatted: String {
        let mins = Int(elapsed) / 60
        let secs = Int(elapsed) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private var timerColor: Color {
        let target = Double(plan.durationMinutes * 60)
        if elapsed > target { return .red }
        if elapsed > target * 0.8 { return .orange }
        return IBColors.electricBlue
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsed += 1
        }
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
                guard let apiKey = KeychainService.loadAPIKey(), !apiKey.isEmpty else { return }

                // Build full ARIA system prompt with context
                let aria = ARIAService()
                let systemPrompt = await aria.buildSystemPrompt(context: context, seedQuery: userMsg)

                // Build conversation history
                var messages: [GeminiMessage] = []

                // Add study plan context as first message
                messages.append(GeminiMessage(role: "user", text: """
                I'm in an active study session for \(plan.subjectName) — \(plan.topicName)\(plan.subtopicName.isEmpty ? "" : " (\(plan.subtopicName))").
                Duration: \(plan.durationMinutes) minutes. Time elapsed: \(Int(elapsed / 60)) minutes.
                
                My study plan:
                \(plan.planMarkdown.prefix(1500))
                \(sessionNotes.isEmpty ? "" : "\nMy notes so far: \(sessionNotes.prefix(500))")
                """))
                messages.append(GeminiMessage(role: "model", text: "Got it! I have full context on your study session. I'm here to help with \(plan.topicName). What would you like to know?"))

                // Add chat history
                for msg in chatMessages {
                    messages.append(GeminiMessage(role: msg.role, text: msg.text))
                }

                let response = try await GeminiService.generateContent(
                    messages: messages,
                    systemInstruction: systemPrompt,
                    apiKey: apiKey
                )

                ARIAService.recordARIAChatExchange(
                    subjectName: plan.subjectName,
                    topicNames: [plan.topicName, plan.subtopicName].filter { !$0.isEmpty },
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
                guard let apiKey = KeychainService.loadAPIKey(), !apiKey.isEmpty else { return }

                let prompt = """
                Generate 8 IB exam-focused flashcards for:
                Subject: \(plan.subjectName)
                Topic: \(plan.topicName)\(plan.subtopicName.isEmpty ? "" : " — \(plan.subtopicName)")
                
                Study plan context:
                \(plan.planMarkdown.prefix(800))

                Format each card EXACTLY as:
                FRONT: [question]
                BACK: [answer]

                Rules:
                - Mix definition, application, and exam-technique cards
                - Use IB command terms (define, explain, evaluate, discuss, analyse)
                - Include mark scheme hints where relevant
                - Make answers concise but complete
                """

                let response = try await GeminiService.generateContent(
                    messages: [GeminiMessage(role: "user", text: prompt)],
                    systemInstruction: "You are ARIA, an IB flashcard generator. Create high-quality flashcards suitable for IB exams. Each card must have FRONT: and BACK: lines.",
                    apiKey: apiKey
                )

                let parsed = parseFlashcards(response)

                ARIAService.recordFlashcardGeneration(
                    subjectName: plan.subjectName,
                    topicName: plan.topicName,
                    subtopicName: plan.subtopicName,
                    generatedCards: parsed,
                    sourceReference: "ActiveStudySessionView.generateFlashcards"
                )

                await MainActor.run {
                    generatedCards.append(contentsOf: parsed)
                    isGeneratingCards = false
                }
            } catch {
                await MainActor.run {
                    isGeneratingCards = false
                }
            }
        }
    }

    private func parseFlashcards(_ text: String) -> [(front: String, back: String)] {
        var cards: [(front: String, back: String)] = []
        let lines = text.components(separatedBy: .newlines)
        var currentFront = ""
        var currentBack = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("FRONT:") {
                if !currentFront.isEmpty && !currentBack.isEmpty {
                    cards.append((front: currentFront, back: currentBack))
                }
                currentFront = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                currentBack = ""
            } else if trimmed.hasPrefix("BACK:") {
                currentBack = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if !trimmed.isEmpty && !currentBack.isEmpty {
                currentBack += " " + trimmed
            }
        }
        if !currentFront.isEmpty && !currentBack.isEmpty {
            cards.append((front: currentFront, back: currentBack))
        }
        return cards
    }

    private func saveCardToSubject(front: String, back: String) {
        guard let subject = subjects.first(where: { $0.name == plan.subjectName }) else { return }
        let card = StudyCard(
            topicName: plan.topicName,
            subtopic: plan.subtopicName.isEmpty ? plan.topicName : plan.subtopicName,
            front: front,
            back: back,
            subject: subject
        )
        subject.cards.append(card)
        try? context.save()
        IBHaptics.success()
    }

    private func saveAllCards() {
        guard let subject = subjects.first(where: { $0.name == plan.subjectName }) else { return }
        for card in generatedCards {
            let studyCard = StudyCard(
                topicName: plan.topicName,
                subtopic: plan.subtopicName.isEmpty ? plan.topicName : plan.subtopicName,
                front: card.front,
                back: card.back,
                subject: subject
            )
            subject.cards.append(studyCard)
        }
        try? context.save()
        IBHaptics.success()
    }

    // MARK: - Spaced Repetition Scheduling

    private var scheduledReviews: [Date] {
        // SM-2 inspired intervals: 1 day, 3 days, 7 days, 14 days
        let intervals = [1, 3, 7, 14]
        let cal = Calendar.current
        let endDate = Date()

        return intervals.compactMap { days in
            guard let date = cal.date(byAdding: .day, value: days, to: endDate) else { return nil }
            // Schedule at 4pm (after school)
            return cal.date(bySettingHour: 16, minute: 0, second: 0, of: date)
        }
    }

    private func scheduleSpacedReviews() {
        let cal = Calendar.current
        let intervals = [1, 3, 7, 14]

        for days in intervals {
            guard let date = cal.date(byAdding: .day, value: days, to: Date()),
                  let scheduledAt = cal.date(bySettingHour: 16, minute: 0, second: 0, of: date)
            else { continue }

            let review = StudyPlan(
                subjectName: plan.subjectName,
                topicName: plan.topicName,
                subtopicName: plan.subtopicName,
                planMarkdown: "📝 **Spaced Repetition Review**\n\nRevisit \(plan.topicName) from your session on \(Date().formatted(date: .abbreviated, time: .omitted)).\n\n1. **Quick Recall** (10 min): Try to recall key concepts without notes\n2. **Review Cards** (15 min): Go through your flashcards\n3. **Practice** (10 min): Attempt one exam-style question\n4. **Self-Assessment**: Rate your confidence 1-5\n\nInterval: Day \(days) review • \(days <= 3 ? "Critical retention window" : "Long-term consolidation")",
                scheduledDate: scheduledAt,
                durationMinutes: 30
            )
            context.insert(review)
        }
    }

    // MARK: - Complete

    private var xpAwarded: Int {
        let baseXP = max(10, Int(elapsed / 60) * 2)
        let cardBonus = generatedCards.count * 3
        let noteBonus = sessionNotes.count > 50 ? 10 : 0
        return baseXP + cardBonus + noteBonus
    }

    private func completeSession() {
        plan.isCompleted = true
        plan.notes = sessionNotes

        // Log StudySession
        let topics = [plan.topicName, plan.subtopicName].filter { !$0.isEmpty }
        let session = StudySession(
            subjectName: plan.subjectName,
            topicsCovered: topics.joined(separator: ", "),
            startDate: Date().addingTimeInterval(-elapsed),
            endDate: Date(),
            cardsReviewed: generatedCards.count,
            correctCount: generatedCards.count,
            xpEarned: xpAwarded
        )
        context.insert(session)

        // Award XP
        if let profile = profiles.first {
            profile.addXP(xpAwarded)
            profile.checkAndUpdateStreak()
        }

        // Schedule spaced repetition reviews on calendar
        scheduleSpacedReviews()

        // Record to ARIA context
        ARIAService.recordPlannedStudySession(
            subjectName: plan.subjectName,
            topics: topics,
            planMarkdown: plan.planMarkdown,
            notes: sessionNotes,
            xpEarned: xpAwarded,
            durationMinutes: elapsed / 60
        )

        try? context.save()
        withAnimation(IBAnimation.smooth) { showCompletion = true }
        IBHaptics.success()
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
        default: return "book.fill"
        }
    }
}
