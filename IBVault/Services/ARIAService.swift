import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
class ARIAService {
    var isLoading = false
    var currentStreamText = ""
    var isOnline = true
    var suggestedPrompts: [String] = []

    private let tokenThreshold = 12000
    private let maxMemoryItems = 8
    private let maxContextSubjects = 4
    private let maxHistoryMessages = 24
    private let minMessagesBeforeCompaction = 16
    private let minMessagesToKeepAfterCompaction = 8

    private struct PlannedAppAction: Codable {
        let type: String
        let subjectName: String?
        let topics: [String]?
        let subtopics: [String]?
        let scheduledAt: String?
        let durationMinutes: Int?
        let cardCount: Int?
        let masteryLevel: String?
        let dailyGoal: Int?
        let targetIBScore: Int?
        let minutesStudied: Double?
        let xpEarned: Int?
        let notes: String?
        let memoryCategory: String?
        let searchText: String?
        let frontText: String?
        let backText: String?
    }

    private struct ActionExecutionSummary {
        let completed: [String]
        let failed: [String]

        var isEmpty: Bool {
            completed.isEmpty && failed.isEmpty
        }

        var promptContext: String {
            guard !isEmpty else { return "" }
            var lines = ["ARIA app actions executed in this turn:"]
            if !completed.isEmpty {
                lines.append("Completed:")
                lines.append(contentsOf: completed.map { "- \($0)" })
            }
            if !failed.isEmpty {
                lines.append("Failed:")
                lines.append(contentsOf: failed.map { "- \($0)" })
            }
            return lines.joined(separator: "\n")
        }
    }

    init() {
        suggestedPrompts = [
            "What should I study today?",
            "Give me a study plan",
            "Quiz me on my weakest topic",
            "How can I improve my grades?",
            "Create a study session for Biology tomorrow at 6",
            "Generate flashcards for my weakest Economics topic",
            "Clean up weak flashcards and assign me a session from my weakest topic"
        ]
    }

    @MainActor
    func updateSuggestedPrompts(context: ModelContext) {
        var prompts: [String] = []
        
        // Get user profile
        if let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first {
            let streak = profile.currentStreak
            let target = profile.targetIBScore
            
            if streak == 0 {
                prompts.append("Let's get back on track! What should I study today?")
            } else if streak > 0 {
                prompts.append("Keep my streak going! What's due today?")
            }
            
            prompts.append("I want to get to \(target)/45 - what should I focus on?")
        }
        
        // Get subjects
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        
        if !subjects.isEmpty {
            // Find weakest subjects
            let weakSubjects = subjects
                .map { ($0, ProficiencyTracker.masteryPercentage(for: $0)) }
                .sorted { $0.1 < $1.1 }
                .prefix(2)
            
            for (subject, mastery) in weakSubjects {
                let masteryPercent = Int(mastery * 100)
                prompts.append("Help me improve \(subject.name) (\(masteryPercent)% mastery)")
            }
            
            // Get subjects with due cards
            let now = Date()
            let subjectsWithDue = subjects.filter { subject in
                subject.cards.contains { $0.nextReviewDate <= now }
            }
            
            if let randomSubject = subjectsWithDue.randomElement() {
                let dueCount = randomSubject.cards.filter { $0.nextReviewDate <= now }.count
                prompts.append("Review \(dueCount) cards from \(randomSubject.name)")
            }
        }
        
        // Always include general prompts
        prompts.append(contentsOf: [
            "Make me a weekly study plan",
            "What's my weakest topic?",
            "Quiz me!"
        ])
        
        // Limit and deduplicate
        suggestedPrompts = Array(Set(prompts)).prefix(4).map { $0 }
    }

    private static let stopWords: Set<String> = [
        "about", "after", "again", "also", "because", "could", "from", "have", "into", "just",
        "like", "make", "need", "please", "should", "some", "that", "them", "they", "this",
        "today", "very", "want", "what", "when", "with", "would", "your"
    ]

    private enum QueryIntent {
        case studyPlan
        case performanceReview
        case flashcards
        case quiz
        case explanation
        case general
    }

    private struct QueryProfile {
        let rawQuery: String
        let normalizedQuery: String
        let keywords: Set<String>
        let intent: QueryIntent

        var preferredActionSpecCount: Int {
            switch intent {
            case .studyPlan, .performanceReview:
                return 4
            case .flashcards, .quiz, .explanation, .general:
                return 3
            }
        }

        var needsMaterialsContext: Bool {
            guard !normalizedQuery.isEmpty else { return false }
            return intent == .studyPlan ||
                normalizedQuery.contains("material") ||
                normalizedQuery.contains("resource") ||
                normalizedQuery.contains("guide") ||
                normalizedQuery.contains("paper") ||
                normalizedQuery.contains("formula") ||
                normalizedQuery.contains("report")
        }

        var historyCharacterBudget: Int {
            switch intent {
            case .studyPlan, .performanceReview:
                return 8000
            case .flashcards, .quiz:
                return 6000
            case .explanation, .general:
                return 7000
            }
        }

        var preferredSubjectCount: Int {
            switch intent {
            case .studyPlan, .performanceReview:
                return 3
            case .flashcards, .quiz, .explanation, .general:
                return 2
            }
        }
    }

    private struct LoggingContext {
        let subjectName: String
        let topicNames: [String]
    }

    // MARK: - Chat

    @MainActor
    func sendMessage(
        _ userMessage: String,
        context: ModelContext,
        session: ARIAChatSession,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard let apiKey = KeychainService.loadAPIKey(), !apiKey.isEmpty else {
            onError(GeminiError.noAPIKey)
            return
        }

        isLoading = true
        currentStreamText = ""

        // Save user message
        let userChat = ChatMessage(role: "user", content: userMessage, sessionID: session.id)
        updateSession(session, withUserMessage: userMessage)
        context.insert(userChat)
        try? context.save()

        Task {
            do {
                let queryProfile = analyzeQuery(userMessage)
                let loggingContext = inferredLoggingContext(context: context, queryProfile: queryProfile)
                let actionSummary = try await self.planAndExecuteAppActions(
                    for: userMessage,
                    context: context,
                    queryProfile: queryProfile
                )

                // Build context
                var systemPrompt = await buildSystemPrompt(context: context, queryProfile: queryProfile)
                if !actionSummary.isEmpty {
                    systemPrompt += "\n\n\(actionSummary.promptContext)\nReference these concrete changes in your reply briefly before giving any next-step guidance."
                }
                let messages = await buildConversationHistory(context: context, queryProfile: queryProfile, sessionID: session.id)

                var fullResponse = ""

                let stream = GeminiService.streamContent(
                    messages: messages,
                    systemInstruction: systemPrompt,
                    apiKey: apiKey
                )

                for try await token in stream {
                    fullResponse = Self.appendStreamChunk(token, to: fullResponse)
                    await MainActor.run {
                        self.currentStreamText = fullResponse
                        onToken(fullResponse)
                    }
                }

                let finalizedResponse = Self.finalizeAssistantResponse(fullResponse)

                // Save assistant response
                await MainActor.run {
                    let modelChat = ChatMessage(role: "model", content: finalizedResponse, sessionID: session.id)
                    context.insert(modelChat)
                    self.updateSession(session, withAssistantReply: finalizedResponse)

                    // Auto-update rank from grades after ARIA response
                    self.autoUpdateRank(context: context)

                    try? context.save()

                    self.isLoading = false
                    onComplete(finalizedResponse)
                }

                Self.recordARIAChatExchange(
                    subjectName: loggingContext.subjectName,
                    topicNames: loggingContext.topicNames,
                    userMessage: userMessage,
                    assistantReply: finalizedResponse,
                    sourceReference: "ARIAService.sendMessage"
                )

                // Check if compaction needed
                await checkAndCompact(context: context, apiKey: apiKey, sessionID: session.id)

            } catch {
                await MainActor.run {
                    self.isLoading = false
                    onError(error)
                }
            }
        }
    }

    @MainActor
    private func planAndExecuteAppActions(
        for userMessage: String,
        context: ModelContext,
        queryProfile: QueryProfile
    ) async throws -> ActionExecutionSummary {
        guard shouldAttemptAppActions(for: userMessage, queryProfile: queryProfile) else {
            return ActionExecutionSummary(completed: [], failed: [])
        }

        guard let apiKey = KeychainService.loadAPIKey(), !apiKey.isEmpty else {
            return ActionExecutionSummary(completed: [], failed: ["ARIA could not execute app actions because the API key is missing."])
        }

        let planningPrompt = buildActionPlanningPrompt(userMessage: userMessage, context: context)
        let response = try await GeminiService.generateContent(
            messages: [GeminiMessage(role: "user", text: planningPrompt)],
            systemInstruction: """
            You convert user requests into safe app actions for an IB study app.
            Return ONLY raw JSON as an array.
            Use [] when the user is not explicitly asking for the app to change data.
            Supported action types:
            - create_study_session
            - assign_weakest_study_session
            - create_review_session
            - reschedule_study_session
            - complete_study_session
            - cancel_study_session
            - generate_flashcards
            - edit_flashcard
            - delete_flashcards
            - update_progress
            - update_profile
            - save_memory
            Rules:
            - Only create actions for explicit edit/create/assign/generate/set/update requests.
            - Prefer concrete subject names that exist in the provided app state.
            - Use ISO-8601 timestamps for scheduledAt.
            - Keep topics/subtopics arrays empty rather than inventing values.
            - Use frontText/backText when editing flashcards.
            - Use searchText only when the user gives identifying wording for a card or asks to clean up/delete cards.
            """,
            apiKey: apiKey
        )

        let actions = parsePlannedAppActions(from: response)
        guard !actions.isEmpty else {
            return ActionExecutionSummary(completed: [], failed: [])
        }

        var completed: [String] = []
        var failed: [String] = []

        for action in actions.prefix(4) {
            do {
                if let summary = try await execute(action: action, context: context) {
                    completed.append(summary)
                }
            } catch {
                failed.append(error.localizedDescription)
            }
        }

        if !completed.isEmpty || !failed.isEmpty {
            try? context.save()
        }

        return ActionExecutionSummary(completed: completed, failed: failed)
    }

    private func shouldAttemptAppActions(for userMessage: String, queryProfile: QueryProfile) -> Bool {
        let normalized = userMessage.lowercased()
        if containsAny(normalized, phrases: [
            "create", "schedule", "assign", "set up", "set", "update", "edit",
            "change", "move", "reschedule", "generate", "make", "mark", "log"
        ]) {
            return true
        }

        switch queryProfile.intent {
        case .studyPlan, .flashcards:
            return containsAny(normalized, phrases: ["for me", "go ahead", "do it", "make it", "generate them"])
        default:
            return false
        }
    }

    @MainActor
    private func buildActionPlanningPrompt(userMessage: String, context: ModelContext) -> String {
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        let plans = (try? context.fetch(FetchDescriptor<StudyPlan>())) ?? []
        let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first

        let subjectLines = subjects.map { subject in
            let topics = Array(Set(subject.cards.map(\.topicName))).sorted().prefix(10).joined(separator: ", ")
            return "- \(subject.name) \(subject.level) | topics: \(topics)"
        }

        let upcomingPlans = plans
            .filter { !$0.isCompleted }
            .sorted { $0.scheduledDate < $1.scheduledDate }
            .prefix(8)
            .map { "- \( $0.subjectName) | \($0.selectionSummary) | \($0.scheduledDate.formatted(date: .abbreviated, time: .shortened))" }

        var lines = [
            "User request:",
            userMessage,
            "",
            "Available subjects:",
            subjectLines.joined(separator: "\n"),
            "",
            "Upcoming study plans:",
            upcomingPlans.isEmpty ? "- none" : upcomingPlans.joined(separator: "\n")
        ]

        if let profile {
            lines.append("")
            lines.append("User profile:")
            lines.append("- dailyGoal: \(profile.dailyGoal)")
            lines.append("- targetIBScore: \(profile.targetIBScore)")
        }

        lines.append("")
        lines.append("Return JSON array with fields: type, subjectName, topics, subtopics, scheduledAt, durationMinutes, cardCount, masteryLevel, dailyGoal, targetIBScore, minutesStudied, xpEarned, notes, memoryCategory, searchText, frontText, backText.")
        return lines.joined(separator: "\n")
    }

