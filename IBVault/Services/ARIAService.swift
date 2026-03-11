import Foundation
import SwiftData
import SwiftUI

@Observable
class ARIAService {
    var isLoading = false
    var currentStreamText = ""
    var isOnline = true
    var suggestedPrompts: [String] = [
        "What should I study today?",
        "Analyse my weakest subject",
        "Make me a study plan for this week",
        "Quiz me on Biology Cell Theory"
    ]

    private let tokenThreshold = 8000

    // MARK: - Chat

    @MainActor
    func sendMessage(
        _ userMessage: String,
        context: ModelContext,
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
        let userChat = ChatMessage(role: "user", content: userMessage)
        context.insert(userChat)
        try? context.save()

        Task {
            do {
                // Build context
                let systemPrompt = await buildSystemPrompt(context: context)
                let messages = await buildConversationHistory(context: context)

                var fullResponse = ""

                let stream = GeminiService.streamContent(
                    messages: messages,
                    systemInstruction: systemPrompt,
                    apiKey: apiKey
                )

                for try await token in stream {
                    fullResponse += token
                    await MainActor.run {
                        self.currentStreamText = fullResponse
                        onToken(token)
                    }
                }

                // Save assistant response
                await MainActor.run {
                    let modelChat = ChatMessage(role: "model", content: fullResponse)
                    context.insert(modelChat)

                    // Auto-update rank from grades after ARIA response
                    self.autoUpdateRank(context: context)

                    try? context.save()

                    self.isLoading = false
                    onComplete(fullResponse)
                }

                // Check if compaction needed
                await checkAndCompact(context: context, apiKey: apiKey)

            } catch {
                await MainActor.run {
                    self.isLoading = false
                    onError(error)
                }
            }
        }
    }

    // MARK: - System Prompt Builder

