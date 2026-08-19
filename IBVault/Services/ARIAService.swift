import Foundation
import SwiftData
import SwiftUI

@MainActor
enum ARIAServiceFactory {
    static func make() -> ARIAService {
        ARIAService()
    }
}

@Observable
@MainActor
class ARIAService {
    var isLoading = false
    var currentStatus = ""
    var suggestedPrompts: [String] = []
    private var activeRequest: Task<Void, Never>?
    private var activeRequestID: UUID?
    private var retryActionSummary: (
        sessionID: UUID,
        prompt: String,
        summary: ActionExecutionSummary
    )?

    private let tokenThreshold = 12000
    private let maxMemoryItems = 8
    private let maxContextSubjects = 4
    private let maxHistoryMessages = 24
    private let maxSnapshotReviewSessions = 160
    private let maxCompactionMessages = 120
    private let minMessagesBeforeCompaction = 16
    private let minMessagesToKeepAfterCompaction = 8
    private let streamUpdateCharacterStride = 384
    private let streamUpdateInterval: TimeInterval = 0.22

    /// The typed catalog of app tools ARIA can execute. A raw-string action
    /// type would let typos silently produce no-op actions; an exhaustive enum
    /// forces every case to be handled in the executor. Unknown strings from the
    /// model decode to `.unknown` (via `init(from:)`) and are rejected.
    private enum AppActionType: String, Codable, Sendable {
        case createStudySession = "create_study_session"
        case assignWeakestStudySession = "assign_weakest_study_session"
        case createReviewSession = "create_review_session"
        case rescheduleStudySession = "reschedule_study_session"
        case completeStudySession = "complete_study_session"
        case cancelStudySession = "cancel_study_session"
        case generateFlashcards = "generate_flashcards"
        case createFlashcard = "create_flashcard"
        case editFlashcard = "edit_flashcard"
        case deleteFlashcards = "delete_flashcards"
        case importGrades = "import_grades"
        case addGrade = "add_grade"
        case editGrade = "edit_grade"
        case deleteGrade = "delete_grade"
        case recordAssessment = "record_assessment"
        case deleteAssessment = "delete_assessment"
        case setMastery = "set_mastery"
        case updateProgress = "update_progress"
        case updateUnitState = "update_unit_state"
        case updateProfile = "update_profile"
        case createSubject = "create_subject"
        case updateSubject = "update_subject"
        case deleteSubject = "delete_subject"
        case saveMemory = "save_memory"
        case editMemory = "edit_memory"
        case deleteMemory = "delete_memory"
        case deleteOldChats = "delete_old_chats"
        case deleteStudyPlan = "delete_study_plan"
        case unknown = "unknown"

        /// Lenient decode: unrecognised model output maps to `.unknown` instead
        /// of failing the whole action's JSON decode.
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            self = AppActionType(rawValue: rawValue) ?? .unknown
        }