    private func parsePlannedAppActions(from response: String) -> [PlannedAppAction] {
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let start = cleaned.firstIndex(of: "["),
              let end = cleaned.lastIndex(of: "]") else {
            return []
        }

        let json = String(cleaned[start...end])
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([PlannedAppAction].self, from: data)) ?? []
    }

    @MainActor
    private func execute(action: PlannedAppAction, context: ModelContext) async throws -> String? {
        switch action.type {
        case "create_study_session":
            return try executeCreateStudySession(action: action, context: context)
        case "assign_weakest_study_session":
            return try executeAssignWeakestStudySession(action: action, context: context)
        case "create_review_session":
            return try executeCreateReviewSession(action: action, context: context)
        case "reschedule_study_session":
            return try executeRescheduleStudySession(action: action, context: context)
        case "complete_study_session":
            return try executeCompleteStudySession(action: action, context: context)
        case "cancel_study_session":
            return try executeCancelStudySession(action: action, context: context)
        case "generate_flashcards":
            return try await executeGenerateFlashcards(action: action, context: context)
        case "edit_flashcard":
            return try executeEditFlashcard(action: action, context: context)
        case "delete_flashcards":
            return try executeDeleteFlashcards(action: action, context: context)
        case "update_progress":
            return try executeUpdateProgress(action: action, context: context)
        case "update_profile":
            return try executeUpdateProfile(action: action, context: context)
        case "save_memory":
            return try executeSaveMemory(action: action, context: context)
        default:
            return nil
        }
    }

    @MainActor
    private func executeCreateStudySession(action: PlannedAppAction, context: ModelContext) throws -> String {
        guard let subject = resolveSubject(named: action.subjectName, context: context) else {
            throw NSError(domain: "ARIAService", code: 1, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find the subject to create that study session."])
        }

        let topics = sanitizedTopics(action.topics, subjectName: subject.name)
        guard !topics.isEmpty else {
            throw NSError(domain: "ARIAService", code: 2, userInfo: [NSLocalizedDescriptionKey: "ARIA needs at least one valid topic to create a study session."])
        }

        let scheduledDate = parseScheduledDate(action.scheduledAt) ?? defaultScheduledDate()
        let duration = min(max(action.durationMinutes ?? 60, 15), 180)
        let subtopics = sanitizedSubtopics(action.subtopics, subjectName: subject.name, topics: topics)

        let plan = StudyPlan(
            subjectName: subject.name,
            topicName: topics.joined(separator: ", "),
            subtopicName: subtopics.joined(separator: ", "),
            planMarkdown: action.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            scheduledDate: scheduledDate,
            durationMinutes: duration
        )
        context.insert(plan)

        ARIAService.recordStudyPlan(
            subjectName: subject.name,
            topicName: plan.topicName,
            subtopicName: plan.subtopicName,
            scheduledDate: scheduledDate,
            durationMinutes: duration,
            planMarkdown: plan.planMarkdown
        )

        return "Created a \(duration)-minute study session for \(subject.name) on \(plan.selectionSummary) at \(scheduledDate.formatted(date: .abbreviated, time: .shortened))."
    }

    @MainActor
    private func executeAssignWeakestStudySession(action: PlannedAppAction, context: ModelContext) throws -> String {
        guard let subject = resolveSubject(named: action.subjectName, context: context) else {
            throw NSError(domain: "ARIAService", code: 15, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find the subject to assign that study session."])
        }

        let topics = Array(uniqueWeakTopicNames(for: subject).prefix(2))
        guard !topics.isEmpty else {
            throw NSError(domain: "ARIAService", code: 16, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find a weak topic to build that study session around."])
        }

        let scheduledDate = parseScheduledDate(action.scheduledAt) ?? defaultScheduledDate()
        let duration = min(max(action.durationMinutes ?? 50, 15), 180)
        let subtopics = sanitizedSubtopics(action.subtopics, subjectName: subject.name, topics: topics)
        let defaultNotes = """
        ### ARIA focus session

        - Start with the weakest concept first
        - Review mark-scheme language for the selected topic
        - Finish with one retrieval round and one exam-style application
        """

        let plan = StudyPlan(
            subjectName: subject.name,
            topicName: topics.joined(separator: ", "),
            subtopicName: subtopics.joined(separator: ", "),
            planMarkdown: action.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? defaultNotes,
            scheduledDate: scheduledDate,
            durationMinutes: duration
        )
        context.insert(plan)

        ARIAService.recordStudyPlan(
            subjectName: subject.name,
            topicName: plan.topicName,
            subtopicName: plan.subtopicName,
            scheduledDate: scheduledDate,
            durationMinutes: duration,
            planMarkdown: plan.planMarkdown
        )

        return "Assigned a \(duration)-minute weakest-topic study session for \(subject.name) on \(plan.selectionSummary) at \(scheduledDate.formatted(date: .abbreviated, time: .shortened))."
    }

    @MainActor
    private func executeCreateReviewSession(action: PlannedAppAction, context: ModelContext) throws -> String {
        guard let subject = resolveSubject(named: action.subjectName, context: context) else {
            throw NSError(domain: "ARIAService", code: 12, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find the subject to assign that review session."])
        }

        let requestedTopics = sanitizedTopics(action.topics, subjectName: subject.name)
        let topics = requestedTopics.isEmpty
            ? Array(uniqueWeakTopicNames(for: subject).prefix(2))
            : requestedTopics
        guard !topics.isEmpty else {
            throw NSError(domain: "ARIAService", code: 13, userInfo: [NSLocalizedDescriptionKey: "ARIA could not determine which topics to review."])
        }

        let subtopics = sanitizedSubtopics(action.subtopics, subjectName: subject.name, topics: topics)
        let scheduledDate = parseScheduledDate(action.scheduledAt) ?? defaultScheduledDate()
        let duration = min(max(action.durationMinutes ?? 30, 15), 90)

        let plan = StudyPlan(
            subjectName: subject.name,
            topicName: topics.joined(separator: ", "),
            subtopicName: subtopics.joined(separator: ", "),
            planMarkdown: action.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "📝 **Review Session**\n\n1. Work through due cards\n2. Revisit weak explanations\n3. Finish with one exam-style question",
            scheduledDate: scheduledDate,
            durationMinutes: duration,
            kind: .followUpReview,
            reviewIntervalDays: nil
        )
        context.insert(plan)

        return "Assigned a \(duration)-minute review session for \(subject.name) on \(plan.selectionSummary) at \(scheduledDate.formatted(date: .abbreviated, time: .shortened))."
    }

    @MainActor
    private func executeRescheduleStudySession(action: PlannedAppAction, context: ModelContext) throws -> String {
        let subjectName = action.subjectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let targetTopics = action.topics ?? []
        let plans = (try? context.fetch(FetchDescriptor<StudyPlan>())) ?? []
        guard let plan = plans
            .filter({ !$0.isCompleted && (subjectName.isEmpty || $0.subjectName.caseInsensitiveCompare(subjectName) == .orderedSame) })
            .sorted(by: { $0.scheduledDate < $1.scheduledDate })
            .first(where: { plan in
                targetTopics.isEmpty || targetTopics.allSatisfy { plan.selectedTopicNames.contains($0) || plan.topicName.caseInsensitiveCompare($0) == .orderedSame }
            }) else {
            throw NSError(domain: "ARIAService", code: 3, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find a matching study session to reschedule."])
        }

        let newDate = parseScheduledDate(action.scheduledAt) ?? defaultScheduledDate()
        plan.scheduledDate = newDate
        plan.scheduledEndDate = Calendar.current.date(byAdding: .minute, value: action.durationMinutes ?? plan.durationMinutes, to: newDate) ?? newDate
        if let duration = action.durationMinutes {
            plan.durationMinutes = min(max(duration, 15), 180)
        }

        return "Rescheduled \(plan.subjectName) \(plan.selectionSummary) to \(newDate.formatted(date: .abbreviated, time: .shortened))."
    }

    @MainActor
    private func executeCompleteStudySession(action: PlannedAppAction, context: ModelContext) throws -> String {
        guard let plan = findMatchingPlan(for: action, context: context) else {
            throw NSError(domain: "ARIAService", code: 17, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find a matching study session to mark complete."])
        }

        plan.isCompleted = true
        return "Marked the \(plan.subjectName) session on \(plan.selectionSummary) as completed."
    }

    @MainActor
    private func executeCancelStudySession(action: PlannedAppAction, context: ModelContext) throws -> String {
        guard let plan = findMatchingPlan(for: action, context: context) else {
            throw NSError(domain: "ARIAService", code: 18, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find a matching study session to cancel."])
        }

        let description = "\(plan.subjectName) \(plan.selectionSummary)"
        context.delete(plan)
        return "Cancelled the \(description) session."
    }

    @MainActor
    private func executeGenerateFlashcards(action: PlannedAppAction, context: ModelContext) async throws -> String {
        guard let subject = resolveSubject(named: action.subjectName, context: context) else {
            throw NSError(domain: "ARIAService", code: 4, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find the subject for flashcard generation."])
        }

        let requestedTopics = sanitizedTopics(action.topics, subjectName: subject.name)
        let topics = requestedTopics.isEmpty
            ? Array(uniqueWeakTopicNames(for: subject).prefix(1))
            : requestedTopics
        guard !topics.isEmpty else {
            throw NSError(domain: "ARIAService", code: 11, userInfo: [NSLocalizedDescriptionKey: "ARIA could not determine which topic to generate flashcards for."])
        }
        let count = min(max(action.cardCount ?? 10, 1), 40)
        var generatedTotal = 0

        for topic in topics {
            let validSubtopics = sanitizedSubtopics(action.subtopics, subjectName: subject.name, topics: [topic])
            let cards = try await CardGeneratorService.generateCards(
                subject: subject,
                topicName: topic,
                subtopic: validSubtopics.joined(separator: ", "),
                count: count,
                context: context
            )

            for card in cards {
                context.insert(card)
                subject.cards.append(card)
            }
            generatedTotal += cards.count

            ARIAService.recordFlashcardGeneration(
                subjectName: subject.name,
                topicName: topic,
                subtopicName: validSubtopics.joined(separator: ", "),
                generatedCards: cards.map { ($0.front, $0.back) },
                sourceReference: "ARIAService.executeGenerateFlashcards"
            )
        }

        guard generatedTotal > 0 else {
            throw NSError(domain: "ARIAService", code: 5, userInfo: [NSLocalizedDescriptionKey: "ARIA did not generate any flashcards for that request."])
        }

        return "Generated \(generatedTotal) flashcards for \(subject.name) across \(topics.joined(separator: ", "))."
    }

    @MainActor
    private func executeEditFlashcard(action: PlannedAppAction, context: ModelContext) throws -> String {
        guard let subject = resolveSubject(named: action.subjectName, context: context) else {
            throw NSError(domain: "ARIAService", code: 19, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find the subject for that flashcard edit."])
        }

        let cards = matchingCards(for: action, subject: subject)
        guard let card = cards.first else {
            throw NSError(domain: "ARIAService", code: 20, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find a flashcard matching that edit request."])
        }

        var changes: [String] = []
        if let frontText = action.frontText?.trimmingCharacters(in: .whitespacesAndNewlines), !frontText.isEmpty, frontText != card.front {
            card.front = frontText
            changes.append("front")
        }
        if let backText = action.backText?.trimmingCharacters(in: .whitespacesAndNewlines), !backText.isEmpty, backText != card.back {
            card.back = backText
            changes.append("back")
        }

        guard !changes.isEmpty else {
            throw NSError(domain: "ARIAService", code: 21, userInfo: [NSLocalizedDescriptionKey: "ARIA needs updated flashcard text before it can edit that card."])
        }

        card.isCustom = true
        card.generationSource = "ARIA Edited"
        return "Updated the \(changes.joined(separator: " and ")) of a flashcard in \(subject.name) for \(card.topicName)."
    }

    @MainActor
    private func executeDeleteFlashcards(action: PlannedAppAction, context: ModelContext) throws -> String {
        guard let subject = resolveSubject(named: action.subjectName, context: context) else {
            throw NSError(domain: "ARIAService", code: 22, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find the subject for that flashcard cleanup."])
        }

        let cards = matchingCards(for: action, subject: subject)
        guard !cards.isEmpty else {
            throw NSError(domain: "ARIAService", code: 23, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find flashcards matching that cleanup request."])
        }

        for card in cards {
            subject.cards.removeAll { $0.id == card.id }
            context.delete(card)
        }

        return "Deleted \(cards.count) flashcard\(cards.count == 1 ? "" : "s") from \(subject.name)."
    }

    @MainActor
    private func executeUpdateProgress(action: PlannedAppAction, context: ModelContext) throws -> String {
        guard let subject = resolveSubject(named: action.subjectName, context: context) else {
            throw NSError(domain: "ARIAService", code: 6, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find the subject to update progress."])
        }

        let topics = sanitizedTopics(action.topics, subjectName: subject.name)
        let matchingCards = subject.cards.filter { card in
            topics.isEmpty || topics.contains(card.topicName)
        }

        if let masteryLevel = action.masteryLevel?.lowercased() {
            let proficiency = proficiencyLevel(from: masteryLevel)
            guard !matchingCards.isEmpty else {
                throw NSError(domain: "ARIAService", code: 7, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find cards matching that scope to update mastery."])
            }

            for card in matchingCards {
                card.proficiency = proficiency
                switch proficiency {
                case .novice:
                    card.repetitions = 0
                    card.consecutiveCorrect = 0
                    card.nextReviewDate = Date()
                case .developing:
                    card.repetitions = max(card.repetitions, 1)
                    card.consecutiveCorrect = max(card.consecutiveCorrect, 2)
                    card.nextReviewDate = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
                case .proficient:
                    card.repetitions = max(card.repetitions, 3)
                    card.consecutiveCorrect = max(card.consecutiveCorrect, 4)
                    card.nextReviewDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
                case .mastered:
                    card.repetitions = max(card.repetitions, 6)
                    card.consecutiveCorrect = max(card.consecutiveCorrect, 7)
                    card.nextReviewDate = Calendar.current.date(byAdding: .day, value: 21, to: Date()) ?? Date()
                }
            }

            return "Updated \(matchingCards.count) cards in \(subject.name) to \(proficiency.rawValue.lowercased()) mastery."
        }

        let roundedMinutes = Int(action.minutesStudied ?? 0)
        let xp = action.xpEarned ?? 0
        guard roundedMinutes > 0 || xp > 0 else {
            throw NSError(domain: "ARIAService", code: 8, userInfo: [NSLocalizedDescriptionKey: "ARIA needs a mastery level, minutes studied, or XP amount to update progress."])
        }

        let today = Calendar.current.startOfDay(for: Date())
        let predicate = #Predicate<StudyActivity> { $0.date == today }
        let activity = (try? context.fetch(FetchDescriptor(predicate: predicate)).first) ?? {
            let activity = StudyActivity(date: today)
            context.insert(activity)
            return activity
        }()

        activity.minutesStudied += Double(max(roundedMinutes, 0))
        activity.xpEarned += max(xp, 0)
        if let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first, xp > 0 {
            profile.addXP(xp)
        }

        return "Logged \(roundedMinutes)m and \(xp) XP to today's study progress."
    }

    @MainActor
    private func executeUpdateProfile(action: PlannedAppAction, context: ModelContext) throws -> String {
        guard let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first else {
            throw NSError(domain: "ARIAService", code: 9, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find a user profile to update."])
        }

        var changes: [String] = []
        if let dailyGoal = action.dailyGoal, dailyGoal > 0 {
            profile.dailyGoal = dailyGoal
            changes.append("daily goal to \(dailyGoal) cards")
        }
        if let target = action.targetIBScore, (1...45).contains(target) {
            profile.targetIBScore = target
            changes.append("target score to \(target)/45")
        }

        guard !changes.isEmpty else {
            throw NSError(domain: "ARIAService", code: 10, userInfo: [NSLocalizedDescriptionKey: "ARIA did not receive a supported profile change."])
        }

        return "Updated your profile: \(changes.joined(separator: " and "))."
    }

    @MainActor
    private func executeSaveMemory(action: PlannedAppAction, context: ModelContext) throws -> String {
        let note = action.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !note.isEmpty else {
            throw NSError(domain: "ARIAService", code: 14, userInfo: [NSLocalizedDescriptionKey: "ARIA needs the note content before it can remember it."])
        }

        let category = memoryCategory(from: action.memoryCategory)
        let memory = ARIAMemory(
            category: category,
            content: note,
            importance: .high,
            subjectName: action.subjectName?.trimmingCharacters(in: .whitespacesAndNewlines),
            topicName: action.topics?.first,
            tags: (action.topics ?? []) + (action.subtopics ?? [])
        )
        context.insert(memory)
        return "Saved that to ARIA memory under \(category.rawValue)."
    }

    @MainActor
    private func resolveSubject(named rawName: String?, context: ModelContext) -> Subject? {
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        guard let rawName = rawName?.trimmingCharacters(in: .whitespacesAndNewlines), !rawName.isEmpty else {
            return subjects.first
        }

        if let exact = subjects.first(where: { $0.name.caseInsensitiveCompare(rawName) == .orderedSame }) {
            return exact
        }

        let normalized = rawName.lowercased()
        return subjects.first(where: { $0.name.lowercased().contains(normalized) || normalized.contains($0.name.lowercased()) })
    }

    @MainActor
    private func findMatchingPlan(for action: PlannedAppAction, context: ModelContext) -> StudyPlan? {
        let subjectName = action.subjectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let targetTopics = (action.topics ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let searchText = action.searchText?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

        let plans = ((try? context.fetch(FetchDescriptor<StudyPlan>())) ?? [])
            .filter { !$0.isCompleted && (subjectName.isEmpty || $0.subjectName.caseInsensitiveCompare(subjectName) == .orderedSame) }
            .sorted { $0.scheduledDate < $1.scheduledDate }

        return plans.first { plan in
            let matchesTopics = targetTopics.isEmpty || targetTopics.allSatisfy { target in
                plan.selectedTopicNames.contains { $0.lowercased() == target } ||
                plan.selectionSummary.lowercased().contains(target)
            }
            let matchesSearch = searchText.isEmpty ||
                plan.selectionSummary.lowercased().contains(searchText) ||
                plan.planMarkdown.lowercased().contains(searchText)
            return matchesTopics && matchesSearch
        }
    }

    private func matchingCards(for action: PlannedAppAction, subject: Subject) -> [StudyCard] {
        let topics = sanitizedTopics(action.topics, subjectName: subject.name)
        let topicScope = topics.isEmpty ? uniqueTopicNames(for: subject) : topics
        let subtopics = sanitizedSubtopics(action.subtopics, subjectName: subject.name, topics: topicScope)
        let searchTerms = [action.searchText, action.frontText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        return subject.cards.filter { card in
            let matchesTopic = topics.isEmpty || topics.contains(card.topicName)
            let matchesSubtopic = subtopics.isEmpty || subtopics.contains(card.subtopic)
            let haystack = [card.front, card.back, card.topicName, card.subtopic]
                .joined(separator: "\n")
                .lowercased()
            let matchesSearch = searchTerms.isEmpty || searchTerms.allSatisfy { haystack.contains($0) }
            return matchesTopic && matchesSubtopic && matchesSearch
        }
        .sorted { $0.createdDate > $1.createdDate }
    }

    private func uniqueTopicNames(for subject: Subject) -> [String] {
        var seen = Set<String>()
        var topics: [String] = []

        for card in subject.cards {
            let topic = card.topicName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !topic.isEmpty else { continue }
            let key = topic.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            topics.append(topic)
        }

        return topics
    }

    private func sanitizedTopics(_ topics: [String]?, subjectName: String) -> [String] {
        let requested = (topics ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !requested.isEmpty else { return [] }
        let valid = Set(SyllabusSeeder.curriculum(for: subjectName).flatMap { $0.topics.map(\.name) })
        return requested.filter { valid.contains($0) }
    }

    private func sanitizedSubtopics(_ subtopics: [String]?, subjectName: String, topics: [String]) -> [String] {
        let requested = (subtopics ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !requested.isEmpty else { return [] }
        let valid = Set(topics.flatMap { SyllabusSeeder.subtopics(for: subjectName, topicName: $0) })
        return requested.filter { valid.contains($0) }
    }

    private func parseScheduledDate(_ rawValue: String?) -> Date? {
        guard let rawValue, !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: rawValue) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue)
    }

    private func defaultScheduledDate() -> Date {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        let base = cal.component(.hour, from: now) >= 16 ? (cal.date(byAdding: .day, value: 1, to: today) ?? today) : today
        return cal.date(bySettingHour: 16, minute: 0, second: 0, of: base) ?? now
    }

    private func proficiencyLevel(from rawValue: String) -> ProficiencyLevel {
        switch rawValue {
        case "novice": return .novice
        case "developing", "intermediate": return .developing
        case "proficient", "strong": return .proficient
        case "mastered", "mastery": return .mastered
        default: return .developing
        }
    }

    private func memoryCategory(from rawValue: String?) -> MemoryCategory {
        let normalized = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch normalized {
        case "grades", "targets": return .grades
        case "weaktopics", "weak_topics": return .weakTopics
        case "studyhabits", "study_habits", "habits": return .studyHabits
        case "goals": return .goals
        case "notes", "usernotes", "user_notes": return .userNotes
        case "subjectinsight", "subject_insight": return .subjectInsight
        case "sessionsummary", "session_summary": return .sessionSummary
        case "achievement", "achievements": return .achievement
        case "struggle", "struggles": return .struggle
        default: return .userNotes
        }
    }

    private static func appendStreamChunk(_ chunk: String, to current: String) -> String {
        guard !chunk.isEmpty else { return current }
        guard !current.isEmpty else { return chunk }

        var combined = current
        if shouldInsertSpace(between: current.last, and: chunk.first) {
            combined.append(" ")
        }
        combined.append(chunk)
        return combined
    }

    private static func shouldInsertSpace(between lhs: Character?, and rhs: Character?) -> Bool {
        guard let lhs, let rhs else { return false }
        guard !lhs.isWhitespace, !rhs.isWhitespace else { return false }
        guard !"\n\r\t".contains(lhs), !"\n\r\t".contains(rhs) else { return false }

        let sentenceTerminators = ".!?:"
        if sentenceTerminators.contains(lhs) {
            return rhs.isLetter || rhs.isNumber || rhs == "*" || rhs == "#" || rhs == "("
        }

        return false
    }

    private static func finalizeAssistantResponse(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "—", with: " - ")
            .replacingOccurrences(of: "–", with: " - ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        result = replaceRegex(pattern: #"(?m)^(#{1,6})([^ #\n])"#, template: "$1 $2", in: result)
        result = replaceRegex(pattern: #"(?m)(?<!\n)(#{1,6}\s)"#, template: "\n\n$1", in: result)
        result = replaceRegex(pattern: #"(?m)^\s*#{1,6}\s*$"#, template: "", in: result)
        result = replaceRegex(pattern: #"(?m)^\s*(?:[-*•]|\d+[.)])\s*$"#, template: "", in: result)
        result = replaceRegex(pattern: #"(?<=[^\n])\s+(?=((?:[-*•]|\d+[.)])\s))"#, template: "\n", in: result)
        result = replaceRegex(pattern: #"\n{3,}"#, template: "\n\n", in: result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replaceRegex(pattern: String, template: String, in source: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        let range = NSRange(source.startIndex..., in: source)
        return regex.stringByReplacingMatches(in: source, range: range, withTemplate: template)
    }

    @MainActor
    private func updateSession(_ session: ARIAChatSession, withUserMessage message: String) {
        if session.title == "New Chat" || session.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            session.title = compactSessionTitle(from: message)
        }
        session.updatedAt = Date()
        session.lastMessagePreview = compactSessionPreview(from: message)
    }

    @MainActor
    private func updateSession(_ session: ARIAChatSession, withAssistantReply reply: String) {
        session.updatedAt = Date()
        session.lastMessagePreview = compactSessionPreview(from: reply)
    }

    private func compactSessionTitle(from source: String) -> String {
        let trimmed = source
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard !trimmed.isEmpty else { return "New Chat" }
        if trimmed.count <= 44 { return trimmed }
        return String(trimmed.prefix(44)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private func compactSessionPreview(from source: String) -> String {
        let flattened = source
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard !flattened.isEmpty else { return "No messages yet" }
        if flattened.count <= 90 { return flattened }
        return String(flattened.prefix(90)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    // MARK: - System Prompt Builder
    @MainActor
    private func checkIfUserHasData(context: ModelContext) -> Bool {
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first
        let cards = subjects.flatMap { $0.cards }
        
        let hasProfile = profile?.studentName.isEmpty == false
        let hasSubjects = !subjects.isEmpty
        let hasCards = !cards.isEmpty
        let hasGrades = subjects.contains { !$0.grades.isEmpty }
        
        return hasProfile || hasSubjects || hasCards || hasGrades
    }

    @MainActor
    func buildSystemPrompt(context: ModelContext) async -> String {
        await buildSystemPrompt(context: context, seedQuery: "")
    }

    @MainActor
    func buildSystemPrompt(context: ModelContext, seedQuery: String) async -> String {
        await buildSystemPrompt(context: context, queryProfile: analyzeQuery(seedQuery))
    }

    @MainActor
    private func buildSystemPrompt(context: ModelContext, queryProfile: QueryProfile) async -> String {
        // Check if user is new
        let hasData = checkIfUserHasData(context: context)
        
        var prompt = """
        You are ARIA (Adaptive Retrieval Intelligence Assistant), the most efficient AI study companion ever built for IB students.

        CORE MISSION:
        - Your #1 goal is MAXIMUM EFFICIENCY: every minute of study must produce the highest possible IB score improvement
        - You use evidence-based learning science: spaced repetition, active recall, interleaving, elaborative interrogation
        - You understand that IB is HARD — the global average is 30/45. A score of 38+ puts you in the top 5%
        - You calibrate all advice to REAL IB DIFFICULTY, never oversimplifying

        PERSONALITY:
        - Warm but direct — like the best tutor who genuinely wants you to succeed
        - Never condescending. Celebrate wins genuinely.
        - If the user's streak broke or grades dropped, acknowledge empathetically before pivoting to action
        - Use occasional emojis for warmth, but keep it professional

        \(hasData ? "" : "NEW USER BEHAVIOR: This user hasn't set up their subjects yet. Help them get started by asking what IB subjects they're taking, then guide them to add subjects in the app. Don't assume any subject knowledge.")

        RESPONSE FORMATTING:
        - Use clean Markdown for structure: short paragraphs, bullet lists, and **bold** for key takeaways
        - Use plain hyphen bullets and avoid em dashes in prose
        - When writing maths or science equations, use LaTeX: inline as $...$ and display equations as $$...$$
        - Use code blocks with ```language for any code examples
        - Keep emoji use light and helpful, not excessive
        - Do not dump raw JSON unless the user explicitly asks for it
        - ALWAYS use proper spacing: separate sections with blank lines, use headers (###) for major sections
        - Lists should use dash (-) or asterisk (*) bullets, not numbers unless sequential order matters
        - When providing definitions, use: **Term**: Definition format
        - When providing steps, use numbered lists with clear action verbs

        STUDY GUIDE CAPABILITIES:
        - Generate session-specific study guides that target weak areas first
        - Create topic breakdowns with IB-calibrated difficulty ratings
        - Produce focused review plans: what to study, in what order, for how long
        - Build pre-session briefs: key concepts, common exam pitfalls, mark scheme hints
        - Design post-session analyses: what improved, what needs more work

        REAL IB DIFFICULTY CONTEXT:
        - Biology SL: Paper 1 (20%, MCQ), Paper 2 (40%, short answer + extended), IA (20%). Common pitfalls: photosynthesis mechanisms, genetics pedigree analysis, ecology data analysis
        - Economics HL: Paper 1 (20%, essay), Paper 2 (30%, data response), Paper 3 (30%, HL policy), IA (20%). Hardest: evaluation in essays, real-world examples, Paper 3 quantitative
        - Business Management HL: Paper 1 (35%, case study), Paper 2 (35%, structured), IA (30%). Hardest: CUEGIS application, quantitative tools, stakeholder analysis depth
        - English B HL: Paper 1 (25%, text handling), Paper 2 (25%, written production), IA (25% oral), Written Assignment (25%). Hardest: text type conventions, register accuracy, literary analysis
        - Russian A Literature SL: Paper 1 (20%, guided analysis), Paper 2 (25%, essay), IA (30%), Written Assignment (25%). Hardest: close literary analysis, author technique identification
        - Mathematics AA SL: Paper 1 (40%, no calc), Paper 2 (40%, calc), IA (20%). Hardest: proof questions, applications in Paper 1 without calculator, IA criterion E (use of math)

        IB GRADE BOUNDARIES (typical):
        - 7: 70-80%+ (subject dependent)
        - 6: 60-70%
        - 5: 50-60%
        - 4: 40-50%
        - The jump from 5→6→7 requires exponentially more effort

        CAPABILITIES:
        - Analyse grades, predict IB outcomes, identify weak spots
        - Create study plans and sprint plans calibrated to real IB difficulty
        - Generate flashcards using dedicated FRONT/BACK blocks with a blank line between cards
        - Quiz using Socratic questioning for active recall
        - Explain concepts, structure essays, clarify mark schemes at IB level
        - Track session-by-session and subject-by-subject progress
        - When the user explicitly asks, you can execute app actions: create, assign, reschedule, complete, or cancel study sessions; generate, edit, or delete flashcards in the library; and update progress/profile settings
        - Produce study guides with difficulty ratings and time allocations
        - TRACK FLASHCARD EFFECTIVENESS: You know which AI-generated flashcards are working (high review success) vs struggling (low review success). Use this to recommend regeneration of weak cards.
        - XP & MASTERY TRACKING: You have full access to student's XP, rank progression, and subject mastery percentages. Reference this to motivate students ("You're 200XP away from leveling up to Atom!").
        - SUBJECT MASTERY: You can see per-subject mastery percentages and use this to recommend which subjects need more attention based on their target IB score.

        FLASHCARD GENERATION:
        When the user asks you to create flashcards, generate them in this exact format:
        - Start each card with "FRONT:" followed by the question
        - Follow with "BACK:" followed by the answer
        - Separate cards with a blank line
        - Never put FRONT and BACK on the same line with pipes or extra labels
        - Generate IB-exam-level questions that test understanding, not just recall
        - Include a mix of definitions, applications, analysis, and evaluation questions
        - For science/math: include formulas and worked examples where relevant
        - For humanities: include real-world examples and evaluation points
        - The user can also use the "Browse Curriculum" button in any subject to generate cards automatically via the Topic Browser

        CURRICULUM AWARENESS:
        - You know the full IB DP 2027 curriculum structure for all enrolled subjects
        - Each subject has Units → Topics → Subtopics
        - When recommending study focus, reference specific topics and subtopics
        - Guide students to use the Topic Browser to generate cards for weak subtopics

        STUDY SESSION PLANNING:
        - Students can create structured study sessions via the Study Sessions tab
        - You generate time-blocked study plans with warm-up, active learning, practice, and review phases
        - ***CRITICAL FORMATTING***: You must use explicit double newlines (`\n\n`) to create paragraphs and separate sections clearly. Never return a single continuous block of text! Use Markdown headers `###` and bullet points formatted spaciously.
        - School finishes at 4pm — suggest study slots between 4pm and 10pm
        - Plans should be exam-focused: include specific concepts, practice question types, and mark scheme hints
        - Students can refine plans by chatting with you during the planning phase
        - During active sessions, students can ask you questions about the topic they're studying

        """

        // Inject memory preamble
        let memoryPreamble = await buildMemoryPreamble(context: context, queryProfile: queryProfile)
        if !memoryPreamble.isEmpty {
            prompt += "\nRELEVANT LONG-TERM CONTEXT:\n\(memoryPreamble)\n"
        }

        // Inject app state
        let appState = await buildAppStateSnapshot(context: context, queryProfile: queryProfile)
        prompt += "\nCURRENT STUDENT SNAPSHOT:\n\(appState)\n"

        let actionSpecContext = buildActionSpecPreamble(queryProfile: queryProfile)
        if !actionSpecContext.isEmpty {
            prompt += "\nPERSISTENT ACTION SPECS:\n\(actionSpecContext)\n"
        }

        let materialsContext = buildMaterialsContext(queryProfile: queryProfile)
        if !materialsContext.isEmpty {
            prompt += "\nAVAILABLE MATERIALS AND GENERATED GUIDES:\n\(materialsContext)\n"
        }

        prompt += """

        EFFICIENCY INSTRUCTIONS:
        - Always reference the user's ACTUAL data — grades, session history, weak topics
        - If cards are overdue, mention it proactively with urgency proportional to count
        - When making study plans, base on: weak topics FIRST, then upcoming exam dates, then IB weighting
        - Use session-by-session data to track improvement trends ("Last 5 sessions you averaged 72% on Bio, up from 60%")
        - Use subject-by-subject data to prioritise ("Economics is your weakest at 45% mastery — focus here")
        - Reference their target IB score gap: how many points they need and where to find them
        - For study guides: rank topics by (difficulty × weakness × exam weight) to maximise score per hour
        - If DP2: be more urgent, reference exam timeline, focus on highest-yield improvements
        - Tailor pace to their study intensity preset
        - After generating a study guide, explicitly state expected time and predicted score impact

        CURRENT SESSION CONTEXT:
        """

        // Current time context
        let now = Date()
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "EEEE, d MMMM yyyy 'at' HH:mm"
        prompt += "\n- Current time: \(timeFormatter.string(from: now))"

        // ADHD medication context
        let doseMg = UserDefaults.standard.integer(forKey: "adhdDoseMg")
        if doseMg > 0 {
            let hour = Calendar.current.component(.hour, from: now)
            let minute = Calendar.current.component(.minute, from: now)
            let hoursSince9 = Double(hour - 9) + Double(minute) / 60.0

            var focusLevel = "Not active (before first dose or late night)"
            if hoursSince9 >= 0 && hoursSince9 <= 15 {
                // Simplified PK estimation
                let peakHours: [Double] = [2, 6, 11]  // hours after 9 AM
                let isNearPeak = peakHours.contains { abs(hoursSince9 - $0) < 1.5 }
                let isWearingOff = [4.0, 8.5, 14.0].contains { abs(hoursSince9 - $0) < 1 }
                if isNearPeak { focusLevel = "Peak focus (near dose peak)" }
                else if isWearingOff { focusLevel = "Wearing off (consider timing study accordingly)" }
                else { focusLevel = "Effective range" }
            }
            prompt += "\n- ADHD Medication: Ritalin IR \(doseMg)mg, 3× daily. Current focus: \(focusLevel)"
            prompt += "\n  → Adapt study recommendations to medication peaks. Harder topics during peak focus."
        }

        // Effectiveness context
        prompt += "\n- Study method effectiveness: IB Vault (spaced repetition + active recall) = 1.7× baseline re-reading"
        prompt += "\n  → Reference this when motivating the student ('every hour here equals 1h 42m of re-reading')"

        // Exam timeline — DP1 vs DP2 awareness
        if let profileData = try? context.fetch(FetchDescriptor<UserProfile>()).first {
            let currentYear = Calendar.current.component(.year, from: now)
            if profileData.ibYear == .dp2 {
                // DP2: exams this May — urgent mode
                let examDate = Calendar.current.date(from: DateComponents(year: currentYear, month: 5, day: 5))!
                let daysToExam = Calendar.current.dateComponents([.day], from: now, to: examDate).day ?? 0
                if daysToExam > 0 {
                    prompt += "\n- ⚠️ EXAM COUNTDOWN: \(daysToExam) days until IB exams. Every session counts."
                    prompt += "\n  → DP2 mode: prioritise highest-yield topics, triage weak areas, focus on exam technique."
                }
            } else {
                // DP1: exams next May — foundation building mode
                let examDate = Calendar.current.date(from: DateComponents(year: currentYear + 1, month: 5, day: 5))!
                let monthsToExam = Calendar.current.dateComponents([.month], from: now, to: examDate).month ?? 0
                prompt += "\n- 📅 DP1 STUDENT: ~\(monthsToExam) months until IB exams (May \(currentYear + 1))."
                prompt += "\n  → DP1 mode: build strong foundations NOW. Deep understanding > cramming."
                prompt += "\n  → Focus on: mastering core concepts, starting IA research early, building consistent study habits."
                prompt += "\n  → This is the advantage window — students who build spaced repetition habits in DP1 score significantly higher."
                prompt += "\n  → Encourage exploration and genuine understanding rather than surface-level memorization."
            }
        }

        return prompt
    }

    // MARK: - Memory Preamble

    @MainActor
    private func buildMemoryPreamble(context: ModelContext, queryProfile: QueryProfile) async -> String {
        var descriptor = FetchDescriptor<ARIAMemory>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 30

        guard let memories = try? context.fetch(descriptor) else { return "" }

        let ranked = memories
            .map { memory in
                (memory, score: memoryRelevanceScore(for: memory, queryProfile: queryProfile))
            }
            .sorted {
                if $0.score == $1.score {
                    return $0.0.timestamp > $1.0.timestamp
                }
                return $0.score > $1.score
            }

        var selected: [ARIAMemory] = []
        var categoryCounts: [MemoryCategory: Int] = [:]
        var subjectCounts: [String: Int] = [:]
        
        let maxSubjects = 2

        for item in ranked {
            guard selected.count < maxMemoryItems else { break }
            guard item.score > 0 || item.0.category == .userNotes else { continue }

            let limitPerCategory: Int
            switch item.0.category {
            case .conversationHistory: limitPerCategory = 1
            case .sessionSummary: limitPerCategory = 2
            case .weakTopics, .grades, .subjectInsight: limitPerCategory = 3
            default: limitPerCategory = 2
            }
            if categoryCounts[item.0.category, default: 0] >= limitPerCategory { continue }
            
            if let subjectName = item.0.subjectName, !subjectName.isEmpty {
                if subjectCounts[subjectName, default: 0] >= maxSubjects { continue }
                subjectCounts[subjectName, default: 0] += 1
            }

            selected.append(item.0)
            categoryCounts[item.0.category, default: 0] += 1
        }

        guard !selected.isEmpty else { return "" }

        let grouped = Dictionary(grouping: selected) { $0.category }
        var lines: [String] = []

        for category in MemoryCategory.allCases {
            guard let items = grouped[category], !items.isEmpty else { continue }
            lines.append("[\(category.rawValue)]")
            for item in items {
                let ageContext = formatTemporalContext(for: item)
                let content = trimmedContextLine(item.content, limit: item.isCompacted ? 260 : 180)
                lines.append("- \(ageContext)\(content)")
            }
        }

        return lines.joined(separator: "\n")
    }
    
    private func formatTemporalContext(for memory: ARIAMemory) -> String {
        let now = Date()
        let days = Calendar.current.dateComponents([.day], from: memory.timestamp, to: now).day ?? 0
        
        if days == 0 {
            return "[Today] "
        } else if days == 1 {
            return "[Yesterday] "
        } else if days < 7 {
            return "[\(days)d ago] "
        } else if days < 30 {
            let weeks = days / 7
            return "[\(weeks)w ago] "
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "[\(formatter.string(from: memory.timestamp))] "
        }
    }

    // MARK: - App State Snapshot

    @MainActor
    private func buildAppStateSnapshot(context: ModelContext, queryProfile: QueryProfile) async -> String {
        let now = Date()
        var lines: [String] = []

        if let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first {
            let studentName = profile.studentName.isEmpty ? "Student" : profile.studentName
            lines.append("- Student: \(studentName), \(profile.ibYear.shortLabel), target \(profile.targetIBScore)/45, intensity \(profile.studyIntensity.rawValue)")
            lines.append("- Momentum: streak \(profile.currentStreak), total XP \(profile.totalXP), rank \(profile.rank.rawValue), daily goal \(profile.dailyGoal) cards")
        }

        let duePredicate = #Predicate<StudyCard> { $0.nextReviewDate <= now }
        let dueCount = (try? context.fetchCount(FetchDescriptor(predicate: duePredicate))) ?? 0
        let overdueDate = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let overduePredicate = #Predicate<StudyCard> { $0.nextReviewDate < overdueDate }
        let overdueCount = (try? context.fetchCount(FetchDescriptor(predicate: overduePredicate))) ?? 0
        lines.append("- Review load: \(dueCount) due cards, \(overdueCount) overdue")

        let sessionDescriptor = FetchDescriptor<ReviewSession>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        let sessions = (try? context.fetch(sessionDescriptor)) ?? []
        let recentSessions = Array(sessions.prefix(40))
        if !recentSessions.isEmpty {
            let recentRetention = Int(ProficiencyTracker.retentionRate(from: recentSessions) * 100)
            let avgQuality = Double(recentSessions.map(\.qualityRating).reduce(0, +)) / Double(max(1, recentSessions.count))
            lines.append("- Recent reviews: \(recentSessions.count) cards, \(recentRetention)% retention, avg quality \(String(format: "%.1f", avgQuality))/5")
        }

        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        
        if subjects.isEmpty {
            lines.append("- No subjects configured yet - user needs to add subjects first")
            lines.append("- Ask user which IB subjects they're taking")
            return lines.joined(separator: "\n")
        }
        
        let selectedSubjects = prioritizedSubjects(from: subjects, queryProfile: queryProfile, now: now)
        if !selectedSubjects.isEmpty {
            lines.append("- Priority subjects:")
            for subject in selectedSubjects.prefix(min(maxContextSubjects, queryProfile.preferredSubjectCount)) {
                lines.append(contentsOf: subjectSummaryLines(subject: subject, sessions: sessions, queryProfile: queryProfile, now: now))
            }
        }

        let allGrades = subjects.flatMap(\.grades).sorted { $0.date > $1.date }
        if queryProfile.intent == .performanceReview, !allGrades.isEmpty {
            let recentGrades = allGrades.prefix(4).map { grade in
                let subjectName = grade.subject?.name ?? "Unknown Subject"
                return "\(subjectName) \(grade.component): \(grade.score)"
            }
            lines.append("- Latest grades: \(recentGrades.joined(separator: "; "))")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Conversation History

    private let tokenToCharRatio = 4
    
    @MainActor
    private func buildConversationHistory(context: ModelContext, queryProfile: QueryProfile, sessionID: UUID) async -> [GeminiMessage] {
        let windowSize = UserDefaults.standard.integer(forKey: "ariaContextWindow")
        var descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = max(windowSize, 30)

        guard let messages = try? context.fetch(descriptor), !messages.isEmpty else { return [] }

        let estimatedTokenBudget = queryProfile.historyCharacterBudget / tokenToCharRatio
        
        var selected: [ChatMessage] = []
        var selectedIDs = Set<UUID>()
        var totalTokens = 0

        let recentMessages = Array(messages.prefix(8))
        for message in recentMessages {
            let messageTokens = estimateTokens(in: message.content)
            if totalTokens + messageTokens > estimatedTokenBudget / 2 {
                break
            }
            selected.append(message)
            selectedIDs.insert(message.id)
            totalTokens += messageTokens
        }

        for message in messages {
            guard !selectedIDs.contains(message.id) else { continue }
            
            let messageTokens = estimateTokens(in: message.content)
            
            if totalTokens + messageTokens > estimatedTokenBudget {
                if selected.count >= 3 {
                    break
                }
            }

            selected.append(message)
            selectedIDs.insert(message.id)
            totalTokens += messageTokens

            if selected.count >= maxHistoryMessages || totalTokens >= estimatedTokenBudget {
                break
            }
        }

        if !queryProfile.keywords.isEmpty {
            let topicalCandidates = messages
                .filter { !selectedIDs.contains($0.id) }
                .map { message in
                    (message, score: keywordOverlapScore(in: message.content, keywords: queryProfile.keywords))
                }
                .filter { $0.score > 0 }
                .sorted {
                    if $0.score == $1.score {
                        return $0.0.timestamp > $1.0.timestamp
                    }
                    return $0.score > $1.score
                }

            for candidate in topicalCandidates {
                let cost = estimateTokens(in: candidate.0.content)
                guard selected.count < maxHistoryMessages else { break }
                guard totalTokens + cost <= estimatedTokenBudget else { continue }

                selected.append(candidate.0)
                selectedIDs.insert(candidate.0.id)
                totalTokens += cost
            }
        }
        
        let systemMessages = buildSystemContextMessages(queryProfile: queryProfile)
        
        return systemMessages + selected.sorted { $0.timestamp < $1.timestamp }.map { msg in
            GeminiMessage(role: msg.role, text: msg.content)
        }
    }
    
    private func estimateTokens(in text: String) -> Int {
        return text.count / tokenToCharRatio
    }
    
    private func buildSystemContextMessages(queryProfile: QueryProfile) -> [GeminiMessage] {
        var messages: [GeminiMessage] = []
        
        let intentContext: String
        switch queryProfile.intent {
        case .studyPlan:
            intentContext = "User is requesting a study plan. Focus on: weak topics, time availability, and exam relevance."
        case .performanceReview:
            intentContext = "User wants to review their performance. Focus on: grades, retention rates, and improvement trends."
        case .flashcards, .quiz:
            intentContext = "User wants to practice with flashcards or a quiz. Focus on: weak topics and key concepts."
        case .explanation:
            intentContext = "User wants an explanation. Focus on: clear, structured answers with examples."
        case .general:
            intentContext = "General conversation. Be helpful and contextually aware."
        }
        
        messages.append(GeminiMessage(role: "system", text: "Current intent: \(intentContext)\nRelevant keywords: \(queryProfile.keywords.joined(separator: ", "))"))
        
        return messages
    }

    private func buildActionSpecPreamble(queryProfile: QueryProfile) -> String {
        let rankedSpecs = ARIAContextSpecStore.recentSpecs(limit: 60)
            .map { spec in
                (spec, score: actionSpecRelevanceScore(for: spec, queryProfile: queryProfile))
            }
            .sorted {
                if $0.score == $1.score {
                    return $0.0.createdAt > $1.0.createdAt
                }
                return $0.score > $1.score
            }

        var selected: [ARIAActionSpec] = []
        var typeCounts: [ARIAActionSpecType: Int] = [:]

        for entry in rankedSpecs {
            guard selected.count < queryProfile.preferredActionSpecCount else { break }
            if !queryProfile.rawQuery.isEmpty && entry.score <= 0 { continue }

            let perTypeLimit = entry.0.actionType == .studyGuide ? 2 : 1
            if typeCounts[entry.0.actionType, default: 0] >= perTypeLimit { continue }

            selected.append(entry.0)
            typeCounts[entry.0.actionType, default: 0] += 1
        }

        guard !selected.isEmpty else { return "" }

        return selected.map { spec in
            var lines = ["- \(spec.title) [\(spec.actionType.label)] — \(spec.createdAt.formatted(date: .abbreviated, time: .shortened))"]
            lines.append("  \(trimmedContextLine(spec.summary, limit: 220))")

            if !spec.detailLines.isEmpty {
                for detail in spec.detailLines.prefix(2) {
                    lines.append("  • \(trimmedContextLine(detail, limit: 180))")
                }
            }

            return lines.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private func buildMaterialsContext(queryProfile: QueryProfile) -> String {
        guard queryProfile.needsMaterialsContext else { return "" }

        let matches = ARIAMaterialsCatalog.relevantMatches(
            queryText: queryProfile.normalizedQuery,
            keywords: queryProfile.keywords,
            limit: 3
        )

        guard !matches.isEmpty else { return "" }

        return matches.map { match in
            var lines = ["- \(match.collection.name) (\(match.collection.subject)): \(match.collection.description)"]
            if !match.topFiles.isEmpty {
                lines.append("  files: \(match.topFiles.prefix(5).joined(separator: "; "))")
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    // MARK: - Context Compaction

    @MainActor
    private func checkAndCompact(context: ModelContext, apiKey: String, sessionID: UUID) async {
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )

        guard let allMessages = try? context.fetch(descriptor) else { return }
        guard allMessages.count >= minMessagesBeforeCompaction else { return }

        // Rough token estimate (4 chars per token)
        let totalTokens = allMessages.reduce(0) { $0 + $1.content.count / 4 }

        guard totalTokens > tokenThreshold else { return }

        // Compact only the oldest portion while preserving a strong recent window.
        let compactCount = min(
            Int(Double(allMessages.count) * 0.5),
            max(0, allMessages.count - minMessagesToKeepAfterCompaction)
        )
        guard compactCount >= 8 else { return }

        let toCompact = Array(allMessages.prefix(compactCount))

        let conversationText = toCompact.map { "\($0.role): \($0.content)" }.joined(separator: "\n")

        let prompt = """
        Summarize this conversation into durable study memory for a tutoring assistant.

        Extract only information that will still be useful later:
        - grades, targets, and likely score gaps
        - weak subjects, topics, and recurring mistakes
        - study habits, constraints, and preferred pacing
        - deadlines, exams, or personal goals
        - unresolved follow-ups or action items

        Ignore small talk and short-lived phrasing.
        Keep it concise (under 350 words) with bullet points and clear category headers.

        Conversation:
        \(conversationText)
        """

        do {
            let summary = try await GeminiService.generateContent(
                messages: [GeminiMessage(role: "user", text: prompt)],
                systemInstruction: "You are a conversation summarizer. Extract and categorize key information.",
                apiKey: apiKey
            )

            // Save compacted summary
            let memory = ARIAMemory(category: .conversationHistory, content: summary, isCompacted: true)
            context.insert(memory)

            // Archive old messages
            for msg in toCompact {
                context.delete(msg)
            }

            try? context.save()
        } catch {
            print("Compaction failed: \(error)")
        }
    }

    private func analyzeQuery(_ query: String) -> QueryProfile {
        let normalizedQuery = query.lowercased()
        let keywords = Set(
            normalizedQuery
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !Self.stopWords.contains($0) }
        )

        let intent: QueryIntent
        if containsAny(normalizedQuery, phrases: ["flashcard", "flashcards", "make cards", "create cards"]) {
            intent = .flashcards
        } else if containsAny(normalizedQuery, phrases: ["quiz me", "test me", "practice questions", "question me"]) {
            intent = .quiz
        } else if containsAny(normalizedQuery, phrases: ["study plan", "what should i study", "this week", "today", "schedule", "revision plan", "study guide", "revision guide", "resources", "materials"]) {
            intent = .studyPlan
        } else if containsAny(normalizedQuery, phrases: ["analyse", "analyze", "weak", "grades", "grade", "score", "performance", "predict"]) {
            intent = .performanceReview
        } else if containsAny(normalizedQuery, phrases: ["explain", "teach me", "how do", "why does", "what is"]) {
            intent = .explanation
        } else {
            intent = .general
        }

        return QueryProfile(
            rawQuery: query,
            normalizedQuery: normalizedQuery,
            keywords: keywords,
            intent: intent
        )
    }

    private func prioritizedSubjects(from subjects: [Subject], queryProfile: QueryProfile, now: Date) -> [Subject] {
        let ranked = subjects
            .map { subject in
                (subject: subject, score: subjectRelevanceScore(for: subject, queryProfile: queryProfile, now: now))
            }
            .sorted {
                if $0.score == $1.score {
                    return $0.subject.name < $1.subject.name
                }
                return $0.score > $1.score
            }

        let positiveMatches = ranked.filter { $0.score > 0 }.map { $0.subject }
        if !positiveMatches.isEmpty {
            return positiveMatches
        }

        return subjects
            .sorted {
                let lhsScore = defaultPriorityScore(for: $0, now: now)
                let rhsScore = defaultPriorityScore(for: $1, now: now)
                if lhsScore == rhsScore {
                    return $0.name < $1.name
                }
                return lhsScore > rhsScore
            }
    }

    @MainActor
    private func inferredLoggingContext(context: ModelContext, queryProfile: QueryProfile) -> LoggingContext {
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        guard !subjects.isEmpty else {
            return LoggingContext(subjectName: "", topicNames: [])
        }

        let now = Date()
        let rankedSubjects = subjects
            .map { subject in
                (
                    subject: subject,
                    score: subjectRelevanceScore(for: subject, queryProfile: queryProfile, now: now),
                    matchedTopics: matchedTopics(for: subject, keywords: queryProfile.keywords)
                )
            }
            .sorted {
                if $0.score == $1.score {
                    return $0.subject.name < $1.subject.name
                }
                return $0.score > $1.score
            }

        guard let primary = rankedSubjects.first else {
            return LoggingContext(subjectName: "", topicNames: [])
        }

        let nextScore = rankedSubjects.dropFirst().first?.score ?? Int.min
        let hasExplicitSubjectMatch = queryProfile.normalizedQuery.contains(primary.subject.name.lowercased())
        let hasMatchedTopics = !primary.matchedTopics.isEmpty
        let isOnlySubject = subjects.count == 1
        let isStrongIntentMatch = queryProfile.intent != .general && (primary.score >= 40 || primary.score - nextScore >= 20)

        guard hasExplicitSubjectMatch || hasMatchedTopics || isOnlySubject || isStrongIntentMatch else {
            return LoggingContext(subjectName: "", topicNames: [])
        }

        var topicNames = Array(primary.matchedTopics.prefix(4))
        if topicNames.isEmpty && queryProfile.intent != .general {
            topicNames = Array(uniqueWeakTopicNames(for: primary.subject).prefix(3))
        }
        if topicNames.isEmpty {
            let recentTopics = primary.subject.cards
                .sorted { ($0.lastReviewedDate ?? $0.createdDate) > ($1.lastReviewedDate ?? $1.createdDate) }
                .flatMap { [$0.topicName, $0.subtopic] }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            var seen = Set<String>()
            topicNames = recentTopics.filter { topic in
                let key = topic.lowercased()
                guard !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
            .prefix(3)
            .map { $0 }
        }

        return LoggingContext(subjectName: primary.subject.name, topicNames: topicNames)
    }

    private func subjectSummaryLines(subject: Subject, sessions: [ReviewSession], queryProfile: QueryProfile, now: Date) -> [String] {
        let masteryPercent = Int(ProficiencyTracker.masteryPercentage(for: subject) * 100)
        let weakTopics = uniqueWeakTopicNames(for: subject).prefix(4)
        let mentionedTopics = matchedTopics(for: subject, keywords: queryProfile.keywords).prefix(3)
        let recentGrades = subject.grades.sorted { $0.date > $1.date }.prefix(3)
        let recentWindowStart = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now
        let recentSessions = sessions.filter {
            $0.subjectName == subject.name &&
            $0.timestamp >= recentWindowStart
        }

        let aiEffectiveness = ProficiencyTracker.overallAIEffectiveness(for: subject)
        let strugglingCards = ProficiencyTracker.strugglingCards(for: subject).count
        let aiCards = subject.cards.filter { $0.isAIGenerated ?? false }.count

        var headline = "  • \(subject.name) \(subject.level): mastery \(masteryPercent)%, due \(subject.dueCardsCount)/\(subject.cards.count)"
        if aiCards > 0 {
            let effPercent = Int(aiEffectiveness * 100)
            headline += ", ARIA cards: \(aiCards) (\(effPercent)% effective"
            if strugglingCards > 0 {
                headline += ", \(strugglingCards) need review"
            }
            headline += ")"
        }
        if let examDate = subject.examDate {
            let days = Calendar.current.dateComponents([.day], from: now, to: examDate).day ?? 0
            headline += days >= 0 ? ", exam in \(days)d" : ", exam passed"
        }

        var lines = [headline]
        if !weakTopics.isEmpty {
            lines.append("    weak topics: \(weakTopics.joined(separator: ", "))")
        }
        if !mentionedTopics.isEmpty {
            lines.append("    query-matched topics: \(mentionedTopics.joined(separator: ", "))")
        }
        if !recentGrades.isEmpty {
            let gradeSummary = recentGrades.map { "\($0.component) \($0.score)" }.joined(separator: ", ")
            lines.append("    recent grades: \(gradeSummary)")
        }
        if !recentSessions.isEmpty {
            let retention = Int(ProficiencyTracker.retentionRate(from: recentSessions) * 100)
            let avgQuality = Double(recentSessions.map(\.qualityRating).reduce(0, +)) / Double(max(1, recentSessions.count))
            lines.append("    last 14d: \(recentSessions.count) reviews, \(retention)% retention, quality \(String(format: "%.1f", avgQuality))/5")
        }
        if strugglingCards > 0 {
            lines.append("    ⚠️ ARIA struggling cards: \(strugglingCards) - consider regenerating or reviewing these topics")
        }

        return lines
    }

    private func uniqueWeakTopicNames(for subject: Subject) -> [String] {
        var seen = Set<String>()
        var topics: [String] = []

        for card in ProficiencyTracker.weakTopics(for: subject) {
            let name = card.topicName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            topics.append(name)
        }

        return topics
    }

    private func matchedTopics(for subject: Subject, keywords: Set<String>) -> [String] {
        guard !keywords.isEmpty else { return [] }
        var seen = Set<String>()
        var topics: [String] = []

        for card in subject.cards {
            let candidates = [card.topicName, card.subtopic]
            for candidate in candidates {
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let key = trimmed.lowercased()
                guard !seen.contains(key), keywordOverlapScore(in: trimmed, keywords: keywords) > 0 else { continue }
                seen.insert(key)
                topics.append(trimmed)
            }
        }

        return topics.sorted()
    }

    private func memoryRelevanceScore(for memory: ARIAMemory, queryProfile: QueryProfile) -> Int {
        var score = categoryWeight(for: memory.category, intent: queryProfile.intent)
        score += keywordOverlapScore(in: memory.content, keywords: queryProfile.keywords) * 6
        
        score += Int(memory.importanceScore)
        score += Int(memory.relevanceBoost * 2)
        
        if memory.category == .userNotes { score += 3 }
        if memory.isCompacted { score -= 1 }
        
        if let subjectName = memory.subjectName, !subjectName.isEmpty {
            if queryProfile.normalizedQuery.lowercased().contains(subjectName.lowercased()) {
                score += 5
            }
        }
        
        if let topicName = memory.topicName, !topicName.isEmpty {
            if queryProfile.normalizedQuery.lowercased().contains(topicName.lowercased()) {
                score += 4
            }
        }
        
        for tag in memory.tags {
            if queryProfile.keywords.contains(tag.lowercased()) {
                score += 3
            }
        }
        
        let ageInDays = Calendar.current.dateComponents([.day], from: memory.timestamp, to: Date()).day ?? 0
        score += max(0, 7 - ageInDays)
        
        score -= Int(memory.effectiveAge / 10)
        
        return max(0, score)
    }

    private func categoryWeight(for category: MemoryCategory, intent: QueryIntent) -> Int {
        let basePriority = category.priority / 10
        
        switch intent {
        case .studyPlan:
            switch category {
            case .weakTopics: return basePriority + 3
            case .grades: return basePriority + 2
            case .goals: return basePriority + 2
            case .subjectInsight: return basePriority + 2
            case .sessionSummary: return basePriority + 1
            case .studyHabits: return basePriority + 1
            case .achievement: return basePriority
            case .struggle: return basePriority + 1
            case .userNotes: return basePriority
            case .conversationHistory: return 2
            }

        case .performanceReview:
            switch category {
            case .grades: return basePriority + 3
            case .weakTopics: return basePriority + 3
            case .achievement: return basePriority + 2
            case .sessionSummary: return basePriority + 1
            case .subjectInsight: return basePriority + 1
            case .studyHabits: return basePriority
            case .goals: return basePriority
            case .struggle: return basePriority
            case .userNotes: return basePriority - 1
            case .conversationHistory: return 2
            }

        case .flashcards, .quiz, .explanation:
            switch category {
            case .weakTopics: return basePriority + 3
            case .subjectInsight: return basePriority + 2
            case .struggle: return basePriority + 2
            case .sessionSummary: return basePriority + 1
            case .userNotes: return basePriority
            case .grades: return basePriority - 1
            case .studyHabits: return basePriority - 2
            case .goals: return basePriority - 2
            case .achievement: return basePriority - 3
            case .conversationHistory: return 2
            }

        case .general:
            switch category {
            case .userNotes: return basePriority + 1
            case .goals: return basePriority
            case .studyHabits: return basePriority
            case .achievement: return basePriority
            case .grades: return basePriority - 1
            case .weakTopics: return basePriority - 1
            case .subjectInsight: return basePriority - 1
            case .sessionSummary: return basePriority - 2
            case .struggle: return basePriority - 2
            case .conversationHistory: return 2
            }
        }
    }

    private func subjectRelevanceScore(for subject: Subject, queryProfile: QueryProfile, now: Date) -> Int {
        var score = defaultPriorityScore(for: subject, now: now)

        if queryProfile.normalizedQuery.contains(subject.name.lowercased()) {
            score += 120
        }
        if subject.name.lowercased().contains("mathematics") && (queryProfile.keywords.contains("math") || queryProfile.keywords.contains("maths")) {
            score += 120
        }

        score += keywordOverlapScore(in: subject.name, keywords: queryProfile.keywords) * 10
        score += matchedTopics(for: subject, keywords: queryProfile.keywords).count * 18

        switch queryProfile.intent {
        case .studyPlan:
            score += min(subject.dueCardsCount, 20)
        case .performanceReview:
            score += subject.grades.isEmpty ? 0 : 18
        case .flashcards, .quiz, .explanation:
            score += min(uniqueWeakTopicNames(for: subject).count * 3, 15)
        case .general:
            break
        }

        return score
    }

    private func actionSpecRelevanceScore(for spec: ARIAActionSpec, queryProfile: QueryProfile) -> Int {
        var score = actionTypeWeight(for: spec.actionType, intent: queryProfile.intent)
        score += keywordOverlapScore(in: spec.searchText, keywords: queryProfile.keywords) * 8

        if !spec.subjectName.isEmpty && queryProfile.normalizedQuery.contains(spec.subjectName.lowercased()) {
            score += 28
        }

        let ageInDays = Calendar.current.dateComponents([.day], from: spec.createdAt, to: Date()).day ?? 0
        score += max(0, 10 - ageInDays)
        return score
    }

    private func actionTypeWeight(for actionType: ARIAActionSpecType, intent: QueryIntent) -> Int {
        switch intent {
        case .studyPlan:
            switch actionType {
                case .studyGuide: return 9
                case .studyPlanDraft, .planRevision: return 9
                case .studyPlan, .plannedSession: return 8
                case .ariaConversation: return 7
                case .flashcardBatch: return 6
                case .reviewSession: return 6
                case .developmentUpdate: return 1
            }

        case .performanceReview:
            switch actionType {
                case .reviewSession: return 9
                case .studyGuide: return 6
                case .flashcardBatch: return 5
                case .ariaConversation: return 4
                case .studyPlanDraft, .planRevision: return 5
                case .studyPlan, .plannedSession: return 5
                case .developmentUpdate: return 1
            }

        case .flashcards, .quiz, .explanation:
            switch actionType {
                case .flashcardBatch: return 10
                case .studyGuide: return 8
                case .ariaConversation: return 7
                case .reviewSession: return 7
                case .studyPlanDraft, .planRevision: return 6
                case .studyPlan, .plannedSession: return 5
                case .developmentUpdate: return 1
            }

        case .general:
            switch actionType {
                case .ariaConversation: return 8
                case .studyGuide: return 6
                case .reviewSession: return 6
                case .flashcardBatch: return 5
                case .studyPlanDraft, .planRevision: return 5
                case .studyPlan, .plannedSession: return 5
                case .developmentUpdate: return 2
            }
        }
    }

    private func defaultPriorityScore(for subject: Subject, now: Date) -> Int {
        let masteryPenalty = Int((1.0 - ProficiencyTracker.masteryPercentage(for: subject)) * 40)
        let duePressure = min(subject.dueCardsCount, 20)
        var examUrgency = 0

        if let examDate = subject.examDate {
            let days = Calendar.current.dateComponents([.day], from: now, to: examDate).day ?? 999
            if days >= 0 {
                examUrgency = max(0, 30 - min(days, 30))
            }
        }

        return masteryPenalty + duePressure + examUrgency
    }

    private func keywordOverlapScore(in source: String, keywords: Set<String>) -> Int {
        guard !keywords.isEmpty else { return 0 }
        let haystack = source.lowercased()
        return keywords.reduce(0) { partial, keyword in
            partial + (haystack.contains(keyword) ? 1 : 0)
        }
    }

    private func trimmedContextLine(_ text: String, limit: Int) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard singleLine.count > limit else { return singleLine }
        return String(singleLine.prefix(limit - 1)) + "…"
    }

    private func containsAny(_ text: String, phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }

    // MARK: - Greeting

    func generateGreeting(context: ModelContext) -> String {
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        let timeGreeting: String
        if hour < 12 { timeGreeting = "Good morning" }
        else if hour < 18 { timeGreeting = "Good afternoon" }
        else { timeGreeting = "Good evening" }

        let duePredicate = #Predicate<StudyCard> { $0.nextReviewDate <= now }
        let dueCount = (try? context.fetchCount(FetchDescriptor(predicate: duePredicate))) ?? 0

        if dueCount > 0 {
            let overdueDate = Calendar.current.date(byAdding: .day, value: -1, to: now)!
            let overduePredicate = #Predicate<StudyCard> { $0.nextReviewDate < overdueDate }
            let overdueCount = (try? context.fetchCount(FetchDescriptor(predicate: overduePredicate))) ?? 0

            if overdueCount > 0 {
                return "\(timeGreeting)! You have \(dueCount) cards due today, \(overdueCount) of them are overdue — want to tackle those first?"
            }
            return "\(timeGreeting)! You have \(dueCount) cards due today. Ready to start your review? 📚"
        }

        return "\(timeGreeting)! You're all caught up — no cards due right now. Want to explore a new topic or review your grades? 🎯"
    }

    // MARK: - Save Memory

    func saveMemory(category: MemoryCategory, content: String, context: ModelContext) {
        let memory = ARIAMemory(category: category, content: content)
        context.insert(memory)
        try? context.save()
    }

    static func recordReviewSession(subjectName: String, topics: [String], cardsReviewed: Int, correctCount: Int, xpEarned: Int, durationMinutes: Double) {
        let accuracy = cardsReviewed == 0 ? 0 : Int((Double(correctCount) / Double(cardsReviewed)) * 100)
        let roundedMinutes = normalizedDurationMinutes(durationMinutes)
        let detailLines = [
            "Topics: \(topics.prefix(6).joined(separator: ", "))",
            "Cards reviewed: \(cardsReviewed)",
            "Accuracy: \(accuracy)%",
            "Duration: \(roundedMinutes) minutes",
            "XP earned: \(xpEarned)"
        ]

        let spec = ARIAActionSpec(
            actionType: .reviewSession,
            title: "Review session completed for \(subjectName)",
            subjectName: subjectName,
            topicNames: topics,
            summary: "Completed a review session in \(subjectName) covering \(topics.prefix(4).joined(separator: ", ")). Reviewed \(cardsReviewed) cards with \(accuracy)% accuracy in \(roundedMinutes) minutes.",
            detailLines: detailLines,
            sourceReference: "ReviewSessionView.completeSession"
        )

        ARIAContextSpecStore.write(spec)
    }

    static func recordPlannedStudySession(subjectName: String, topics: [String], planMarkdown: String, notes: String, xpEarned: Int, durationMinutes: Double) {
        let roundedMinutes = normalizedDurationMinutes(durationMinutes)
        var detailLines = [
            "Topics: \(topics.prefix(6).joined(separator: ", "))",
            "Duration: \(roundedMinutes) minutes",
            "XP earned: \(xpEarned)"
        ]

        let trimmedPlan = planMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPlan.isEmpty {
            detailLines.append("Plan focus: \(trimmedPlan.prefix(240))")
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            detailLines.append("Session notes: \(trimmedNotes.prefix(240))")
        }

        let spec = ARIAActionSpec(
            actionType: .plannedSession,
            title: "Planned study session completed for \(subjectName)",
            subjectName: subjectName,
            topicNames: topics,
            summary: "Completed a planned study session in \(subjectName) focused on \(topics.prefix(4).joined(separator: ", ")). Duration \(roundedMinutes) minutes, XP \(xpEarned).",
            detailLines: detailLines,
            sourceReference: "ActiveStudySessionView.completeSession"
        )

        ARIAContextSpecStore.write(spec)
    }

    static func recordStudyPlan(subjectName: String, topicName: String, subtopicName: String, scheduledDate: Date, durationMinutes: Int, planMarkdown: String) {
        let topics = [topicName, subtopicName].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var detailLines = [
            "Scheduled for: \(scheduledDate.formatted(date: .abbreviated, time: .shortened))",
            "Duration: \(durationMinutes) minutes"
        ]
        let trimmedPlan = planMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPlan.isEmpty {
            detailLines.append("Plan outline: \(trimmedPlan.prefix(240))")
        }

        let spec = ARIAActionSpec(
            actionType: .studyPlan,
            title: "Study plan created for \(subjectName)",
            subjectName: subjectName,
            topicNames: topics,
            summary: "Created a study plan for \(subjectName) on \(topics.joined(separator: ", ")) scheduled for \(scheduledDate.formatted(date: .abbreviated, time: .shortened)).",
            detailLines: detailLines,
            sourceReference: "NewStudySessionView.saveSession"
        )

        ARIAContextSpecStore.write(spec)
    }

    static func recordStudyGuide(subjectName: String, mode: String, guideText: String) {
        let lines = guideText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let detailLines = Array(lines.prefix(5))
        let topics = lines
            .filter { $0.hasPrefix("##") || ($0.hasPrefix("**") && $0.hasSuffix("**")) }
            .map {
                $0.replacingOccurrences(of: "#", with: "")
                    .replacingOccurrences(of: "**", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

        let spec = ARIAActionSpec(
            actionType: .studyGuide,
            title: "\(mode) guide generated for \(subjectName)",
            subjectName: subjectName,
            topicNames: Array(topics.prefix(6)),
            summary: "Generated a \(mode.lowercased()) for \(subjectName). This guide can be reused by ARIA as structured study context for later chats.",
            detailLines: detailLines,
            sourceReference: "StudyGuideView.generateGuide"
        )

        ARIAContextSpecStore.write(spec)
    }

    static func recordStudyPlanDraft(subjectName: String, topicName: String, subtopicName: String, scheduledDate: Date, durationMinutes: Int, planMarkdown: String) {
        let topics = [topicName, subtopicName].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var detailLines = [
            "Scheduled for: \(scheduledDate.formatted(date: .abbreviated, time: .shortened))",
            "Duration: \(durationMinutes) minutes"
        ]

        let trimmedPlan = compactSpecLine(planMarkdown, limit: 240)
        if !trimmedPlan.isEmpty {
            detailLines.append("Draft outline: \(trimmedPlan)")
        }

        let spec = ARIAActionSpec(
            actionType: .studyPlanDraft,
            title: "Study plan draft generated for \(subjectName)",
            subjectName: subjectName,
            topicNames: topics,
            summary: "Generated a study plan draft for \(subjectName) on \(topics.joined(separator: ", ")) before the session was saved.",
            detailLines: detailLines,
            sourceReference: "NewStudySessionView.generatePlan"
        )

        ARIAContextSpecStore.write(spec)
    }

    static func recordStudyPlanRevision(subjectName: String, topicName: String, subtopicName: String, userRequest: String, updatedPlanMarkdown: String, sourceReference: String) {
        let topics = [topicName, subtopicName].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let detailLines = [
            "User request: \(compactSpecLine(userRequest, limit: 180))",
            "Updated plan: \(compactSpecLine(updatedPlanMarkdown, limit: 240))"
        ]

        let spec = ARIAActionSpec(
            actionType: .planRevision,
            title: "Study plan revised for \(subjectName)",
            subjectName: subjectName,
            topicNames: topics,
            summary: "ARIA revised a study plan for \(subjectName) based on user feedback, keeping the plan context available for future chats.",
            detailLines: detailLines,
            sourceReference: sourceReference
        )

        ARIAContextSpecStore.write(spec)
    }

    static func recordFlashcardGeneration(subjectName: String, topicName: String, subtopicName: String, generatedCards: [(front: String, back: String)], sourceReference: String) {
        let topics = [topicName, subtopicName].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var detailLines = [
            "Cards generated: \(generatedCards.count)"
        ]

        for front in generatedCards.prefix(3).map(\.front) {
            detailLines.append("Card prompt: \(compactSpecLine(front, limit: 140))")
        }

        let spec = ARIAActionSpec(
            actionType: .flashcardBatch,
            title: "Flashcards generated for \(subjectName)",
            subjectName: subjectName,
            topicNames: topics,
            summary: "ARIA generated \(generatedCards.count) flashcards for \(subjectName) on \(topics.joined(separator: ", ")).",
            detailLines: detailLines,
            sourceReference: sourceReference
        )

        ARIAContextSpecStore.write(spec)
    }

    static func recordARIAChatExchange(subjectName: String, topicNames: [String], userMessage: String, assistantReply: String, sourceReference: String) {
        let normalizedSubject = subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let detailLines = [
            "User message: \(compactSpecLine(userMessage, limit: 180))",
            "ARIA reply: \(compactSpecLine(assistantReply, limit: 220))"
        ]

        let summarySubject = normalizedSubject.isEmpty ? "general study context" : normalizedSubject
        let spec = ARIAActionSpec(
            actionType: .ariaConversation,
            title: normalizedSubject.isEmpty ? "ARIA conversation recorded" : "ARIA conversation recorded for \(normalizedSubject)",
            subjectName: normalizedSubject,
            topicNames: topicNames,
            summary: "Recorded an ARIA conversation in \(summarySubject) so later prompts can reuse the user's active context and recent assistant guidance.",
            detailLines: detailLines,
            sourceReference: sourceReference
        )

        ARIAContextSpecStore.write(spec)
    }

    static func recordDevelopmentUpdate(title: String, summary: String, detailLines: [String], sourceReference: String) {
        let spec = ARIAActionSpec(
            actionType: .developmentUpdate,
            title: title,
            subjectName: "Development",
            topicNames: [],
            summary: compactSpecLine(summary, limit: 220),
            detailLines: detailLines.map { compactSpecLine($0, limit: 220) },
            sourceReference: sourceReference
        )

        ARIAContextSpecStore.write(spec)
    }

    private static func compactSpecLine(_ text: String, limit: Int) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard singleLine.count > limit else { return singleLine }
        return String(singleLine.prefix(limit - 1)) + "…"
    }

    static func normalizedDurationMinutes(_ durationMinutes: Double) -> Int {
        max(1, Int(durationMinutes.rounded()))
    }

    // MARK: - Auto-Update Rank

    private func autoUpdateRank(context: ModelContext) {
        guard let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first else { return }
        guard let subjects = try? context.fetch(FetchDescriptor<Subject>()) else { return }

        let allGrades = subjects.flatMap { $0.grades }
        guard !allGrades.isEmpty else { return }

        let avg = Double(allGrades.map(\.score).reduce(0, +)) / Double(allGrades.count)
        let totalReviews = (try? context.fetchCount(FetchDescriptor<ReviewSession>())) ?? 0

        profile.autoUpdateFromGrades(averageGrade: avg, totalReviews: totalReviews)
    }
}

private enum ARIAActionSpecType: String, Codable {
    case reviewSession = "review_session"
    case plannedSession = "planned_study_session"
    case studyPlan = "study_plan"
    case studyPlanDraft = "study_plan_draft"
    case planRevision = "study_plan_revision"
    case studyGuide = "study_guide"
    case flashcardBatch = "flashcard_batch"
    case ariaConversation = "aria_conversation"
    case developmentUpdate = "development_update"

    var label: String {
        switch self {
        case .reviewSession: return "review"
        case .plannedSession: return "session"
        case .studyPlan: return "plan"
        case .studyPlanDraft: return "draft"
        case .planRevision: return "revision"
        case .studyGuide: return "guide"
        case .flashcardBatch: return "cards"
        case .ariaConversation: return "chat"
        case .developmentUpdate: return "dev"
        }
    }
}

private struct ARIAActionSpec: Codable {
    let id: UUID
    let actionType: ARIAActionSpecType
    let title: String
    let subjectName: String
    let topicNames: [String]
    let summary: String
    let detailLines: [String]
    let sourceReference: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        actionType: ARIAActionSpecType,
        title: String,
        subjectName: String,
        topicNames: [String],
        summary: String,
        detailLines: [String],
        sourceReference: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.actionType = actionType
        self.title = title
        self.subjectName = subjectName
        self.topicNames = topicNames
        self.summary = summary
        self.detailLines = detailLines
        self.sourceReference = sourceReference
        self.createdAt = createdAt
    }

    var searchText: String {
        ([title, subjectName, summary] + topicNames + detailLines).joined(separator: " ")
    }
}

private enum ARIAContextSpecStore {
    private static let folderName = "ARIAContextSpecs"
    private static let cacheLock = NSLock()
    private static var cachedRootPath: String?
    private static var cachedSpecs: [ARIAActionSpec]?

    static func write(_ spec: ARIAActionSpec) {
        guard let rootURL = rootDirectoryURL() else { return }

        let typeDirectory = rootURL.appendingPathComponent(spec.actionType.rawValue, isDirectory: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "\(formatter.string(from: spec.createdAt))_\(spec.id.uuidString).json"
        let fileURL = typeDirectory.appendingPathComponent(fileName)

        do {
            try FileManager.default.createDirectory(at: typeDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(spec)
            try data.write(to: fileURL, options: .atomic)
            cache(spec: spec, forRootPath: rootURL.path)
        } catch {
            print("Failed to write ARIA spec: \(error)")
        }
    }

    static func recentSpecs(limit: Int) -> [ARIAActionSpec] {
        guard let rootURL = rootDirectoryURL() else { return [] }
        let rootPath = rootURL.path

        if let cached = cachedSpecs(forRootPath: rootPath) {
            return Array(cached.prefix(limit))
        }

        let manager = FileManager.default
        guard let enumerator = manager.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var specs: [ARIAActionSpec] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "json" else { continue }
            guard let data = try? Data(contentsOf: url),
                  let spec = try? decoder.decode(ARIAActionSpec.self, from: data) else { continue }
            specs.append(spec)
        }

        let sortedSpecs = specs.sorted { $0.createdAt > $1.createdAt }
        storeCachedSpecs(sortedSpecs, forRootPath: rootPath)
        return Array(sortedSpecs.prefix(limit))
    }

    private static func rootDirectoryURL() -> URL? {
        let manager = FileManager.default
        if let appSupport = try? manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            return appSupport.appendingPathComponent("IBVault", isDirectory: true)
                .appendingPathComponent(folderName, isDirectory: true)
        }

        return manager.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true)
    }

    private static func cachedSpecs(forRootPath rootPath: String) -> [ARIAActionSpec]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        guard cachedRootPath == rootPath else {
            cachedRootPath = rootPath
            cachedSpecs = nil
            return nil
        }

        return cachedSpecs
    }

    private static func storeCachedSpecs(_ specs: [ARIAActionSpec], forRootPath rootPath: String) {
        cacheLock.lock()
        cachedRootPath = rootPath
        cachedSpecs = specs
        cacheLock.unlock()
    }

    private static func cache(spec: ARIAActionSpec, forRootPath rootPath: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if cachedRootPath != rootPath {
            cachedRootPath = rootPath
            cachedSpecs = [spec]
            return
        }

        if cachedSpecs == nil {
            cachedSpecs = [spec]
            return
        }

        cachedSpecs?.append(spec)
        cachedSpecs?.sort { $0.createdAt > $1.createdAt }
    }
}

private struct ARIAMaterialCollection {
    let name: String
    let subject: String
    let subfolder: String
    let description: String
}

private struct ARIAMaterialMatch {
    let collection: ARIAMaterialCollection
    let topFiles: [String]
    let score: Int
}

private enum ARIAMaterialsCatalog {
    private static let cacheLock = NSLock()
    private static var cachedRootPath: String?
    private static var cachedFilesByCollection: [String: [String]] = [:]
    private static let collections: [ARIAMaterialCollection] = [
        .init(name: "IB Documents", subject: "All Subjects", subfolder: "IB DOCUMENTS", description: "Official IB subject guides, mark schemes, examiner reports, and formula booklets."),
        .init(name: "revision-town", subject: "All Subjects", subfolder: "revision-town", description: "High-yield revision resources across multiple IB subjects."),
        .init(name: "Math AI Resources", subject: "Mathematics", subfolder: "A I", description: "Practice-heavy IB Mathematics AI resources and notes."),
        .init(name: "Bananaomics", subject: "Economics", subfolder: "Bananaomics", description: "IB Economics notes, diagrams, and evaluation-focused materials."),
        .init(name: "Bioknowledgy", subject: "Biology", subfolder: "Bioknowledgy", description: "IB Biology topic explanations and syllabus-aligned notes."),
        .init(name: "catalyst IB", subject: "Chemistry", subfolder: "catalyst IB", description: "IB Chemistry concept summaries and exam practice resources."),
        .init(name: "English Guys", subject: "English", subfolder: "English Guys", description: "IB English literary analysis and paper strategy materials."),
        .init(name: "ibGenius", subject: "Business Management", subfolder: "ibGenius", description: "IB Business Management notes, case-study prep, and exam drills."),
        .init(name: "LitLearn", subject: "Literature", subfolder: "LitLearn", description: "Literature analysis resources and essay-planning support."),
        .init(name: "Nail IB", subject: "Physics", subfolder: "Nail IB", description: "IB Physics worked examples and concept walkthroughs.")
    ]

    static func relevantMatches(queryText: String, keywords: Set<String>, limit: Int) -> [ARIAMaterialMatch] {
        let ranked: [ARIAMaterialMatch] = collections.compactMap { collection -> ARIAMaterialMatch? in
            let score = relevanceScore(for: collection, queryText: queryText, keywords: keywords)
            let subjectMatch = queryText.contains(collection.subject.lowercased())
            guard score > 0 || subjectMatch else { return nil }

            let files = materialFiles(for: collection)
            let rankedFiles = files
                .sorted {
                    let lhsScore = fileScore(for: $0, keywords: keywords)
                    let rhsScore = fileScore(for: $1, keywords: keywords)
                    if lhsScore == rhsScore {
                        return $0.localizedStandardCompare($1) == .orderedAscending
                    }
                    return lhsScore > rhsScore
                }

            return ARIAMaterialMatch(collection: collection, topFiles: Array(rankedFiles.prefix(6)), score: score)
        }
        .sorted {
            if $0.score == $1.score {
                return $0.collection.name < $1.collection.name
            }
            return $0.score > $1.score
        }

        return Array(ranked.prefix(limit))
    }

    private static func relevanceScore(for collection: ARIAMaterialCollection, queryText: String, keywords: Set<String>) -> Int {
        let haystack = [collection.name, collection.subject, collection.subfolder, collection.description]
            .joined(separator: " ")
            .lowercased()

        var score = keywords.reduce(0) { partial, keyword in
            partial + (haystack.contains(keyword) ? 8 : 0)
        }

        if queryText.contains(collection.subject.lowercased()) { score += 20 }
        if queryText.contains("past paper") || queryText.contains("markscheme") { score += collection.name == "IB Documents" ? 12 : 0 }
        if queryText.contains("formula") { score += collection.subfolder == "IB DOCUMENTS" ? 12 : 0 }
        return score
    }

    private static func fileScore(for fileName: String, keywords: Set<String>) -> Int {
        let haystack = fileName.lowercased()
        return keywords.reduce(0) { partial, keyword in
            partial + (haystack.contains(keyword) ? 1 : 0)
        }
    }

    private static func materialFiles(for collection: ARIAMaterialCollection) -> [String] {
        guard let rootURL = materialsRootURL() else { return [] }
        let rootPath = rootURL.path

        if let cached = cachedFiles(for: collection, rootPath: rootPath) {
            return cached
        }

        let baseURL = rootURL.appendingPathComponent(collection.subfolder, isDirectory: true)

        let manager = FileManager.default
        guard let enumerator = manager.enumerator(at: baseURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        var files: [String] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true else { continue }
            files.append(url.lastPathComponent)
            if files.count >= 24 { break }
        }

        storeCachedFiles(files, for: collection, rootPath: rootPath)
        return files
    }

    private static func materialsRootURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "Materials", withExtension: nil) {
            return bundled
        }

        let fileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = fileURL.deletingLastPathComponent().deletingLastPathComponent()
        let localURL = projectRoot.appendingPathComponent("Materials", isDirectory: true)
        return FileManager.default.fileExists(atPath: localURL.path) ? localURL : nil
    }

    private static func cachedFiles(for collection: ARIAMaterialCollection, rootPath: String) -> [String]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if cachedRootPath != rootPath {
            cachedRootPath = rootPath
            cachedFilesByCollection = [:]
            return nil
        }

        return cachedFilesByCollection[collection.subfolder]
    }

    private static func storeCachedFiles(_ files: [String], for collection: ARIAMaterialCollection, rootPath: String) {
        cacheLock.lock()
        cachedRootPath = rootPath
        cachedFilesByCollection[collection.subfolder] = files
        cacheLock.unlock()
    }
}