    func buildSystemPrompt(context: ModelContext) async -> String {
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
        - Generate flashcards (format: "FRONT: [question] | BACK: [answer]")
        - Quiz using Socratic questioning for active recall
        - Explain concepts, structure essays, clarify mark schemes at IB level
        - Track session-by-session and subject-by-subject progress
        - Produce study guides with difficulty ratings and time allocations

        """

        // Inject memory preamble
        let memoryPreamble = await buildMemoryPreamble(context: context)
        if !memoryPreamble.isEmpty {
            prompt += "\nUSER CONTEXT (from memory):\n\(memoryPreamble)\n"
        }

        // Inject app state
        let appState = await buildAppStateSnapshot(context: context)
        prompt += "\nCURRENT APP STATE:\n\(appState)\n"

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

    private func buildMemoryPreamble(context: ModelContext) async -> String {
        let descriptor = FetchDescriptor<ARIAMemory>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        guard let memories = try? context.fetch(descriptor) else { return "" }

        var preamble = ""
        let grouped = Dictionary(grouping: memories) { $0.category }

        for category in MemoryCategory.allCases {
            if let items = grouped[category], !items.isEmpty {
                preamble += "\n[\(category.rawValue)]:\n"
                for item in items.prefix(5) {
                    preamble += "- \(item.content)\n"
                }
            }
        }

        return preamble
    }

    // MARK: - App State Snapshot

    private func buildAppStateSnapshot(context: ModelContext) async -> String {
        var state: [String: Any] = [:]

        // Profile
        if let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first {
            state["streak"] = profile.currentStreak
            state["totalXP"] = profile.totalXP
            state["rank"] = profile.rank.rawValue
            state["studentName"] = profile.studentName.isEmpty ? "Student" : profile.studentName
            state["ibYear"] = profile.ibYear.shortLabel
            state["studyIntensity"] = profile.studyIntensity.rawValue
            state["targetIBScore"] = profile.targetIBScore
            state["dailyGoal"] = profile.dailyGoal
        }

        // Due cards
        let now = Date()
        let duePredicate = #Predicate<StudyCard> { $0.nextReviewDate <= now }
        let dueCount = (try? context.fetchCount(FetchDescriptor(predicate: duePredicate))) ?? 0
        state["dueCards"] = dueCount

        // Subjects — detailed per-subject breakdown
        if let subjects = try? context.fetch(FetchDescriptor<Subject>()) {
            var subjectStates: [[String: Any]] = []
            for s in subjects {
                let weakTopics = ProficiencyTracker.weakTopics(for: s)
                let mastery = ProficiencyTracker.masteryPercentage(for: s)

                // Per-subject session stats (last 7 days)
                let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!
                let subjectSessions = (try? context.fetch(FetchDescriptor<ReviewSession>()))?.filter {
                    $0.subjectName == s.name && $0.timestamp >= weekAgo
                } ?? []
                let avgQuality = subjectSessions.isEmpty ? 0.0 :
                    Double(subjectSessions.map(\.qualityRating).reduce(0, +)) / Double(subjectSessions.count)
                let retention = ProficiencyTracker.retentionRate(from: subjectSessions)

                // Topic-level difficulty breakdown
                let topicBreakdown: [[String: Any]] = s.cards.reduce(into: [String: [StudyCard]]()) { dict, card in
                    dict[card.topicName, default: []].append(card)
                }.map { (topic, cards) in
                    let topicMastery = Double(cards.filter { $0.proficiency == .mastered || $0.proficiency == .proficient }.count) / Double(max(1, cards.count))
                    let avgEase = cards.map(\.easeFactor).reduce(0, +) / Double(max(1, cards.count))
                    let dueCards = cards.filter { $0.nextReviewDate <= now }.count
                    return [
                        "topic": topic,
                        "mastery": Int(topicMastery * 100),
                        "avgEaseFactor": round(avgEase * 100) / 100,
                        "dueCards": dueCards,
                        "totalCards": cards.count
                    ] as [String: Any]
                }

                // Latest grades for this subject
                let subjectGrades = s.grades.sorted { $0.date > $1.date }.prefix(4).map {
                    ["component": $0.component, "score": $0.score] as [String: Any]
                }

                subjectStates.append([
                    "name": s.name,
                    "level": s.level,
                    "totalCards": s.cards.count,
                    "dueCards": s.dueCardsCount,
                    "weakTopicNames": weakTopics.map(\.topicName),
                    "masteryPercent": Int(mastery * 100),
                    "weeklyAvgQuality": round(avgQuality * 10) / 10,
                    "weeklyRetention": Int(retention * 100),
                    "weeklySessions": subjectSessions.count,
                    "topicBreakdown": topicBreakdown,
                    "latestGrades": Array(subjectGrades)
                ])
            }
            state["subjects"] = subjectStates
        }

        // Session-by-session history (last 10 sessions grouped by day)
        let sessionDescriptor = FetchDescriptor<ReviewSession>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        if let sessions = try? context.fetch(sessionDescriptor) {
            let recent = sessions.prefix(50)
            let grouped = Dictionary(grouping: recent) { Calendar.current.startOfDay(for: $0.timestamp) }
            let sessionHistory: [[String: Any]] = grouped.sorted { $0.key > $1.key }.prefix(10).map { (day, daySessions) in
                let subjects = Set(daySessions.map(\.subjectName))
                let avgQ = Double(daySessions.map(\.qualityRating).reduce(0, +)) / Double(max(1, daySessions.count))
                let correct = daySessions.filter(\.wasCorrect).count
                let fmt = DateFormatter(); fmt.dateStyle = .short
                return [
                    "date": fmt.string(from: day),
                    "totalReviews": daySessions.count,
                    "correctCount": correct,
                    "retentionPercent": daySessions.isEmpty ? 0 : correct * 100 / daySessions.count,
                    "avgQuality": round(avgQ * 10) / 10,
                    "subjects": Array(subjects)
                ] as [String: Any]
            }
            state["sessionHistory"] = sessionHistory
        }

        // Recent grades
        let gradeDescriptor = FetchDescriptor<Grade>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        if let grades = try? context.fetch(gradeDescriptor) {
            let recent = grades.prefix(12).map { g in
                ["subject": g.subject?.name ?? "", "component": g.component, "score": g.score] as [String: Any]
            }
            state["recentGrades"] = Array(recent)
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }

    // MARK: - Conversation History

    private func buildConversationHistory(context: ModelContext) async -> [GeminiMessage] {
        let windowSize = UserDefaults.standard.integer(forKey: "ariaContextWindow")
        var descriptor = FetchDescriptor<ChatMessage>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = windowSize > 0 ? windowSize : 20

        guard let messages = try? context.fetch(descriptor) else { return [] }

        return messages.reversed().map { msg in
            GeminiMessage(role: msg.role, text: msg.content)
        }
    }

    // MARK: - Context Compaction

    private func checkAndCompact(context: ModelContext, apiKey: String) async {
        let descriptor = FetchDescriptor<ChatMessage>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )

        guard let allMessages = try? context.fetch(descriptor) else { return }

        // Rough token estimate (4 chars per token)
        let totalTokens = allMessages.reduce(0) { $0 + $1.content.count / 4 }

        guard totalTokens > tokenThreshold else { return }

        // Take the oldest 60% of messages for compaction
        let compactCount = Int(Double(allMessages.count) * 0.6)
        let toCompact = Array(allMessages.prefix(compactCount))

        let conversationText = toCompact.map { "\($0.role): \($0.content)" }.joined(separator: "\n")

        let prompt = """
        Summarize this conversation into a structured memory summary. Extract key facts:
        - User's grades and targets
        - Weak topics identified
        - Study habits observed
        - Personal goals mentioned
        - Key advice given

        Keep it concise (under 500 words). Format as bullet points under categories.

        Conversation:
        \(conversationText)
        """

        do {
            let summary = try await GeminiService.generateContent(
                messages: [GeminiMessage(role: "user", text: prompt)],
                systemInstruction: "You are a conversation summarizer. Extract and categorize key information.",
                apiKey: apiKey
            )

            await MainActor.run {
                // Save compacted summary
                let memory = ARIAMemory(category: .conversationHistory, content: summary, isCompacted: true)
                context.insert(memory)

                // Archive old messages
                for msg in toCompact {
                    context.delete(msg)
                }

                try? context.save()
            }
        } catch {
            print("Compaction failed: \(error)")
        }
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