        /// Tools that permanently remove data and therefore require the learner
        /// to have explicitly asked for that change in the current message.
        var isDestructive: Bool {
            switch self {
            case .cancelStudySession, .deleteFlashcards, .deleteGrade, .deleteAssessment,
                 .deleteSubject, .deleteMemory, .deleteOldChats, .deleteStudyPlan:
                return true
            case .createStudySession, .assignWeakestStudySession, .createReviewSession,
                 .rescheduleStudySession, .completeStudySession, .generateFlashcards,
                 .createFlashcard, .editFlashcard, .importGrades, .addGrade,
                 .editGrade, .recordAssessment, .setMastery, .updateProgress, .updateUnitState,
                 .updateProfile, .createSubject, .updateSubject, .saveMemory,
                 .editMemory, .unknown:
                return false
            }
        }
    }

    private struct PlannedAppAction: Codable {
        let type: AppActionType
        let subjectName: String?
        let topics: [String]?
        let subtopics: [String]?
        let scheduledAt: String?
        let durationMinutes: Int?
        let cardCount: Int?
        let flashcardOnly: Bool?
        let flashcardTargetCount: Int?
        let flashcardDifficulty: String?
        let masteryLevel: String?
        let dailyGoal: Int?
        let targetIBScore: Int?
        let minutesStudied: Double?
        /// Retained so previously stored payloads still decode. Never read:
        /// XP is priced by XPCalculator, not by the model.
        let xpEarned: Int?
        let notes: String?
        let memoryCategory: String?
        let searchText: String?
        let frontText: String?
        let backText: String?
        let assessmentTitle: String?
        let assessmentDate: String?
        let assessmentType: String?
        let category: String?
        let percentage: Double?
        let component: String?
        let score: Int?
        let predictedGrade: Int?
        let achievedPoints: Double?
        let maxPoints: Double?
        let weightPercent: Double?
        let sourceName: String?
        let termName: String?
        let name: String?
        let level: String?
        let accentColorHex: String?
        let examDate: String?
        let hint: String?
        let difficulty: String?
        let cognitiveSkill: String?
        let cardID: UUID?
        let gradeID: UUID?
        let memoryID: UUID?
        let studyIntensity: String?
        let ibYear: String?
        let studentName: String?
        let notificationHour: Int?
        let notificationMinute: Int?
        let streakFreezes: Int?
        let unitName: String?
        let isTaught: Bool?
        let clearMastery: Bool?
        let olderThanDays: Int?

        init(
            type: AppActionType,
            subjectName: String? = nil,
            topics: [String]? = nil,
            subtopics: [String]? = nil,
            masteryLevel: String? = nil,
            minutesStudied: Double? = nil,
            notes: String? = nil
        ) {
            self.type = type
            self.subjectName = subjectName
            self.topics = topics
            self.subtopics = subtopics
            self.scheduledAt = nil
            self.durationMinutes = nil
            self.cardCount = nil
            self.flashcardOnly = nil
            self.flashcardTargetCount = nil
            self.flashcardDifficulty = nil
            self.masteryLevel = masteryLevel
            self.dailyGoal = nil
            self.targetIBScore = nil
            self.minutesStudied = minutesStudied
            self.xpEarned = nil
            self.notes = notes
            self.memoryCategory = nil
            self.searchText = nil
            self.frontText = nil
            self.backText = nil
            self.assessmentTitle = nil
            self.assessmentDate = nil
            self.assessmentType = nil
            self.category = nil
            self.percentage = nil
            self.component = nil
            self.score = nil
            self.predictedGrade = nil
            self.achievedPoints = nil
            self.maxPoints = nil
            self.weightPercent = nil
            self.sourceName = nil
            self.termName = nil
            self.name = nil
            self.level = nil
            self.accentColorHex = nil
            self.examDate = nil
            self.hint = nil
            self.difficulty = nil
            self.cognitiveSkill = nil
            self.cardID = nil
            self.gradeID = nil
            self.memoryID = nil
            self.studyIntensity = nil
            self.ibYear = nil
            self.studentName = nil
            self.notificationHour = nil
            self.notificationMinute = nil
            self.streakFreezes = nil
            self.unitName = nil
            self.isTaught = nil
            self.clearMastery = nil
            self.olderThanDays = nil
        }

        var deduplicationKey: String {
            var parts: [String] = [type.rawValue, subjectName ?? ""]
            parts.append((topics ?? []).joined(separator: "|"))
            parts.append((subtopics ?? []).joined(separator: "|"))
            parts.append(scheduledAt ?? "")
            parts.append(masteryLevel ?? "")
            parts.append(searchText ?? "")
            parts.append(frontText ?? "")
            parts.append(backText ?? "")
            parts.append(assessmentTitle ?? "")
            parts.append(name ?? "")
            parts.append(cardID?.uuidString ?? "")
            parts.append(gradeID?.uuidString ?? "")
            parts.append(memoryID?.uuidString ?? "")
            parts.append(olderThanDays.map(String.init) ?? "")
            return parts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .joined(separator: "::")
        }
    }

    private struct ActionExecutionSummary {
        let completed: [String]
        let failed: [String]
        let notes: [String]

        var isEmpty: Bool {
            completed.isEmpty && failed.isEmpty && notes.isEmpty
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
            if !notes.isEmpty {
                lines.append("Notes:")
                lines.append(contentsOf: notes.map { "- \($0)" })
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
            "Clean up weak flashcards and assign me a session from my weakest topic",
            "Import my ManageBac grades and estimate my DP1 average"
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
            let dueSubjects = subjects.compactMap { subject -> (subject: Subject, count: Int)? in
                let count = subject.cards.lazy.filter { $0.nextReviewDate <= now }.count
                return count > 0 ? (subject, count) : nil
            }

            if let mostDue = dueSubjects.max(by: { $0.count < $1.count }) {
                prompts.append("Review \(mostDue.count) cards from \(mostDue.subject.name)")
            }
        }
        
        // Always include general prompts
        prompts.append(contentsOf: [
            "Make me a weekly study plan",
            "What's my weakest topic?",
            "Quiz me!"
        ])
        
        var seenPrompts = Set<String>()
        suggestedPrompts = Array(prompts.filter { seenPrompts.insert($0).inserted }.prefix(4))
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
        persistUserMessage: Bool = true,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (any Error, UUID?) -> Void
    ) {
        guard activeRequestID == nil else { return }
        let trimmedMessage = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }

        let requestID = UUID()
        let requestProvider = AIConfiguration.provider
        activeRequestID = requestID
        isLoading = true
        currentStatus = "Preparing your study context"

        if persistUserMessage {
            retryActionSummary = nil
            let userChat = ChatMessage(role: .user, content: trimmedMessage, sessionID: session.id)
            updateSession(session, withUserMessage: trimmedMessage)
            context.insert(userChat)
            do {
                try context.save()
            } catch {
                finishRequest(requestID)
                onError(error, nil)
                return
            }
        }

        activeRequest = Task { [weak self] in
            guard let self else { return }
            defer { self.finishRequest(requestID) }

            do {
                try Task.checkCancellation()
                let queryProfile = analyzeQuery(trimmedMessage)
                let loggingContext = inferredLoggingContext(context: context, queryProfile: queryProfile)
                self.currentStatus = "Checking requested app changes"
                let actionSummary: ActionExecutionSummary
                if !persistUserMessage {
                    if let cachedSummary = self.retryActionSummary,
                       cachedSummary.sessionID == session.id,
                       cachedSummary.prompt == trimmedMessage {
                        actionSummary = cachedSummary.summary
                    } else {
                        // A relaunched retry cannot prove which app actions already committed.
                        // Reuse the saved prompt without risking duplicate sessions or cards.
                        actionSummary = ActionExecutionSummary(completed: [], failed: [], notes: [])
                    }
                } else {
                    actionSummary = try await self.planAndExecuteAppActions(
                        for: trimmedMessage,
                        context: context,
                        queryProfile: queryProfile
                    )
                    if !actionSummary.isEmpty {
                        self.retryActionSummary = (
                            sessionID: session.id,
                            prompt: trimmedMessage,
                            summary: actionSummary
                        )
                    }
                }
                try Task.checkCancellation()

                // Build context
                self.currentStatus = "Building your study context"
                var systemPrompt = await buildSystemPrompt(context: context, queryProfile: queryProfile)
                if !actionSummary.isEmpty {
                    systemPrompt += "\n\n\(actionSummary.promptContext)\nReference these concrete changes in your reply briefly before giving any next-step guidance."
                }
                let messages = await buildConversationHistory(context: context, queryProfile: queryProfile, sessionID: session.id)

                var fullResponse = ""

                let stream = AIProviderService.streamContent(
                    messages: messages,
                    systemInstruction: systemPrompt,
                    onStatus: { [weak self] status in
                        Task { @MainActor in
                            self?.currentStatus = status
                        }
                    }
                )

                var lastStreamUpdate = Date.distantPast
                var pendingStreamCharacters = 0

                for try await token in stream {
                    try Task.checkCancellation()
                    Self.appendStreamChunk(token, to: &fullResponse)
                    pendingStreamCharacters += token.count

                    let now = Date()
                    guard pendingStreamCharacters >= self.streamUpdateCharacterStride ||
                            now.timeIntervalSince(lastStreamUpdate) >= self.streamUpdateInterval else {
                        continue
                    }

                    pendingStreamCharacters = 0
                    lastStreamUpdate = now
                    onToken(fullResponse)
                }

                try Task.checkCancellation()
                onToken(fullResponse)

                let finalizedResponse = Self.finalizeAssistantResponse(fullResponse)
                guard !finalizedResponse.isEmpty else {
                    throw AIProviderError.emptyResponse
                }

                // Save assistant response
                let modelChat = ChatMessage(role: .model, content: finalizedResponse, sessionID: session.id)
                context.insert(modelChat)
                self.updateSession(session, withAssistantReply: finalizedResponse)
                do {
                    try context.save()
                    self.retryActionSummary = nil
                    onComplete(finalizedResponse)
                } catch {
                    context.delete(modelChat)
                    onError(error, nil)
                    return
                }

                Self.recordARIAChatExchange(
                    subjectName: loggingContext.subjectName,
                    topicNames: loggingContext.topicNames,
                    userMessage: trimmedMessage,
                    assistantReply: finalizedResponse,
                    sourceReference: "ARIAService.sendMessage"
                )

                // Check if compaction needed
                await checkAndCompact(context: context, sessionID: session.id)

            } catch is CancellationError {
                return
            } catch {
                let failureID = self.persistFailure(
                    error,
                    context: context,
                    session: session,
                    provider: requestProvider
                )
                onError(error, failureID)
            }
        }
    }

    @discardableResult
    func cancelCurrentRequest(
        context: ModelContext? = nil,
        session: ARIAChatSession? = nil,
        provider: AIProviderKind? = nil
    ) -> UUID? {
        activeRequest?.cancel()
        activeRequest = nil
        activeRequestID = nil
        isLoading = false
        currentStatus = ""

        guard let context, let session, let provider else { return nil }
        return persistFailureMessage(
            role: .cancelled(provider: provider),
            content: "Response stopped. Your message is saved and can be retried.",
            context: context,
            session: session
        )
    }

    private func finishRequest(_ requestID: UUID) {
        guard activeRequestID == requestID else { return }
        activeRequest = nil
        activeRequestID = nil
        isLoading = false
        currentStatus = ""
    }

    @discardableResult
    private func persistFailure(
        _ error: any Error,
        context: ModelContext,
        session: ARIAChatSession,
        provider: AIProviderKind
    ) -> UUID? {
        let needsAuthentication: Bool
        if let providerError = error as? AIProviderError,
           case .codexNotAuthenticated = providerError {
            needsAuthentication = true
        } else {
            needsAuthentication = false
        }

        return persistFailureMessage(
            role: .failure(provider: provider, needsAuthentication: needsAuthentication),
            content: error.localizedDescription,
            context: context,
            session: session
        )
    }

    @discardableResult
    private func persistFailureMessage(
        role: ChatMessageRole,
        content: String,
        context: ModelContext,
        session: ARIAChatSession
    ) -> UUID? {
        let failureMessage = ChatMessage(role: role, content: content, sessionID: session.id)
        context.insert(failureMessage)
        guard !session.isDeleted else {
            do {
                try context.save()
                return failureMessage.id
            } catch {
                context.delete(failureMessage)
                return nil
            }
        }
        session.updatedAt = Date()

        do {
            try context.save()
            return failureMessage.id
        } catch {
            context.delete(failureMessage)
            return nil
        }
    }

    @MainActor
    private func planAndExecuteAppActions(
        for userMessage: String,
        context: ModelContext,
        queryProfile: QueryProfile
    ) async throws -> ActionExecutionSummary {
        guard shouldAttemptAppActions(for: userMessage, queryProfile: queryProfile) else {
            return ActionExecutionSummary(completed: [], failed: [], notes: [])
        }

        // Actions run against a scratch context derived from the shared store.
        // Each action commits independently; a failed action's partial state is
        // discarded with the scratch context instead of rolling back the whole
        // app-wide shared context (which previously reverted concurrent UI work
        // and unrelated pending inserts).
        let actionContext = ModelContext(context.container)

        if let directProgressAction = directProgressAction(for: userMessage, context: actionContext) {
            do {
                let summary = try await execute(action: directProgressAction, context: actionContext)
                try actionContext.save()
                return ActionExecutionSummary(completed: summary.map { [$0] } ?? [], failed: [], notes: [])
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return ActionExecutionSummary(completed: [], failed: [error.localizedDescription], notes: [])
            }
        }

        let planningPrompt = buildActionPlanningPrompt(userMessage: userMessage, context: actionContext)
        let response = try await AIProviderService.generateContent(
            messages: [GeminiMessage(role: "user", text: planningPrompt)],
            systemInstruction: """
            You convert user requests into safe app actions for an IB study app.
            Return ONLY raw JSON as an array.
            Use [] when the user is not explicitly asking for the app to change data.
            Supported action types:
            - create_study_session, assign_weakest_study_session, create_review_session
            - reschedule_study_session, complete_study_session, cancel_study_session (destructive)
            - generate_flashcards, create_flashcard, edit_flashcard, delete_flashcards (destructive)
            - import_grades, add_grade, edit_grade, delete_grade (destructive)
            - record_assessment, delete_assessment (destructive)
            - set_mastery, update_progress, update_unit_state
            - update_profile, create_subject, update_subject, delete_subject (destructive)
            - save_memory, edit_memory, delete_memory (destructive)
            - delete_study_plan (destructive)
            Rules:
            - Only create actions for explicit edit/create/assign/generate/set/update/delete requests.
            - Never execute a destructive action (marked destructive above) unless the learner clearly asked for that specific change in this message.
            - Use set_mastery when the learner rates their mastery of a real topic/subunit or wants a specific card marked at a level; include a real topic or subtopic, never an entire subject.
            - Use update_progress when the learner reports study time or rates mastery AND you want to log minutes/XP; keep topics/subtopics real.
            - Never infer mastery from ARIA explaining a concept, answering a question, or judging the learner's writing.
            - Put a short user-evidence summary in notes for update_progress and set_mastery.
            - Use import_grades when the user pastes report-card, ManageBac, assessment, marks, or grade-export data; use add_grade/edit_grade for single assessment updates.
            - Use record_assessment for scored school evidence that should calibrate mastery. Include assessmentTitle plus percentage, score, or achievedPoints/maxPoints; include real topics/subtopics only when the evidence belongs to them.
            - Prefer concrete subject names that exist in the provided app state.
            - Use ISO-8601 timestamps for scheduledAt and examDate.
            - Keep topics/subtopics arrays empty rather than inventing values.
            - When the learner requests a whole topic, leave subtopics empty so the app can cover every real curriculum subunit.
            - Use frontText/backText when creating or editing flashcards; use searchText only when the user gives identifying wording for a card.
            - For create_flashcard include topicName and optional subtopic, hint, difficulty (Foundation/Standard/Exam/Stretch), and cognitiveSkill (Recall/Explain/Apply/Analyze/Evaluate).
            - For grade actions use component, assessmentTitle, score (1-7), predictedGrade, achievedPoints, maxPoints, weightPercent, sourceName, termName, and notes for feedback. For assessment actions use assessmentTitle, assessmentDate, assessmentType, category, percentage, score, achievedPoints, maxPoints, topics, and subtopics.
            - For subject actions use name, level (SL/HL), accentColorHex (e.g. "#10B981"), and examDate.
            - For profile actions use studentName, dailyGoal, targetIBScore (1-45), notificationHour (0-23), notificationMinute (0-59), studyIntensity, ibYear.
            - For memory actions use memoryCategory, notes (the content), and searchText to identify existing memories to edit or delete.
            """
        )

        return try await executeToolPlan(
            response: response,
            userMessage: userMessage,
            actionContext: actionContext
        )
    }

    /// E2E test seam: runs the exact post-planning pipeline (parse, dedupe,
    /// destructive gate, scratch-context execution) that `planAndExecuteAppActions`
    /// uses after the model returns its JSON plan. Kept internal so the tool
    /// catalog can be exercised against synthetic model output without a live
    /// Gemini key.
    @MainActor
    func applyAppToolPlan(
        _ response: String,
        userMessage: String,
        context: ModelContext
    ) async throws -> (completed: [String], failed: [String], notes: [String]) {
        let actionContext = ModelContext(context.container)
        let summary = try await executeToolPlan(
            response: response,
            userMessage: userMessage,
            actionContext: actionContext
        )
        return (summary.completed, summary.failed, summary.notes)
    }

    @MainActor
    private func executeToolPlan(
        response: String,
        userMessage: String,
        actionContext: ModelContext
    ) async throws -> ActionExecutionSummary {
        var seenActions = Set<String>()
        let actions = parsePlannedAppActions(from: response).filter {
            seenActions.insert($0.deduplicationKey).inserted
        }
        guard !actions.isEmpty else {
            return ActionExecutionSummary(completed: [], failed: [], notes: [])
        }

        var completed: [String] = []
        var failed: [String] = []
        var notes: [String] = []

        for action in actions.prefix(2) {
            try Task.checkCancellation()

            if action.type.isDestructive {
                guard userMessageConfirmsDestructiveAction(userMessage, type: action.type) else {
                    failed.append("\(action.type.rawValue) skipped — the learner did not clearly confirm that destructive change in this message.")
                    continue
                }
            }

            do {
                if let summary = try await execute(action: action, context: actionContext) {
                    try actionContext.save()
                    completed.append(summary)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failed.append(error.localizedDescription)
            }
        }

        if actions.count > 2 {
            notes.append("ARIA limited this turn to 2 actions; \(actions.count - 2) additional planned change\(actions.count - 2 == 1 ? "" : "s") were skipped.")
        }

        return ActionExecutionSummary(completed: completed, failed: failed, notes: notes)
    }

    private func userMessageConfirmsDestructiveAction(_ userMessage: String, type: AppActionType) -> Bool {
        let normalized = userMessage.lowercased()
        let consentPhrases: [String]
        switch type {
        case .deleteFlashcards:
            consentPhrases = ["delete", "remove", "clear", "erase", "get rid", "clean"]
        case .cancelStudySession:
            consentPhrases = ["cancel", "remove", "delete", "drop"]
        case .deleteGrade, .deleteAssessment, .deleteSubject, .deleteMemory, .deleteOldChats, .deleteStudyPlan:
            consentPhrases = ["delete", "remove", "erase", "get rid"]
        default:
            return false
        }
        return containsExplicitConsent(normalized, phrases: consentPhrases)
    }

    /// True when the message contains a destructive request that is not negated.
    /// A bare substring check would treat "do not delete my cards" or "don't
    /// cancel" as consent, so a consent phrase immediately preceded by a
    /// negation token does not count. Each occurrence is inspected on its own,
    /// so a negated occurrence in one clause does not suppress a separate
    /// affirmative occurrence elsewhere in the message.
    private func containsExplicitConsent(_ normalized: String, phrases: [String]) -> Bool {
        let negationSuffixes = ["don't", "dont", "do not", "not", "never", "n't", "no"]
        for phrase in phrases {
            var searchStart = normalized.startIndex
            while let range = normalized.range(of: phrase, options: [], range: searchStart..<normalized.endIndex) {
                let preceding = normalized[..<range.lowerBound]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let negated = negationSuffixes.contains { preceding.hasSuffix($0) }
                if !negated { return true }
                searchStart = range.upperBound
            }
        }
        return false
    }

    private func shouldAttemptAppActions(for userMessage: String, queryProfile: QueryProfile) -> Bool {
        let normalized = userMessage.lowercased()
        if containsAny(normalized, phrases: [
            "create", "schedule", "assign", "set up", "set", "update", "edit",
            "change", "move", "reschedule", "generate", "make", "mark", "log",
            "import", "upload", "sync", "paste", "studied", "worked on", "finished",
            "completed", "mastered", "proficient", "developing", "novice",
            "delete", "remove", "cancel", "clear", "erase", "get rid", "clean up",
            "add", "record", "note down", "remember", "rate"
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
    private func directProgressAction(for userMessage: String, context: ModelContext) -> PlannedAppAction? {
        let normalized = userMessage.lowercased()
        let masteryLevel = explicitlyReportedMasteryLevel(in: normalized)

        let hasWorkStatement = containsAny(normalized, phrases: [
            "studied", "worked on", "spent", "log", "finished", "completed"
        ])
        let minutes = hasWorkStatement ? parsedStudyMinutes(from: userMessage) : nil
        guard masteryLevel != nil || minutes != nil else { return nil }

        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        let mentionedSubjects = subjects.filter { normalized.contains($0.name.lowercased()) }
        var subject = mentionedSubjects.count == 1 ? mentionedSubjects.first : nil

        struct ScopeMatch {
            let subject: Subject
            let topic: String
            let subtopic: String?
        }
        var matches: [ScopeMatch] = []
        for candidate in subjects {
            for unit in SyllabusSeeder.curriculum(for: candidate.name, level: candidate.level) {
                for topic in unit.topics {
                    let matchingSubtopics = topic.subtopics.filter { normalized.contains($0.lowercased()) }
                    if !matchingSubtopics.isEmpty {
                        matches.append(contentsOf: matchingSubtopics.map {
                            ScopeMatch(subject: candidate, topic: topic.name, subtopic: $0)
                        })
                    } else if normalized.contains(topic.name.lowercased()) {
                        matches.append(ScopeMatch(subject: candidate, topic: topic.name, subtopic: nil))
                    }
                }
            }
        }

        let matchedSubjectIDs = Set(matches.map { $0.subject.id })
        if subject == nil, matchedSubjectIDs.count == 1 {
            subject = matches.first?.subject
        }
        guard let subject else { return nil }

        let subjectMatches = matches.filter { $0.subject.id == subject.id }
        var seenTopics = Set<String>()
        let topics = subjectMatches.map(\.topic).filter { seenTopics.insert($0.lowercased()).inserted }
        var seenSubtopics = Set<String>()
        let subtopics = subjectMatches.compactMap(\.subtopic).filter {
            seenSubtopics.insert($0.lowercased()).inserted
        }

        if masteryLevel != nil && topics.isEmpty && subtopics.isEmpty {
            return nil
        }

        return PlannedAppAction(
            type: .updateProgress,
            subjectName: subject.name,
            topics: topics,
            subtopics: subtopics,
            masteryLevel: masteryLevel,
            minutesStudied: minutes,
            notes: "Recorded from the learner's explicit statement."
        )
    }

    private func explicitlyReportedMasteryLevel(in normalized: String) -> String? {
        let controlVerbs = ["mark", "set", "record", "update"]
        let hasControlVerb = containsAny(normalized, phrases: controlVerbs)
        if containsAny(normalized, phrases: [
            "not mastered", "not proficient", "not developing", "not a novice",
            "haven't mastered", "have not mastered"
        ]) {
            return nil
        }

        if containsAny(normalized, phrases: ["i mastered", "i have mastered", "i've mastered"]) ||
            (hasControlVerb && normalized.contains("mastered")) {
            return "mastered"
        }
        if containsAny(normalized, phrases: ["i am proficient", "i'm proficient", "i feel proficient"]) ||
            (hasControlVerb && normalized.contains("proficient")) {
            return "proficient"
        }
        if containsAny(normalized, phrases: ["i am developing", "i'm developing", "i feel developing"]) ||
            (hasControlVerb && normalized.contains("developing")) {
            return "developing"
        }
        if containsAny(normalized, phrases: ["i am a novice", "i'm a novice", "i feel like a novice"]) ||
            (hasControlVerb && normalized.contains("novice")) {
            return "novice"
        }
        return nil
    }

    private func parsedStudyMinutes(from text: String) -> Double? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)\b(\d+(?:\.\d+)?)\s*(minutes?|mins?|m|hours?|hrs?|h)\b"#
        ) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = Double(text[valueRange]) else {
            return nil
        }
        let unit = text[unitRange].lowercased()
        return unit.hasPrefix("h") ? value * 60 : value
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
        lines.append("Return JSON array with fields: type, subjectName, topics, subtopics, scheduledAt, durationMinutes, cardCount, flashcardOnly, flashcardTargetCount, flashcardDifficulty, masteryLevel, dailyGoal, targetIBScore, minutesStudied, xpEarned, notes, memoryCategory, searchText, frontText, backText, hint, difficulty, cognitiveSkill, cardID, gradeID, memoryID, assessmentTitle, assessmentDate, assessmentType, category, percentage, component, score, predictedGrade, achievedPoints, maxPoints, weightPercent, sourceName, termName, name, level, accentColorHex, examDate, studyIntensity, ibYear, studentName, notificationHour, notificationMinute, streakFreezes, unitName, isTaught, clearMastery, olderThanDays.")
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
        case .createStudySession:
            return try executeCreateStudySession(action: action, context: context)
        case .assignWeakestStudySession:
            return try executeAssignWeakestStudySession(action: action, context: context)
        case .createReviewSession:
            return try executeCreateReviewSession(action: action, context: context)
        case .rescheduleStudySession:
            return try executeRescheduleStudySession(action: action, context: context)
        case .completeStudySession:
            return try executeCompleteStudySession(action: action, context: context)
        case .cancelStudySession:
            return try executeCancelStudySession(action: action, context: context)
        case .generateFlashcards:
            return try await executeGenerateFlashcards(action: action, context: context)
        case .createFlashcard:
            return try executeCreateFlashcard(action: action, context: context)
        case .editFlashcard:
            return try executeEditFlashcard(action: action, context: context)
        case .deleteFlashcards:
            return try executeDeleteFlashcards(action: action, context: context)
        case .importGrades:
            return try executeImportGrades(action: action, context: context)
        case .addGrade:
            return try executeAddGrade(action: action, context: context)
        case .editGrade:
            return try executeEditGrade(action: action, context: context)
        case .deleteGrade:
            return try executeDeleteGrade(action: action, context: context)
        case .recordAssessment:
            return try executeRecordAssessment(action: action, context: context)
        case .deleteAssessment:
            return try executeDeleteAssessment(action: action, context: context)
        case .setMastery:
            return try executeSetMastery(action: action, context: context)
        case .updateProgress:
            return try executeUpdateProgress(action: action, context: context)
        case .updateUnitState:
            return try executeUpdateUnitState(action: action, context: context)
        case .updateProfile:
            return try executeUpdateProfile(action: action, context: context)
        case .createSubject:
            return try executeCreateSubject(action: action, context: context)
        case .updateSubject:
            return try executeUpdateSubject(action: action, context: context)
        case .deleteSubject:
            return try executeDeleteSubject(action: action, context: context)
        case .saveMemory:
            return try executeSaveMemory(action: action, context: context)
        case .editMemory:
            return try executeEditMemory(action: action, context: context)
        case .deleteMemory:
            return try executeDeleteMemory(action: action, context: context)
        case .deleteOldChats:
            return try executeDeleteOldChats(action: action, context: context)
        case .deleteStudyPlan:
            return try executeDeleteStudyPlan(action: action, context: context)
        case .unknown:
            return nil
        }
    }

    @MainActor
    private func executeCreateStudySession(action: PlannedAppAction, context: ModelContext) throws -> String {
        guard let subject = resolveSubject(named: action.subjectName, context: context) else {
            throw NSError(domain: "ARIAService", code: 1, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find the subject to create that study session."])
        }

        let topics = sanitizedTopics(action.topics, subjectName: subject.name, subjectLevel: subject.level)
        guard !topics.isEmpty else {
            throw NSError(domain: "ARIAService", code: 2, userInfo: [NSLocalizedDescriptionKey: "ARIA needs at least one valid topic to create a study session."])
        }

        let scheduledDate = parseScheduledDate(action.scheduledAt) ?? defaultScheduledDate()
        let duration = min(max(action.durationMinutes ?? 60, 15), 180)
        let subtopics = sanitizedSubtopics(action.subtopics, subjectName: subject.name, subjectLevel: subject.level, topics: topics)

        let plan = StudyPlan(
            subjectName: subject.name,
            topicName: topics.joined(separator: ", "),
            subtopicName: subtopics.joined(separator: ", "),
            planMarkdown: action.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            scheduledDate: scheduledDate,
            durationMinutes: duration,
            prepareFlashcards: action.flashcardOnly == true || action.flashcardTargetCount != nil,
            flashcardOnly: action.flashcardOnly ?? false,
            flashcardTargetCount: action.flashcardTargetCount,
            flashcardDifficulty: CardDifficulty.allCases.first { $0.rawValue.caseInsensitiveCompare(action.flashcardDifficulty ?? "") == .orderedSame }
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
        let subtopics = sanitizedSubtopics(action.subtopics, subjectName: subject.name, subjectLevel: subject.level, topics: topics)
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

        let requestedTopics = sanitizedTopics(action.topics, subjectName: subject.name, subjectLevel: subject.level)
        let topics = requestedTopics.isEmpty
            ? Array(uniqueWeakTopicNames(for: subject).prefix(2))
            : requestedTopics
        guard !topics.isEmpty else {
            throw NSError(domain: "ARIAService", code: 13, userInfo: [NSLocalizedDescriptionKey: "ARIA could not determine which topics to review."])
        }

        let subtopics = sanitizedSubtopics(action.subtopics, subjectName: subject.name, subjectLevel: subject.level, topics: topics)
        let scope = StudyScope(
            subjectName: subject.name,
            unitNames: SyllabusSeeder.unitNames(for: subject.name, topicNames: topics),
            topicNames: topics,
            subtopicNames: subtopics
        )
        let now = IBLocalClock.now
        let matching = subject.cards.filter { scope.matches($0) }
            .sorted { $0.nextReviewDate < $1.nextReviewDate }
        let queued = Array(matching.prefix(ReviewDailyLimitPolicy.maximumCards))
        guard !queued.isEmpty else {
            throw NSError(domain: "ARIAService", code: 13, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find saved flashcards for that review scope."])
        }
        for card in queued where card.nextReviewDate > now {
            card.nextReviewDate = now
        }

        return "Queued \(queued.count) saved flashcard\(queued.count == 1 ? "" : "s") for \(subject.name). They are available in today's review queue without adding a calendar session."
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
        let minutes = Double(min(max(action.durationMinutes ?? plan.durationMinutes, 1), 180))
        let xp = recordScopedStudyWork(
            subjectName: plan.subjectName,
            topics: plan.selectedTopicNames,
            subtopics: plan.selectedSubtopicNames,
            minutes: minutes,
            context: context
        )
        return "Completed the \(plan.subjectName) session on \(plan.selectionSummary), logged \(Int(minutes))m, and recorded \(xp) XP."
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

        let requestedTopics = sanitizedTopics(action.topics, subjectName: subject.name, subjectLevel: subject.level)
        let topics = requestedTopics.isEmpty
            ? Array(uniqueWeakTopicNames(for: subject).prefix(1))
            : requestedTopics
        guard !topics.isEmpty else {
            throw NSError(domain: "ARIAService", code: 11, userInfo: [NSLocalizedDescriptionKey: "ARIA could not determine which topic to generate flashcards for."])
        }
        let count = min(max(action.cardCount ?? 10, 1), 40)
        var generatedTotal = 0
        var alreadyCoveredSubtopics = 0
        var generationFailures: [String] = []

        for topic in topics {
            let validSubtopics = sanitizedSubtopics(action.subtopics, subjectName: subject.name, subjectLevel: subject.level, topics: [topic])
            if validSubtopics.isEmpty,
               let curriculumTopic = SyllabusSeeder.topic(named: topic, in: subject.name, level: subject.level),
               !curriculumTopic.subtopics.isEmpty {
                let targetPerSubtopic = max(
                    Int(ceil(Double(count) / Double(curriculumTopic.subtopics.count))),
                    1
                )
                let result = await CardGeneratorService.generateCoverage(
                    subject: subject,
                    topic: curriculumTopic,
                    cardsPerSubtopic: targetPerSubtopic,
                    context: context,
                    onProgress: { _, _, _ in }
                )
                result.cards.forEach(context.insert)
                generatedTotal += result.cards.count
                alreadyCoveredSubtopics += result.skippedSubtopics
                generationFailures.append(contentsOf: result.failures.map { "\(topic) — \($0)" })

                ARIAService.recordFlashcardGeneration(
                    subjectName: subject.name,
                    topicName: topic,
                    subtopicName: "Full curriculum coverage",
                    generatedCards: result.cards.map { ($0.front, $0.back) },
                    sourceReference: "ARIAService.executeGenerateFlashcards"
                )
                continue
            }

            let generationTargets = validSubtopics.isEmpty ? [""] : validSubtopics
            let cardsPerTarget = max(Int(ceil(Double(count) / Double(generationTargets.count))), 1)
            for subtopic in generationTargets {
                do {
                    let cards = try await CardGeneratorService.generateCards(
                        subject: subject,
                        topicName: topic,
                        subtopic: subtopic,
                        count: cardsPerTarget,
                        context: context
                    )
                    cards.forEach(context.insert)
                    generatedTotal += cards.count

                    ARIAService.recordFlashcardGeneration(
                        subjectName: subject.name,
                        topicName: topic,
                        subtopicName: subtopic,
                        generatedCards: cards.map { ($0.front, $0.back) },
                        sourceReference: "ARIAService.executeGenerateFlashcards"
                    )
                } catch {
                    let label = subtopic.isEmpty ? topic : "\(topic) — \(subtopic)"
                    generationFailures.append("\(label): \(error.localizedDescription)")
                }
            }
        }

        guard generatedTotal > 0 || alreadyCoveredSubtopics > 0 else {
            let detail = generationFailures.first ?? "ARIA did not generate any flashcards for that request."
            throw NSError(domain: "ARIAService", code: 5, userInfo: [NSLocalizedDescriptionKey: detail])
        }

        var summary = generatedTotal > 0
            ? "Generated \(generatedTotal) adaptive flashcards for \(subject.name) across \(topics.joined(separator: ", "))."
            : "The requested \(subject.name) subunits already meet the selected card coverage."
        if alreadyCoveredSubtopics > 0 {
            summary += " \(alreadyCoveredSubtopics) subunits already had enough cards."
        }
        if !generationFailures.isEmpty {
            summary += " \(generationFailures.count) subunits still need attention."
        }
        return summary
    }

    private struct ParsedGradeImport {
        let subject: Subject
        let component: String
        let assessmentTitle: String
        let score: Int
        let predictedGrade: Int?
        let achievedPoints: Double?
        let maxPoints: Double?
        let weightPercent: Double?
        let sourceName: String?
        let termName: String?
        let teacherFeedback: String
    }

    @MainActor
    private func executeImportGrades(action: PlannedAppAction, context: ModelContext) throws -> String {
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        let preferredSubject = resolveSubject(named: action.subjectName, context: context)
        let inlineGrade = buildInlineGradeImport(from: action, preferredSubject: preferredSubject)
        let parsedGrades = inlineGrade.map { [$0] } ?? parseGradeImports(
            from: action.notes ?? "",
            subjects: subjects,
            preferredSubject: preferredSubject,
            defaultSource: action.sourceName
        )

        guard !parsedGrades.isEmpty else {
            throw NSError(domain: "ARIAService", code: 24, userInfo: [NSLocalizedDescriptionKey: "ARIA could not parse any grades from that report. Paste the assessment lines or ManageBac export text and include the subject names if possible."])
        }

        var importedCount = 0
        var touchedSubjects = Set<String>()

        for entry in parsedGrades {
            let titleKey = normalizedGradeTitle(entry.assessmentTitle)
            let sourceKey = (entry.sourceName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let existing = entry.subject.grades.first(where: { grade in
                grade.component.caseInsensitiveCompare(entry.component) == .orderedSame &&
                normalizedGradeTitle(grade.displayTitle) == titleKey &&
                ((grade.sourceName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == sourceKey || sourceKey.isEmpty)
            }) {
                existing.score = entry.score
                existing.predictedGrade = entry.predictedGrade
                existing.assessmentTitle = entry.assessmentTitle
                existing.achievedPoints = entry.achievedPoints
                existing.maxPoints = entry.maxPoints
                existing.weightPercent = entry.weightPercent
                existing.sourceName = entry.sourceName
                existing.termName = entry.termName
                existing.teacherFeedback = entry.teacherFeedback
                existing.date = Date()
            } else {
                context.insert(Grade(
                    component: entry.component,
                    score: entry.score,
                    predictedGrade: entry.predictedGrade,
                    teacherFeedback: entry.teacherFeedback,
                    assessmentTitle: entry.assessmentTitle,
                    achievedPoints: entry.achievedPoints,
                    maxPoints: entry.maxPoints,
                    weightPercent: entry.weightPercent,
                    sourceName: entry.sourceName,
                    termName: entry.termName,
                    subject: entry.subject
                ))
            }
            importedCount += 1
            touchedSubjects.insert(entry.subject.name)
        }

        if let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first {
            profile.reportLastUploaded = Date()
        }

        let subjectSummary = touchedSubjects.sorted().joined(separator: ", ")
        return "Imported \(importedCount) assessment grade\(importedCount == 1 ? "" : "s") for \(subjectSummary). ARIA updated your course averages using the imported assessment weights and marks."
    }

    private func buildInlineGradeImport(from action: PlannedAppAction, preferredSubject: Subject?) -> ParsedGradeImport? {
        guard let subject = preferredSubject,
              action.score != nil || (action.achievedPoints != nil && action.maxPoints != nil) else {
            return nil
        }

        let assessmentTitle = action.assessmentTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let component = normalizedGradeComponent(from: action.component ?? assessmentTitle)
        let resolvedScore: Int
        if let score = action.score {
            resolvedScore = min(max(score, 1), 7)
        } else {
            resolvedScore = Grade.ibScore(fromNormalized: (action.achievedPoints ?? 0) / max(action.maxPoints ?? 1, 1))
        }

        return ParsedGradeImport(
            subject: subject,
            component: component,
            assessmentTitle: assessmentTitle.isEmpty ? component : assessmentTitle,
            score: resolvedScore,
            predictedGrade: action.predictedGrade,
            achievedPoints: action.achievedPoints,
            maxPoints: action.maxPoints,
            weightPercent: action.weightPercent,
            sourceName: action.sourceName,
            termName: action.termName,
            teacherFeedback: ""
        )
    }

    private func parseGradeImports(from rawText: String, subjects: [Subject], preferredSubject: Subject?, defaultSource: String?) -> [ParsedGradeImport] {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let subjectPairs = subjects.map { ($0, $0.name.lowercased()) }
        let lines = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var results: [ParsedGradeImport] = []
        var currentSubject = preferredSubject

        for line in lines {
            let lowercased = line.lowercased()
            if let explicitSubject = subjectPairs.first(where: { lowercased.contains($0.1) })?.0 {
                currentSubject = explicitSubject
            }
            guard let subject = currentSubject else { continue }

            let points = firstMatch(in: line, pattern: "(\\d+(?:\\.\\d+)?)\\s*/\\s*(\\d+(?:\\.\\d+)?)")
            let predictedGrade = firstIntMatch(in: line, pattern: "(?:predicted|forecast|target)\\s*(?:grade)?\\s*[:=-]?\\s*([1-7])")
            let explicitGrade = firstIntMatch(in: line, pattern: "(?:ib\\s*grade|grade|level|band)\\s*[:=-]?\\s*([1-7])")
            let weightPercent = firstDoubleMatch(in: line, pattern: "(?:weight|weighted|worth|contributes?)\\s*[:=-]?\\s*(\\d+(?:\\.\\d+)?)\\s*%")
            let sourceName = defaultSource ?? (lowercased.contains("managebac") ? "ManageBac" : nil)

            let resolvedScore: Int?
            let achievedPoints: Double?
            let maxPoints: Double?
            if points.count == 2, let achieved = Double(points[0]), let maximum = Double(points[1]), maximum > 0 {
                achievedPoints = achieved
                maxPoints = maximum
                resolvedScore = explicitGrade ?? Grade.ibScore(fromNormalized: achieved / maximum)
            } else {
                achievedPoints = nil
                maxPoints = nil
                if let explicitGrade {
                    resolvedScore = explicitGrade
                } else if let percentValue = firstStandalonePercent(in: line) {
                    resolvedScore = Grade.ibScore(fromNormalized: percentValue / 100.0)
                } else {
                    resolvedScore = nil
                }
            }

            guard let score = resolvedScore else { continue }

            let title = cleanedAssessmentTitle(from: line, subjectName: subject.name)
            let component = normalizedGradeComponent(from: title)
            results.append(ParsedGradeImport(
                subject: subject,
                component: component,
                assessmentTitle: title.isEmpty ? component : title,
                score: score,
                predictedGrade: predictedGrade,
                achievedPoints: achievedPoints,
                maxPoints: maxPoints,
                weightPercent: weightPercent,
                sourceName: sourceName,
                termName: nil,
                teacherFeedback: ""
            ))
        }

        return results
    }

    private func cleanedAssessmentTitle(from line: String, subjectName: String) -> String {
        var title = line.replacingOccurrences(of: subjectName, with: "", options: [.caseInsensitive])
        let patterns = [
            "(\\d+(?:\\.\\d+)?)\\s*/\\s*(\\d+(?:\\.\\d+)?)",
            "(?:predicted|forecast|target)\\s*(?:grade)?\\s*[:=-]?\\s*[1-7]",
            "(?:ib\\s*grade|grade|level|band)\\s*[:=-]?\\s*[1-7]",
            "(?:weight|weighted|worth|contributes?)\\s*[:=-]?\\s*\\d+(?:\\.\\d+)?\\s*%",
            "\\d+(?:\\.\\d+)?\\s*%"
        ]
        for pattern in patterns {
            title = title.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        title = title.replacingOccurrences(of: "|", with: " ")
        title = title.replacingOccurrences(of: "—", with: " ")
        title = title.replacingOccurrences(of: "-", with: " ")
        title = title.replacingOccurrences(of: "  ", with: " ")
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " -|\t"))
        return title.isEmpty ? "Assessment" : title
    }

    private func normalizedGradeComponent(from text: String) -> String {
        let normalized = text.lowercased()
        if normalized.contains("paper 1") { return "Paper 1" }
        if normalized.contains("paper 2") { return "Paper 2" }
        if normalized.contains("paper 3") { return "Paper 3" }
        if normalized.contains("ia") || normalized.contains("internal assessment") { return "IA" }
        if normalized.contains("mock") { return "Mock Exam" }
        if normalized.contains("quiz") { return "Quiz" }
        if normalized.contains("test") { return "Test" }
        if normalized.contains("essay") { return "Essay" }
        if normalized.contains("overall") { return "Overall" }
        return "Assessment"
    }

    private func normalizedGradeTitle(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func firstMatch(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange) else { return [] }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }

    private func firstIntMatch(in text: String, pattern: String) -> Int? {
        firstMatch(in: text, pattern: pattern).first.flatMap(Int.init)
    }

    private func firstDoubleMatch(in text: String, pattern: String) -> Double? {
        firstMatch(in: text, pattern: pattern).first.flatMap(Double.init)
    }

    private func firstStandalonePercent(in text: String) -> Double? {
        let matches = firstMatch(in: text, pattern: "(\\d+(?:\\.\\d+)?)\\s*%")
        for match in matches {
            if let value = Double(match), value <= 100 {
                return value
            }
        }
        return nil
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

        let requestedTopics = action.topics ?? []
        let topics = sanitizedTopics(requestedTopics, subjectName: subject.name, subjectLevel: subject.level)
        if !requestedTopics.isEmpty && topics.isEmpty {
            throw NSError(domain: "ARIAService", code: 7, userInfo: [NSLocalizedDescriptionKey: "ARIA could not match the requested topic to the real \(subject.name) curriculum."])
        }

        let allTopicNames = SyllabusSeeder.curriculum(for: subject.name, level: subject.level)
            .flatMap { $0.topics.map(\.name) }
        let subtopicScopeTopics = topics.isEmpty ? allTopicNames : topics
        let requestedSubtopics = action.subtopics ?? []
        let subtopics = sanitizedSubtopics(
            requestedSubtopics,
            subjectName: subject.name,
            subjectLevel: subject.level,
            topics: subtopicScopeTopics
        )
        if !requestedSubtopics.isEmpty && subtopics.isEmpty {
            throw NSError(domain: "ARIAService", code: 7, userInfo: [NSLocalizedDescriptionKey: "ARIA could not match the requested subunit to the real \(subject.name) curriculum."])
        }

        var changes: [String] = []

        if let rawMastery = action.masteryLevel?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !rawMastery.isEmpty {
            guard !topics.isEmpty || !subtopics.isEmpty else {
                throw NSError(domain: "ARIAService", code: 7, userInfo: [NSLocalizedDescriptionKey: "Mastery updates need a specific real topic or subunit, not an entire subject."])
            }
            guard let proficiency = proficiencyLevel(from: rawMastery) else {
                throw NSError(domain: "ARIAService", code: 7, userInfo: [NSLocalizedDescriptionKey: "ARIA received an unsupported mastery level."])
            }

            let curriculumNodes = (try? context.fetch(FetchDescriptor<CurriculumNode>())) ?? []
            let matchingNodes = curriculumNodes.filter { node in
                guard node.subjectName.caseInsensitiveCompare(subject.name) == .orderedSame,
                      node.level.caseInsensitiveCompare(subject.level) == .orderedSame else {
                    return false
                }
                let topicMatches = topics.isEmpty || topics.contains {
                    $0.caseInsensitiveCompare(node.topicName) == .orderedSame
                }
                let subtopicMatches = subtopics.isEmpty || subtopics.contains {
                    $0.caseInsensitiveCompare(node.subtopicName) == .orderedSame
                }
                return topicMatches && subtopicMatches
            }
            guard !matchingNodes.isEmpty else {
                throw NSError(domain: "ARIAService", code: 7, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find real curriculum subunits matching that mastery update."])
            }

            for node in matchingNodes {
                let trimmedNote = action.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                node.recordedProficiency = proficiency
                node.masteryUpdatedAt = Date()
                node.masterySource = "ARIA"
                node.masteryNote = trimmedNote.isEmpty ? nil : trimmedNote
                node.updatedAt = Date()
            }
            changes.append("recorded \(proficiency.rawValue.lowercased()) mastery for \(matchingNodes.count) curriculum subunit\(matchingNodes.count == 1 ? "" : "s")")
        }

        let minutes = max(action.minutesStudied ?? 0, 0)
        if minutes > 0 {
            let xp = recordScopedStudyWork(
                subjectName: subject.name,
                topics: topics,
                subtopics: subtopics,
                minutes: minutes,
                context: context
            )
            changes.append("logged \(Int(minutes.rounded()))m of scoped work and \(xp) XP")
        }

        guard !changes.isEmpty else {
            throw NSError(domain: "ARIAService", code: 8, userInfo: [NSLocalizedDescriptionKey: "ARIA needs a mastery level or minutes studied to update progress."])
        }
        return "Updated \(subject.name): \(changes.joined(separator: "; "))."
    }

    @MainActor
    private func recordScopedStudyWork(
        subjectName: String,
        topics: [String],
        subtopics: [String],
        minutes: Double,
        context: ModelContext
    ) -> Int {
        let safeMinutes = min(max(minutes, 1), 180)
        let now = Date()
        var xp = 0
        if let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first {
            xp = XPCalculator.xp(forStudyMinutes: safeMinutes, intensity: profile.studyIntensity)
            profile.recordXP(xp)
        }

        let session = StudySession(
            subjectName: subjectName,
            topicsCovered: topics.joined(separator: ", "),
            subtopicsCovered: subtopics.joined(separator: ", "),
            startDate: now.addingTimeInterval(-(safeMinutes * 60)),
            endDate: now,
            cardsReviewed: 0,
            correctCount: 0,
            xpEarned: xp
        )
        context.insert(session)

        let today = Calendar.current.startOfDay(for: now)
        let predicate = #Predicate<StudyActivity> { $0.date == today }
        let activity = (try? context.fetch(FetchDescriptor(predicate: predicate)).first) ?? {
            let created = StudyActivity(date: today)
            context.insert(created)
            return created
        }()
        activity.minutesStudied += safeMinutes
        activity.xpEarned += xp
        return xp
    }

    @MainActor
    private func executeUpdateProfile(action: PlannedAppAction, context: ModelContext) throws -> String {
        guard let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first else {
            throw NSError(domain: "ARIAService", code: 9, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find a user profile to update."])
        }

        var changes: [String] = []
        if let dailyGoal = action.dailyGoal, dailyGoal > 0 {
            let boundedGoal = min(max(dailyGoal, 5), ReviewDailyLimitPolicy.maximumCards)
            profile.dailyGoal = boundedGoal
            changes.append("daily goal to \(boundedGoal) cards")
        }
        if let target = action.targetIBScore, (1...45).contains(target) {
            profile.targetIBScore = target
            changes.append("target score to \(target)/45")
        }
        if let studentName = action.studentName?.trimmingCharacters(in: .whitespacesAndNewlines), !studentName.isEmpty, studentName != profile.studentName {
            profile.studentName = studentName
            changes.append("name to \(studentName)")
        }
        if let hour = action.notificationHour, (0...23).contains(hour) {
            profile.notificationHour = hour
            changes.append("notification hour to \(hour)")
        }
        if let minute = action.notificationMinute, (0...59).contains(minute) {
            profile.notificationMinute = minute
            changes.append("notification minute to \(minute)")
        }
        if let rawIntensity = action.studyIntensity?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           let intensity = StudyIntensity.allCases.first(where: { $0.rawValue.lowercased() == rawIntensity }) {
            profile.studyIntensity = intensity
            changes.append("study intensity to \(intensity.rawValue)")
        }
        if let rawYear = action.ibYear?.trimmingCharacters(in: .whitespacesAndNewlines),
           let year = IBYear.allCases.first(where: { $0.rawValue.lowercased() == rawYear.lowercased() || $0.shortLabel.lowercased() == rawYear.lowercased() }) {
            profile.ibYear = year
            changes.append("programme stage to \(year.shortLabel)")
        }
        if let freezes = action.streakFreezes, freezes >= 0 {
            profile.streakFreezes = freezes
            changes.append("streak freezes to \(freezes)")
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
        try context.save()
        return "Saved that to ARIA memory under \(category.rawValue)."
    }

    // MARK: - Flashcard tools

    @MainActor
    private func executeCreateFlashcard(action: PlannedAppAction, context: ModelContext) throws -> String {
        guard let subject = resolveSubject(named: action.subjectName, context: context) else {
            throw NSError(domain: "ARIAService", code: 30, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find the subject for that flashcard."])
        }

        let front = action.frontText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let back = action.backText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !front.isEmpty, !back.isEmpty else {
            throw NSError(domain: "ARIAService", code: 31, userInfo: [NSLocalizedDescriptionKey: "ARIA needs both front and back text to create a flashcard."])
        }

        let topicName = action.topics?.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sanitizedTopic = topicName.isEmpty
            ? (uniqueTopicNames(for: subject).first ?? "General")
            : topicName
        let subtopic = action.subtopics?.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let difficulty = CardDifficulty.allCases.first {
            $0.rawValue.caseInsensitiveCompare(action.difficulty ?? "") == .orderedSame
        } ?? .standard
        let cognitiveSkill = CardCognitiveSkill.allCases.first {
            $0.rawValue.caseInsensitiveCompare(action.cognitiveSkill ?? "") == .orderedSame
        } ?? .recall

        let card = StudyCard(
            topicName: sanitizedTopic,
            subtopic: subtopic,
            front: front,
            back: back,
            subject: subject,
            isCustom: true,
            isAIGenerated: false,
            generationSource: "ARIA",
            hint: action.hint?.trimmingCharacters(in: .whitespacesAndNewlines),
            difficulty: difficulty,
            cognitiveSkill: cognitiveSkill
        )
        context.insert(card)

        ARIAService.recordFlashcardGeneration(
            subjectName: subject.name,
            topicName: sanitizedTopic,
            subtopicName: subtopic,
            generatedCards: [(front, back)],
            sourceReference: "ARIAService.executeCreateFlashcard"
        )

        return "Created a new flashcard in \(subject.name) under \(sanitizedTopic)."
    }

    // MARK: - Grade tools

    @MainActor
    private func executeAddGrade(action: PlannedAppAction, context: ModelContext) throws -> String {
        guard let subject = resolveSubject(named: action.subjectName, context: context) else {
            throw NSError(domain: "ARIAService", code: 32, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find the subject for that grade."])
        }

        let component = normalizedGradeComponent(from: action.component ?? action.assessmentTitle ?? "Assessment")
        guard component != "Assessment" || action.assessmentTitle?.isEmpty == false else {
            throw NSError(domain: "ARIAService", code: 33, userInfo: [NSLocalizedDescriptionKey: "ARIA needs a grade component or assessment title."])
        }

        // Without numeric evidence, Grade(score: 0) would clamp to a fabricated
        // score of 1. edit_grade and import_grades already require it; keep
        // add_grade consistent rather than silently inventing a mark.
        guard action.score != nil || (action.achievedPoints != nil && action.maxPoints != nil) else {
            throw NSError(domain: "ARIAService", code: 33, userInfo: [NSLocalizedDescriptionKey: "ARIA needs a score (1-7) or marks out of a maximum to record that grade."])
        }

        let grade = Grade(
            component: component,
            score: action.score ?? 0,
            predictedGrade: action.predictedGrade,
            teacherFeedback: action.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            assessmentTitle: action.assessmentTitle ?? "",
            achievedPoints: action.achievedPoints,
            maxPoints: action.maxPoints,
            weightPercent: action.weightPercent,
            sourceName: action.sourceName,
            termName: action.termName,
            subject: subject
        )
        context.insert(grade)

        if let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first {
            profile.reportLastUploaded = Date()
        }

        return "Recorded \(grade.scoreSummary) for \(subject.name) \(grade.displayTitle)."
    }

    @MainActor
    private func executeEditGrade(action: PlannedAppAction, context: ModelContext) throws -> String {
        guard let subject = resolveSubject(named: action.subjectName, context: context) else {
            throw NSError(domain: "ARIAService", code: 34, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find the subject for that grade edit."])
        }

        guard let grade = matchingGrade(for: action, in: subject) else {
            throw NSError(domain: "ARIAService", code: 35, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find a grade matching that edit request."])
        }

        var changes: [String] = []
        if let score = action.score, (1...7).contains(score) {
            grade.score = score
            changes.append("score to \(score)")
        }
        if let predicted = action.predictedGrade {
            grade.predictedGrade = predicted
            changes.append("predicted grade to \(predicted)")
        }
        if let points = action.achievedPoints, let max = action.maxPoints, max > 0 {
            grade.achievedPoints = points
            grade.maxPoints = max
            changes.append("marks to \(Self.formatGradePoints(points))/\(Self.formatGradePoints(max))")
        }
        if let weight = action.weightPercent, weight > 0 {
            grade.weightPercent = weight
            changes.append("weight to \(Self.formatGradePoints(weight))%")
        }
        if let title = action.assessmentTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            grade.assessmentTitle = title
            changes.append("title to \(title)")
        }
        if let feedback = action.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !feedback.isEmpty {
            grade.teacherFeedback = feedback
            changes.append("feedback")
        }

        guard !changes.isEmpty else {
            throw NSError(domain: "ARIAService", code: 36, userInfo: [NSLocalizedDescriptionKey: "ARIA needs at least one updated grade field."])
        }
        grade.date = Date()
        return "Updated the \(grade.displayTitle) grade in \(subject.name): \(changes.joined(separator: ", "))."
    }

    @MainActor
    private func executeDeleteGrade(action: PlannedAppAction, context: ModelContext) throws -> String {
        guard let subject = resolveSubject(named: action.subjectName, context: context) else {
            throw NSError(domain: "ARIAService", code: 37, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find the subject for that grade."])
        }

        guard let grade = matchingGrade(for: action, in: subject) else {
            throw NSError(domain: "ARIAService", code: 38, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find a grade matching that deletion request."])
        }

        let description = "\(subject.name) \(grade.displayTitle)"
        subject.grades.removeAll { $0.id == grade.id }
        context.delete(grade)
        return "Deleted the \(description) grade."
    }

    private func matchingGrade(for action: PlannedAppAction, in subject: Subject) -> Grade? {
        let requestedComponent = action.component?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let requestedTitle = normalizedGradeTitle(action.assessmentTitle ?? "")
        let searchTerms = [action.searchText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        return subject.grades
            .sorted { $0.date > $1.date }
            .first { grade in
                let componentMatches = requestedComponent.isEmpty
                    || grade.component.caseInsensitiveCompare(requestedComponent) == .orderedSame
                let titleMatches = requestedTitle.isEmpty
                    || normalizedGradeTitle(grade.displayTitle) == requestedTitle
                    || grade.displayTitle.localizedCaseInsensitiveContains(requestedTitle)
                let idMatches = action.gradeID == nil || grade.id == action.gradeID
                let searchMatches = searchTerms.isEmpty || searchTerms.allSatisfy {
                    [grade.component, grade.displayTitle, grade.teacherFeedback]
                        .joined(separator: "\n")
                        .lowercased()
                        .contains($0)
                }
                return componentMatches && titleMatches && idMatches && searchMatches
            }
    }

    // MARK: - Assessment evidence tools

    @MainActor
    private func executeRecordAssessment(action: PlannedAppAction, context: ModelContext) throws -> String {
        guard let subject = resolveSubject(named: action.subjectName, context: context) else {
            throw NSError(domain: "ARIAService", code: 39, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find the subject for that assessment."])
        }

        let title = action.assessmentTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else {
            throw NSError(domain: "ARIAService", code: 40, userInfo: [NSLocalizedDescriptionKey: "ARIA needs an assessment title to record school evidence."])
        }
        let percentage = action.percentage.map { min(max($0, 0), 100) }
        guard percentage != nil || action.score != nil || (action.achievedPoints != nil && action.maxPoints != nil) else {
            throw NSError(domain: "ARIAService", code: 41, userInfo: [NSLocalizedDescriptionKey: "ARIA needs a percentage, IB score, or marks out of a maximum to calibrate mastery."])
        }

        let assessments = (try? context.fetch(FetchDescriptor<AcademicAssessment>())) ?? []
        let existing = assessments.first {
            $0.subjectName.caseInsensitiveCompare(subject.name) == .orderedSame &&
                $0.courseLevel.caseInsensitiveCompare(subject.level) == .orderedSame &&
                normalizedGradeTitle($0.title) == normalizedGradeTitle(title)
        }
        let assessment: AcademicAssessment
        if let existing {
            assessment = existing
            assessment.assessmentDate = parseScheduledDate(action.assessmentDate) ?? assessment.assessmentDate ?? Date()
            assessment.assessmentType = nonEmptyText(action.assessmentType) ?? assessment.assessmentType
            assessment.category = nonEmptyText(action.category) ?? assessment.category
            assessment.achievedPoints = action.achievedPoints ?? assessment.achievedPoints
            assessment.possiblePoints = action.maxPoints ?? assessment.possiblePoints
            assessment.percentage = percentage ?? assessment.percentage
            assessment.ibScore = action.score.map { min(max($0, 1), 7) } ?? assessment.ibScore
            assessment.details = nonEmptyText(action.notes) ?? assessment.details
        } else {
            assessment = AcademicAssessment(
                sourceKey: "aria-(UUID().uuidString)",
                sourceFileName: "ARIA",
                subjectName: subject.name,
                courseLevel: subject.level,
                sourceClassLabel: "(subject.name) (subject.level)",
                assessmentDate: parseScheduledDate(action.assessmentDate) ?? Date(),
                title: title,
                assessmentType: nonEmptyText(action.assessmentType) ?? "Assessment",
                category: nonEmptyText(action.category) ?? "Scored evidence",
                status: "Graded",
                achievedPoints: action.achievedPoints,
                possiblePoints: action.maxPoints,
                percentage: percentage,
                ibScore: action.score.map { min(max($0, 1), 7) },
                details: action.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
            context.insert(assessment)
        }

        let requestedTopics = action.topics ?? []
        let topics = sanitizedTopics(requestedTopics, subjectName: subject.name, subjectLevel: subject.level)
        if !requestedTopics.isEmpty && topics.isEmpty {
            throw NSError(domain: "ARIAService", code: 42, userInfo: [NSLocalizedDescriptionKey: "ARIA could not match the assessment to a real (subject.name) topic."])
        }
        if let topic = topics.first {
            let subtopic = sanitizedSubtopics(
                action.subtopics ?? [],
                subjectName: subject.name,
                subjectLevel: subject.level,
                topics: [topic]
            ).first ?? ""
            let mappings = (try? context.fetch(FetchDescriptor<AcademicAssessmentMapping>())) ?? []
            let mapping = mappings.first { $0.assessmentID == assessment.id } ?? {
                let created = AcademicAssessmentMapping(
                    assessmentID: assessment.id,
                    subjectName: subject.name,
                    courseLevel: subject.level,
                    curriculumNodeKey: "aria.(assessment.id.uuidString)",
                    unitName: nonEmptyText(action.unitName) ?? topic,
                    topicName: topic,
                    subtopicName: subtopic,
                    status: .approved,
                    confidence: 1,
                    rationale: "Recorded directly by ARIA from learner-provided school evidence.",
                    proposedBy: "ARIA"
                )
                context.insert(created)
                return created
            }()
            mapping.topicName = topic
            mapping.subtopicName = subtopic
            mapping.status = .approved
        }

        if let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first {
            profile.reportLastUploaded = Date()
        }
        return "Recorded (assessment.title) as scored (subject.name) evidence; mastery will now use it."
    }

    @MainActor
    private func executeDeleteAssessment(action: PlannedAppAction, context: ModelContext) throws -> String {
        guard let subject = resolveSubject(named: action.subjectName, context: context) else {
            throw NSError(domain: "ARIAService", code: 43, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find the subject for that assessment."])
        }
        let assessments = (try? context.fetch(FetchDescriptor<AcademicAssessment>())) ?? []
        guard let assessment = assessments.first(where: {
            $0.subjectName.caseInsensitiveCompare(subject.name) == .orderedSame &&
                $0.courseLevel.caseInsensitiveCompare(subject.level) == .orderedSame &&
                assessmentMatches(action, assessment: $0)
        }) else {
            throw NSError(domain: "ARIAService", code: 44, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find an assessment matching that deletion request."])
        }
        let mappings = (try? context.fetch(FetchDescriptor<AcademicAssessmentMapping>())) ?? []
        for mapping in mappings where mapping.assessmentID == assessment.id {
            context.delete(mapping)
        }
        context.delete(assessment)
        return "Deleted the (assessment.title) assessment evidence from (subject.name)."
    }

    private func assessmentMatches(_ action: PlannedAppAction, assessment: AcademicAssessment) -> Bool {
        let title = action.assessmentTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let search = action.searchText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty || !search.isEmpty else { return false }
        return title.isEmpty || normalizedGradeTitle(assessment.title) == normalizedGradeTitle(title)
            || assessment.title.localizedCaseInsensitiveContains(title)
            || assessment.details.localizedCaseInsensitiveContains(title)
            || (!search.isEmpty && [
                assessment.title,
                assessment.assessmentType,
                assessment.category,
                assessment.details
            ].joined(separator: "\n").localizedCaseInsensitiveContains(search))
    }

    private func nonEmptyText(_ raw: String?) -> String? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }

    // MARK: - Mastery tools

    @MainActor
    private func executeSetMastery(action: PlannedAppAction, context: ModelContext) throws -> String {
        guard let subject = resolveSubject(named: action.subjectName, context: context) else {
            throw NSError(domain: "ARIAService", code: 40, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find the subject to update mastery."])
        }

        let requestedTopics = action.topics ?? []
        let topics = sanitizedTopics(requestedTopics, subjectName: subject.name, subjectLevel: subject.level)
        if !requestedTopics.isEmpty && topics.isEmpty {
            throw NSError(domain: "ARIAService", code: 41, userInfo: [NSLocalizedDescriptionKey: "ARIA could not match the requested topic to the real \(subject.name) curriculum."])
        }

        // Card-level mastery: the model can target one specific card by ID.
        if let cardID = action.cardID, let card = subject.cards.first(where: { $0.id == cardID }) {
            return try applyCardMastery(card: card, action: action)
        }

        if action.clearMastery == true {
            guard !topics.isEmpty || !(action.subtopics ?? []).isEmpty else {
                throw NSError(domain: "ARIAService", code: 42, userInfo: [NSLocalizedDescriptionKey: "Clearing mastery needs a specific topic or subunit."])
            }
            let cleared = try clearNodeMastery(subject: subject, topics: topics, subtopics: action.subtopics ?? [], context: context)
            return "Cleared recorded mastery for \(cleared) curriculum subunit\(cleared == 1 ? "" : "s") in \(subject.name)."
        }

        guard let rawMastery = action.masteryLevel?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !rawMastery.isEmpty else {
            throw NSError(domain: "ARIAService", code: 43, userInfo: [NSLocalizedDescriptionKey: "ARIA needs a mastery level (Novice, Developing, Proficient, Mastered) or a card id to set mastery."])
        }
        guard let proficiency = proficiencyLevel(from: rawMastery) else {
            throw NSError(domain: "ARIAService", code: 44, userInfo: [NSLocalizedDescriptionKey: "ARIA received an unsupported mastery level."])
        }
        guard !topics.isEmpty || !(action.subtopics ?? []).isEmpty else {
            throw NSError(domain: "ARIAService", code: 45, userInfo: [NSLocalizedDescriptionKey: "Mastery updates need a specific real topic or subunit, not an entire subject."])
        }

        let allTopicNames = SyllabusSeeder.curriculum(for: subject.name, level: subject.level)
            .flatMap { $0.topics.map(\.name) }
        let subtopicScopeTopics = topics.isEmpty ? allTopicNames : topics
        let subtopics = sanitizedSubtopics(
            action.subtopics,
            subjectName: subject.name,
            subjectLevel: subject.level,
            topics: subtopicScopeTopics
        )

        let curriculumNodes = (try? context.fetch(FetchDescriptor<CurriculumNode>())) ?? []
        let matchingNodes = curriculumNodes.filter { node in
            guard node.subjectName.caseInsensitiveCompare(subject.name) == .orderedSame,
                  node.level.caseInsensitiveCompare(subject.level) == .orderedSame else {
                return false
            }
            let topicMatches = topics.isEmpty || topics.contains {
                $0.caseInsensitiveCompare(node.topicName) == .orderedSame
            }
            let subtopicMatches = subtopics.isEmpty || subtopics.contains {
                $0.caseInsensitiveCompare(node.subtopicName) == .orderedSame
            }
            return topicMatches && subtopicMatches
        }
        guard !matchingNodes.isEmpty else {
            throw NSError(domain: "ARIAService", code: 46, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find real curriculum subunits matching that mastery update."])
        }

        let trimmedNote = action.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        for node in matchingNodes {
            node.recordedProficiency = proficiency
            node.masteryUpdatedAt = Date()
            node.masterySource = "ARIA"
            node.masteryNote = trimmedNote.isEmpty ? nil : trimmedNote
            node.updatedAt = Date()
        }

        return "Recorded \(proficiency.rawValue.lowercased()) mastery for \(matchingNodes.count) curriculum subunit\(matchingNodes.count == 1 ? "" : "s") in \(subject.name)."
    }

    private func applyCardMastery(card: StudyCard, action: PlannedAppAction) throws -> String {
        if action.clearMastery == true {
            card.proficiency = .novice
            return "Cleared mastery on the flashcard '\(compactCardLabel(card.front))'."
        }
        guard let rawMastery = action.masteryLevel?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let proficiency = proficiencyLevel(from: rawMastery) else {
            throw NSError(domain: "ARIAService", code: 47, userInfo: [NSLocalizedDescriptionKey: "ARIA needs a mastery level (Novice, Developing, Proficient, Mastered) to set mastery on that card."])
        }
        card.proficiency = proficiency
        card.consecutiveCorrect = proficiency == .novice ? 0 : max(card.consecutiveCorrect, 2)
        return "Marked the flashcard '\(compactCardLabel(card.front))' as \(proficiency.rawValue.lowercased())."
    }

    private func clearNodeMastery(subject: Subject, topics: [String], subtopics: [String], context: ModelContext) throws -> Int {
        let allTopicNames = SyllabusSeeder.curriculum(for: subject.name, level: subject.level)
            .flatMap { $0.topics.map(\.name) }
        let subtopicScopeTopics = topics.isEmpty ? allTopicNames : topics
        let sanitizedSubtopics = sanitizedSubtopics(subtopics, subjectName: subject.name, subjectLevel: subject.level, topics: subtopicScopeTopics)

        let nodes = (try? context.fetch(FetchDescriptor<CurriculumNode>())) ?? []
        let matching = nodes.filter { node in
            guard node.subjectName.caseInsensitiveCompare(subject.name) == .orderedSame,
                  node.level.caseInsensitiveCompare(subject.level) == .orderedSame else {
                return false
            }
            let topicMatches = topics.isEmpty || topics.contains {
                $0.caseInsensitiveCompare(node.topicName) == .orderedSame
            }
            let subtopicMatches = sanitizedSubtopics.isEmpty || sanitizedSubtopics.contains {
                $0.caseInsensitiveCompare(node.subtopicName) == .orderedSame
            }
            return topicMatches && subtopicMatches
        }
        for node in matching {
            node.recordedProficiency = nil
            node.masteryUpdatedAt = nil
            node.masterySource = nil
            node.masteryNote = nil
            node.updatedAt = Date()
        }
        return matching.count
    }

    // MARK: - Unit state tool

    @MainActor
    private func executeUpdateUnitState(action: PlannedAppAction, context: ModelContext) throws -> String {
        guard let subject = resolveSubject(named: action.subjectName, context: context) else {
            throw NSError(domain: "ARIAService", code: 48, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find the subject for that unit update."])
        }

        let unitName = action.unitName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !unitName.isEmpty else {
            throw NSError(domain: "ARIAService", code: 49, userInfo: [NSLocalizedDescriptionKey: "ARIA needs a real unit name to update its state."])
        }

        let isTaught = action.isTaught ?? true
        let existing = (try? context.fetch(FetchDescriptor<UnitState>())) ?? []
        let target = existing.first {
            $0.subjectName.caseInsensitiveCompare(subject.name) == .orderedSame &&
                $0.unitName.caseInsensitiveCompare(unitName) == .orderedSame
        } ?? {
            let created = UnitState(subjectName: subject.name, unitName: unitName, isTaught: isTaught)
            context.insert(created)
            return created
        }()
        target.isTaught = isTaught
        return isTaught
            ? "Marked \(unitName) as taught in \(subject.name)."
            : "Marked \(unitName) as not yet taught in \(subject.name)."
    }

    // MARK: - Subject tools

    @MainActor
    private func executeCreateSubject(action: PlannedAppAction, context: ModelContext) throws -> String {
        let name = action.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else {
            throw NSError(domain: "ARIAService", code: 50, userInfo: [NSLocalizedDescriptionKey: "ARIA needs a subject name to create one."])
        }

        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        if subjects.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            throw NSError(domain: "ARIAService", code: 51, userInfo: [NSLocalizedDescriptionKey: "A subject named \(name) already exists."])
        }

        let level = action.level?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "HL" ? "HL" : "SL"
        let hex = action.accentColorHex?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "#10B981"
        let examDate = parseScheduledDate(action.examDate)

        let subject = Subject(name: name, level: level, accentColorHex: hex, examDate: examDate)
        context.insert(subject)
        return "Added \(name) at \(level) level."
    }

    @MainActor
    private func executeUpdateSubject(action: PlannedAppAction, context: ModelContext) throws -> String {
        guard let subject = resolveSubject(named: action.subjectName, context: context) else {
            throw NSError(domain: "ARIAService", code: 52, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find the subject to update."])
        }

        var changes: [String] = []
        if let newName = action.name?.trimmingCharacters(in: .whitespacesAndNewlines), !newName.isEmpty, newName.caseInsensitiveCompare(subject.name) != .orderedSame {
            subject.name = newName
            changes.append("name to \(newName)")
        }
        if let rawLevel = action.level?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), rawLevel == "HL" || rawLevel == "SL" {
            subject.level = rawLevel
            changes.append("level to \(rawLevel)")
        }
        if let hex = action.accentColorHex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty {
            subject.accentColorHex = hex
            changes.append("accent colour")
        }
        if let rawDate = action.examDate, let date = parseScheduledDate(rawDate) {
            subject.examDate = date
            changes.append("exam date")
        }

        guard !changes.isEmpty else {
            throw NSError(domain: "ARIAService", code: 53, userInfo: [NSLocalizedDescriptionKey: "ARIA did not receive a supported subject change."])
        }
        return "Updated \(subject.name): \(changes.joined(separator: ", "))."
    }

    @MainActor
    private func executeDeleteSubject(action: PlannedAppAction, context: ModelContext) throws -> String {
        guard let subject = resolveSubject(named: action.subjectName, context: context) else {
            throw NSError(domain: "ARIAService", code: 54, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find the subject to delete."])
        }

        let name = subject.name
        let cardCount = subject.cards.count
        for card in subject.cards {
            context.delete(card)
        }
        for grade in subject.grades {
            context.delete(grade)
        }
        context.delete(subject)
        return "Deleted \(name) and its \(cardCount) flashcard\(cardCount == 1 ? "" : "s") and grade records."
    }

    // MARK: - Memory tools

    @MainActor
    private func executeEditMemory(action: PlannedAppAction, context: ModelContext) throws -> String {
        guard let memory = matchingMemory(for: action, context: context) else {
            throw NSError(domain: "ARIAService", code: 55, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find a saved memory matching that request."])
        }

        var changes: [String] = []
        if let note = action.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            memory.content = note
            changes.append("content")
        }
        if let rawCategory = action.memoryCategory?.trimmingCharacters(in: .whitespacesAndNewlines), !rawCategory.isEmpty {
            memory.category = memoryCategory(from: rawCategory)
            changes.append("category")
        }
        if let subjectName = action.subjectName?.trimmingCharacters(in: .whitespacesAndNewlines), !subjectName.isEmpty {
            memory.subjectName = subjectName
            changes.append("subject")
        }

        guard !changes.isEmpty else {
            throw NSError(domain: "ARIAService", code: 56, userInfo: [NSLocalizedDescriptionKey: "ARIA needs updated memory content to edit that note."])
        }
        return "Updated ARIA memory (\(changes.joined(separator: ", ")))."
    }

    @MainActor
    private func executeDeleteMemory(action: PlannedAppAction, context: ModelContext) throws -> String {
        guard let memory = matchingMemory(for: action, context: context) else {
            throw NSError(domain: "ARIAService", code: 57, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find a saved memory matching that deletion request."])
        }

        let preview = compactCardLabel(memory.content)
        context.delete(memory)
        return "Deleted the ARIA memory '\(preview)'."
    }

    @MainActor
    private func executeDeleteOldChats(action: PlannedAppAction, context: ModelContext) throws -> String {
        let days = action.olderThanDays ?? 30
        guard days > 0 else {
            throw NSError(domain: "ARIAService", code: 59, userInfo: [NSLocalizedDescriptionKey: "ARIA needs a positive age in days before deleting old chats."])
        }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            throw NSError(domain: "ARIAService", code: 60, userInfo: [NSLocalizedDescriptionKey: "ARIA could not calculate the chat cleanup date."])
        }

        let sessions = (try? context.fetch(FetchDescriptor<ARIAChatSession>())) ?? []
        let staleSessions = sessions.filter { $0.updatedAt < cutoff }
        guard !staleSessions.isEmpty else {
            return "No ARIA chats are older than \(days) days."
        }

        let messages = (try? context.fetch(FetchDescriptor<ChatMessage>())) ?? []
        let staleIDs = Set(staleSessions.map(\.id))
        for message in messages where message.sessionID.map(staleIDs.contains) == true {
            context.delete(message)
        }
        for session in staleSessions {
            context.delete(session)
        }
        return "Deleted \(staleSessions.count) ARIA chat\(staleSessions.count == 1 ? "" : "s") older than \(days) days."
    }

    private func matchingMemory(for action: PlannedAppAction, context: ModelContext) -> ARIAMemory? {
        let memories = (try? context.fetch(FetchDescriptor<ARIAMemory>())) ?? []
        let searchTerms = [action.searchText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let requestedSubject = action.subjectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return memories
            .sorted { $0.timestamp > $1.timestamp }
            .first { memory in
                let idMatches = action.memoryID == nil || memory.id == action.memoryID
                let subjectMatches = requestedSubject.isEmpty
                    || memory.subjectName?.caseInsensitiveCompare(requestedSubject) == .orderedSame
                let searchMatches = searchTerms.isEmpty || searchTerms.allSatisfy { searchTerm in
                    memory.content.lowercased().contains(searchTerm)
                        || memory.tags.contains { $0.lowercased().contains(searchTerm) }
                }
                return idMatches && subjectMatches && searchMatches
            }
    }

    // MARK: - Plan tool

    @MainActor
    private func executeDeleteStudyPlan(action: PlannedAppAction, context: ModelContext) throws -> String {
        guard let plan = findMatchingPlan(for: action, context: context) else {
            throw NSError(domain: "ARIAService", code: 58, userInfo: [NSLocalizedDescriptionKey: "ARIA could not find a matching study session to delete."])
        }

        let description = "\(plan.subjectName) \(plan.selectionSummary)"
        context.delete(plan)
        return "Deleted the \(description) study session."
    }

    private func compactCardLabel(_ text: String) -> String {
        let flattened = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flattened.count > 60 else { return flattened }
        return String(flattened.prefix(57)) + "…"
    }

    private static func formatGradePoints(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(rounded - value) < 0.0001 {
            return String(Int(rounded))
        }
        return String(format: "%.1f", value)
    }

    @MainActor
    private func resolveSubject(named rawName: String?, context: ModelContext) -> Subject? {
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        guard let rawName = rawName?.trimmingCharacters(in: .whitespacesAndNewlines), !rawName.isEmpty else {
            return subjects.count == 1 ? subjects.first : nil
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
        // Cards can carry arbitrary topic/subtopic strings, so locate them with
        // raw case-insensitive values rather than curriculum-sanitized ones,
        // which would silently drop any card whose subtopic is not an exact
        // syllabus entry.
        let topics = (action.topics ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let subtopics = (action.subtopics ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        // Locate by searchText only. frontText/backText are the *new* values,
        // so they must never double as match terms or a front edit would have
        // to match the store's old text against the replacement text.
        let searchTerms = [action.searchText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        return subject.cards.filter { card in
            let matchesTopic = topics.isEmpty || topics.contains(card.topicName.lowercased())
            let matchesSubtopic = subtopics.isEmpty || subtopics.contains(card.subtopic.lowercased())
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

        // SwiftData relationship order is not guaranteed, so sort for
        // deterministic tool behaviour (e.g. the default-topic fallback).
        return topics.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func sanitizedTopics(_ topics: [String]?, subjectName: String, subjectLevel: String) -> [String] {
        let requested = (topics ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !requested.isEmpty else { return [] }
        let valid = SyllabusSeeder.curriculum(for: subjectName, level: subjectLevel).flatMap { $0.topics.map(\.name) }
        return canonicalCurriculumMatches(requested, validValues: valid)
    }

    private func sanitizedSubtopics(_ subtopics: [String]?, subjectName: String, subjectLevel: String, topics: [String]) -> [String] {
        let requested = (subtopics ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !requested.isEmpty else { return [] }
        let valid = topics.flatMap { SyllabusSeeder.subtopics(for: subjectName, level: subjectLevel, topicName: $0) }
        return canonicalCurriculumMatches(requested, validValues: valid)
    }

    private func canonicalCurriculumMatches(_ requested: [String], validValues: [String]) -> [String] {
        var seen = Set<String>()
        return requested.compactMap { request in
            let exact = validValues.first { $0.caseInsensitiveCompare(request) == .orderedSame }
            let candidates = exact.map { [$0] } ?? validValues.filter {
                $0.localizedCaseInsensitiveContains(request) || request.localizedCaseInsensitiveContains($0)
            }
            guard candidates.count == 1, let match = candidates.first else { return nil }
            let key = match.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return match
        }
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

    private func proficiencyLevel(from rawValue: String) -> ProficiencyLevel? {
        switch rawValue {
        case "novice": return .novice
        case "developing", "intermediate": return .developing
        case "proficient", "strong": return .proficient
        case "mastered", "mastery": return .mastered
        default: return nil
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

    private static func appendStreamChunk(_ chunk: String, to current: inout String) {
        guard !chunk.isEmpty else { return }
        guard !current.isEmpty else {
            current = chunk
            return
        }

        if shouldInsertSpace(between: current.last, and: chunk.first) {
            current.append(" ")
        }
        current.append(chunk)
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
        guard !session.isDeleted else { return }
        if session.title == "New Chat" || session.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            session.title = compactSessionTitle(from: message)
        }
        session.updatedAt = Date()
        session.lastMessagePreview = compactSessionPreview(from: message)
    }

    @MainActor
    private func updateSession(_ session: ARIAChatSession, withAssistantReply reply: String) {
        guard !session.isDeleted else { return }
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
        Role: You are ARIA, an adaptive International Baccalaureate study coach inside IBVault.

        Personality: Warm, direct, calm, and intellectually honest. Treat the learner as capable. Acknowledge setbacks briefly, then move to a concrete next action.

        Goal: Help the learner improve subject mastery and exam performance using their saved curriculum, grades, review history, study plans, and preferences.

        Success criteria:
        - answer the learner's actual request before adding optional advice
        - respect each subject's saved SL or HL level
        - ground recommendations in the supplied app snapshot and curriculum nodes
        - use active recall, spaced repetition, interleaving, worked examples, and error correction where useful
        - distinguish a known fact from an inference or estimate
        - never invent grade boundaries, assessment weightings, quotations, source titles, or syllabus requirements
        - when a source is requested, name the available source and URL; if no source is available, say so plainly

        Formatting:
        - use clean Markdown with short sections and readable lists
        - use $...$ for inline LaTeX and $$...$$ for display equations
        - show units and intermediate steps in calculations
        - avoid Markdown tables; use short labelled bullets so content stays readable at every chat width
        - do not expose internal JSON or hidden reasoning
        \(ARIAContentContract.capabilitySummary)

        App actions:
        - only change app data when the learner explicitly asks
        - you can create, reschedule, complete, or cancel study/review sessions; generate, create, edit, or delete flashcards; import, add, edit, or delete grades (including teacher feedback in notes); record or delete scored school assessments that calibrate subject and mapped-subunit mastery; set or clear mastery on curriculum subunits or individual cards; mark curriculum units taught; update the learner's profile (name, target score, daily goal, study intensity, programme year, notifications, streak freezes); create, update, or delete subjects; save, edit, or delete durable memories; and delete old chats by age using delete_old_chats with olderThanDays
        - destructive changes (deletes and cancellations) require the learner to have clearly asked for that specific change in the current message
        - report what changed and any action that failed
        - never fabricate the outcome of a change you did not perform

        Flashcards:
        - test one idea per card and vary recall, explanation, application, analysis, and evaluation
        - adapt difficulty from the saved review history
        - include valid LaTeX where needed and avoid ambiguous notation
        - use the exact selected curriculum unit, topic, and subunit

        \(hasData ? "" : "The learner has no saved study data yet. Help them complete subject setup before making personalized claims.")
        """

        prompt += "\n\n\(ARIAContentContract.systemInstruction)"

        // Inject memory preamble
        let memoryPreamble = await buildMemoryPreamble(context: context, queryProfile: queryProfile)
        if !memoryPreamble.isEmpty {
            prompt += "\nRELEVANT LONG-TERM CONTEXT:\n\(memoryPreamble)\n"
        }

        // Inject app state
        let appState = await buildAppStateSnapshot(context: context, queryProfile: queryProfile)
        prompt += "\nCURRENT STUDENT SNAPSHOT:\n\(appState)\n"

        // Inject curated subject-specific domain knowledge for the subjects the
        // learner is actively working on, so ARIA's coaching is grounded in the
        // subject's key concepts, high-yield topics and exam conventions.
        let knowledgeBlock = buildSubjectKnowledgeBlock(context: context, queryProfile: queryProfile)
        if !knowledgeBlock.isEmpty {
            prompt += "\nSUBJECT-SPECIFIC KNOWLEDGE:\n\(knowledgeBlock)\n"
        }

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
        - Reference only the user's actual saved grades, session history, weak topics, and explicit goals
        - If cards are overdue, distinguish the backlog from today's humane review allowance; never pressure the learner to clear the entire backlog at once
        - Prioritize weak topics first, then user-entered exam dates and recent assessment evidence
        - Calculate trends from the supplied numbers before describing an improvement or decline
        - Do not claim an exam weighting or predicted score impact unless the app snapshot contains that evidence
        - If DP2, emphasize exam technique and consolidation without inventing an exam countdown
        - Tailor pace to their study intensity preset

        CURRENT SESSION CONTEXT:
        """

        // Current time context
        let now = Date()
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "EEEE, d MMMM yyyy 'at' HH:mm"
        prompt += "\n- Current time: \(timeFormatter.string(from: now))"

        // Medical settings are intentionally excluded from provider prompts.
        // They remain local, matching the privacy promise in Settings.

        // Use only dates the learner explicitly saved on subjects.
        if let profileData = try? context.fetch(FetchDescriptor<UserProfile>()).first {
            prompt += "\n- Programme stage: \(profileData.ibYear.shortLabel)"
        }
        let savedExamDates = ((try? context.fetch(FetchDescriptor<Subject>())) ?? [])
            .compactMap { subject -> String? in
                guard let examDate = subject.examDate, examDate > now else { return nil }
                let days = Calendar.current.dateComponents([.day], from: now, to: examDate).day ?? 0
                return "\(subject.name) \(subject.level): \(days) days (\(examDate.formatted(date: .abbreviated, time: .omitted)))"
            }
        if !savedExamDates.isEmpty {
            prompt += "\n- Saved exam dates: \(savedExamDates.joined(separator: "; "))"
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
        var dailyReviewLimit = ReviewDailyLimitPolicy.maximumCards(for: .average)

        if let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first {
            dailyReviewLimit = ReviewDailyLimitPolicy.maximumCards(
                for: profile.studyIntensity,
                dailyGoal: profile.dailyGoal
            )
            let studentName = profile.studentName.isEmpty ? "Student" : profile.studentName
            lines.append("- Student: \(studentName), \(profile.ibYear.shortLabel), target \(profile.targetIBScore)/45, intensity \(profile.studyIntensity.rawValue)")
            lines.append("- Momentum: streak \(profile.currentStreak), total XP \(profile.totalXP), rank \(profile.achievedStep.displayName), daily goal \(profile.dailyGoal) cards")
        }

        let duePredicate = #Predicate<StudyCard> { $0.nextReviewDate <= now }
        let dueCount = (try? context.fetchCount(FetchDescriptor(predicate: duePredicate))) ?? 0
        let overdueDate = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let overduePredicate = #Predicate<StudyCard> { $0.nextReviewDate < overdueDate }
        let overdueCount = (try? context.fetchCount(FetchDescriptor(predicate: overduePredicate))) ?? 0
        lines.append("- Review backlog: \(dueCount) due cards, \(overdueCount) overdue; today's humane ceiling is \(dailyReviewLimit) cards")

        var sessionDescriptor = FetchDescriptor<ReviewSession>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        sessionDescriptor.fetchLimit = maxSnapshotReviewSessions
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
                return "\(subjectName) \(grade.displayTitle): \(grade.scoreSummary)"
            }
            lines.append("- Latest grades: \(recentGrades.joined(separator: "; "))")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Conversation History

    private let tokenToCharRatio = 4
    
    @MainActor
    private func buildConversationHistory(context: ModelContext, queryProfile: QueryProfile, sessionID: UUID) async -> [GeminiMessage] {
        var descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = max(AIConfiguration.conversationWindow * 2, 48)

        guard let storedMessages = try? context.fetch(descriptor) else { return [] }
        let messages = Array(
            storedMessages
                .filter { ChatMessageRole(storedValue: $0.role)?.isConversation == true }
                .prefix(AIConfiguration.conversationWindow)
        )
        guard !messages.isEmpty else { return [] }

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
    private func checkAndCompact(context: ModelContext, sessionID: UUID) async {
        guard AIConfiguration.autoCompactEnabled else { return }

        // Run compaction in a scratch context so a failure can never roll back
        // the app-wide shared context, which would silently discard unrelated
        // pending work (e.g. a plan the user just created).
        let scratch = ModelContext(context.container)

        var descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        descriptor.fetchLimit = maxCompactionMessages

        guard let storedMessages = try? scratch.fetch(descriptor) else { return }
        let allMessages = storedMessages.filter { ChatMessageRole(storedValue: $0.role)?.isConversation == true }
        guard allMessages.count >= minMessagesBeforeCompaction else { return }

        // Rough token estimate, kept in step with the conversation history budget.
        let totalTokens = allMessages.reduce(0) { $0 + estimateTokens(in: $1.content) }

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
            let summary = try await AIProviderService.generateContent(
                messages: [GeminiMessage(role: "user", text: prompt)],
                systemInstruction: "You are a conversation summarizer. Extract and categorize key information."
            )

            // Save compacted summary + archive old messages atomically in the
            // scratch context. On success the changes stage into the shared
            // store; on failure the scratch context is dropped with no side
            // effects on the app-wide context.
            let memory = ARIAMemory(category: .conversationHistory, content: summary, isCompacted: true)
            scratch.insert(memory)
            for msg in toCompact {
                scratch.delete(msg)
            }
            try scratch.save()
        } catch {
            // Nothing to undo: the scratch context is discarded.
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

    @MainActor
    private func buildSubjectKnowledgeBlock(context: ModelContext, queryProfile: QueryProfile) -> String {
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        guard !subjects.isEmpty else { return "" }

        // Prefer subjects explicitly named in the query; otherwise fall back to
        // the most relevant subjects for this message.
        let namedSubjects = subjects.filter {
            queryProfile.normalizedQuery.contains($0.name.lowercased())
        }
        let selected = namedSubjects.isEmpty
            ? subjects.sorted {
                subjectRelevanceScore(for: $0, queryProfile: queryProfile, now: Date())
                    > subjectRelevanceScore(for: $1, queryProfile: queryProfile, now: Date())
            }
            : namedSubjects

        let blocks = selected.prefix(2).compactMap { subject -> String? in
            SubjectKnowledge.knowledge(for: subject.name)?.promptBlock
        }
        return blocks.joined(separator: "\n\n")
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
        let strugglingCards = ProficiencyTracker.strugglingAICards(for: subject).count
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
        let curriculum = SyllabusSeeder.curriculum(for: subject.name, level: subject.level)
        let metadata = SyllabusSeeder.metadata(for: subject.name)
        lines.append("    curriculum: \(curriculum.count) units, \(curriculum.flatMap(\.topics).count) topics, \(curriculum.flatMap(\.topics).flatMap(\.subtopics).count) subunits; source: \(metadata.sourceTitle) \(metadata.sourceURL.absoluteString)")
        if !weakTopics.isEmpty {
            lines.append("    weak topics: \(weakTopics.joined(separator: ", "))")
        }
        if !mentionedTopics.isEmpty {
            lines.append("    query-matched topics: \(mentionedTopics.joined(separator: ", "))")
        }
        if !recentGrades.isEmpty {
            let gradeSummary = recentGrades.map { "\($0.displayTitle) \($0.scoreSummary)" }.joined(separator: ", ")
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

        let curriculumCandidates = SyllabusSeeder.curriculum(for: subject.name, level: subject.level)
            .flatMap { unit in
                [unit.name] + unit.topics.flatMap { [$0.name] + $0.subtopics }
            }
        let cardCandidates = subject.cards.flatMap { [$0.topicName, $0.subtopic] }
        for candidate in curriculumCandidates + cardCandidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key), keywordOverlapScore(in: trimmed, keywords: keywords) > 0 else { continue }
            seen.insert(key)
            topics.append(trimmed)
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
        Self.compactSpecLine(text, limit: limit)
    }

    private func containsAny(_ text: String, phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }

    // MARK: - Greeting

    func generateGreeting(readyCount: Int, deferredCount: Int) -> String {
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        let timeGreeting: String
        if hour < 12 { timeGreeting = "Good morning" }
        else if hour < 18 { timeGreeting = "Good afternoon" }
        else { timeGreeting = "Good evening" }

        if readyCount > 0 {
            if deferredCount > 0 {
                return "\(timeGreeting). \(readyCount) cards are ready today; \(deferredCount) more are safely deferred."
            }
            return "\(timeGreeting). \(readyCount) cards are ready for a focused review."
        }

        if deferredCount > 0 {
            return "\(timeGreeting). Today's review allowance is complete; the remaining backlog can wait."
        }
        return "\(timeGreeting). You're caught up, so there is no review pressure right now."
    }

    // MARK: - Review Session Recording

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
    private static let maxCachedSpecs = 400
    nonisolated(unsafe) private static var cachedRootPath: String?
    nonisolated(unsafe) private static var cachedSpecs: [ARIAActionSpec]?

    static func write(_ spec: ARIAActionSpec) {
        guard let rootURL = rootDirectoryURL() else { return }
        excludeFromBackupIfNeeded(rootURL)

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
            // Non-fatal: the spec store is an optional enrichment. Debug builds
            // surface failures loudly; Release keeps chat working.
            #if DEBUG
            assertionFailure("Failed to write ARIA spec: \(error)")
            #endif
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
        // Bound memory growth on long-running sessions: the disk is the source
        // of truth, the cache is only a recent-window optimization.
        if let specs = cachedSpecs, specs.count > maxCachedSpecs {
            cachedSpecs = Array(specs.prefix(maxCachedSpecs))
        }
    }

    /// The spec store captures user and assistant chat text, so it must not be
    /// synced to iCloud or Time Machine. Runs once on a background queue; the
    /// `resourceValues(forKeys:)` read can block indefinitely in `getxattr` on
    /// some environments, so we set the exclusion directly and never on main.
    nonisolated(unsafe) private static var hasConfiguredSpecExclusion = false

    private static func excludeFromBackupIfNeeded(_ directory: URL) {
        guard !hasConfiguredSpecExclusion else { return }
        hasConfiguredSpecExclusion = true
        DispatchQueue.global(qos: .utility).async {
            var mutable = directory
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? mutable.setResourceValues(resourceValues)
        }
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
    nonisolated(unsafe) private static var cachedRootPath: String?
    nonisolated(unsafe) private static var cachedFilesByCollection: [String: [String]] = [:]
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
