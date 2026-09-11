import Foundation
import SwiftData

struct CardGeneratorService {
    private static let fallbackModels = ["gemini-2.0-flash", "gemini-2.0-flash-lite"]
    static let promptVersion = 2

    struct AdaptiveProfile: Equatable, Sendable {
        let difficulty: CardDifficulty
        let skillMix: [CardCognitiveSkill]
        let reason: String
    }

    struct CoverageResult {
        let cards: [StudyCard]
        let coveredSubtopics: Int
        let skippedSubtopics: Int
        let failures: [String]
    }

    struct AcademicPerformanceContext: Sendable, Equatable {
        let evidence: ProgressEvidence
        let teacherFeedback: String?

        var promptSummary: String {
            var parts: [String] = []
            if let evidence = evidence.assessmentEvidence {
                parts.append("Approved school evidence: \(Int(evidence * 100))% from \(self.evidence.scoredAssessmentCount) scored record(s).")
            }
            if let teacherFeedback, !teacherFeedback.isEmpty {
                parts.append("Latest teacher feedback: \(teacherFeedback)")
            }
            return parts.isEmpty ? "No approved school-performance evidence is available for this scope." : parts.joined(separator: " ")
        }
    }

    private struct GeneratedCardPayload: Decodable {
        let front: String
        let back: String
        let hint: String?
        let difficulty: String?
        let skill: String?
    }

    /// Generate flashcards for a specific topic using ARIA/Gemini.
    ///
    /// Isolation contract: the generator reads/writes `Subject`/`StudyCard`
    /// model objects and must run on the main actor, where every current caller
    /// already executes (ARIAService, TopicBrowserView, ReviewSessionView,
    /// ActiveStudySessionView). The pure parsing/scoring helpers
    /// (`parseFlashcards`, `adaptiveProfile`) stay nonisolated because the test
    /// suite exercises them from non-isolated contexts; they only construct or
    /// read detached models and never touch a `ModelContext`.
    @MainActor
    static func generateCards(
        subject: Subject,
        topicName: String,
        subtopic: String = "",
        count: Int = 10,
        localStartingIndex: Int = 0,
        context: ModelContext,
        preferredDifficulty: CardDifficulty? = nil,
        options: CardGenerationOptions? = nil
    ) async throws -> [StudyCard] {
        let performanceContext = academicPerformanceContext(
            subject: subject,
            topicName: topicName,
            subtopic: subtopic,
            context: context
        )
        let adaptive = adaptiveProfile(
            for: subject,
            topicName: topicName,
            subtopic: subtopic,
            evidence: performanceContext.evidence.assessmentEvidence
        )
        let selectedDifficulty = options?.difficulty ?? preferredDifficulty
        let selectedSkills = options.map { $0.resolvedSkills(fallback: adaptive.skillMix) } ?? adaptive.skillMix
        let profile: AdaptiveProfile
        if selectedDifficulty != nil || options?.cognitiveSkills.isEmpty == false {
            profile = AdaptiveProfile(
                difficulty: selectedDifficulty ?? adaptive.difficulty,
                skillMix: selectedSkills,
                reason: "Learner-selected card studio settings: \(selectedDifficulty?.rawValue ?? adaptive.difficulty.rawValue) difficulty."
            )
        } else {
            profile = adaptive
        }
        let metadata = SyllabusSeeder.metadata(for: subject.name)
        let remoteAvailable: Bool = switch AIConfiguration.provider {
        case .gemini: KeychainService.hasAPIKey
        case .junali: KeychainService.hasJunaliAPIKey
        case .codexCLI: true
        }
        if !remoteAvailable {
            return localStarterCards(
                subject: subject,
                topicName: topicName,
                subtopic: subtopic,
                count: min(max(count, 1), 50),
                startingIndex: localStartingIndex,
                profile: profile
            )
        }
        let isPersonalCourse = subject.name == SyllabusSeeder.lifeCourseName ||
            subject.name == "Advanced Mathematics" || subject.name == "Fundamentals of the Universe"
        let courseType = isPersonalCourse ? "personal course" : "International Baccalaureate course"
        let systemPrompt = """
        Role: You create precise, adaptive flashcards for a \(courseType).

        Goal: Produce cards aligned to the supplied \(subject.level) curriculum scope and the learner's current performance.

        Success criteria:
        - every card tests one clear idea
        - questions span the requested cognitive skills
        - every back is a self-contained answer, not an instruction to go and produce an answer
        - answers teach the definition, mechanism, example, or reasoning needed to self-correct
        - equations use valid LaTeX with $...$ inline and $$...$$ for display math
        - no invented citations, syllabus codes, quotations, or statistics
        - output only a valid JSON array matching the requested schema
        """

        let modelsToTry: [String?]
        if AIConfiguration.provider == .gemini {
            let selected = AIConfiguration.model(for: .gemini)
            modelsToTry = ([selected] + fallbackModels.filter { $0 != selected }).map(Optional.some)
        } else {
            modelsToTry = [nil]
        }
        // Bounded regardless of what the caller passes, so a rogue or stale
        // cardCount can never trigger an unbounded generation loop.
        let targetCount = min(max(count, 1), 50)
        var collectedCards: [StudyCard] = []
        var lastError: (any Error)?

        for model in modelsToTry {
            for _ in 0..<2 {
                let remaining = targetCount - collectedCards.count
                guard remaining > 0 else {
                    return Array(collectedCards.prefix(targetCount))
                }

                let prompt = generationPrompt(
                    subject: subject,
                    topicName: topicName,
                    subtopic: subtopic,
                    count: remaining,
                    excludingFronts: collectedCards.map(\.front),
                    profile: profile,
                    syllabusVersion: metadata.catalogVersion,
                    performanceContext: performanceContext
                )

                do {
                    let response = try await AIProviderService.generateContent(
                        messages: [GeminiMessage(role: "user", text: prompt)],
                        systemInstruction: systemPrompt,
                        modelOverride: model,
                        timeout: model == AIConfiguration.selectedModel ? 120 : 90
                    )
                    let parsed = try parseFlashcards(
                        from: response,
                        subject: subject,
                        topicName: topicName,
                        subtopic: subtopic,
                        profile: profile
                    )
                    let merged = mergeUnique(existing: collectedCards, incoming: parsed)
                    let addedCount = merged.count - collectedCards.count
                    collectedCards = merged

                    if collectedCards.count >= targetCount {
                        return Array(collectedCards.prefix(targetCount))
                    }

                    if addedCount == 0 {
                        break
                    }
                } catch {
                    lastError = error
                    break
                }
            }
        }

        if !collectedCards.isEmpty {
            return collectedCards
        }
        // A study session must remain usable when the provider is offline,
        // unauthenticated, rate-limited, or returns malformed JSON. These
        // syllabus-grounded starter cards are intentionally explicit about
        // the learner's task, so they are still useful as retrieval prompts
        // and can be replaced by richer ARIA cards on the next batch.
        let localCards = localStarterCards(
            subject: subject,
            topicName: topicName,
            subtopic: subtopic,
            count: targetCount,
            startingIndex: localStartingIndex,
            profile: adaptiveProfile(for: subject, topicName: topicName, subtopic: subtopic)
        )
        if !localCards.isEmpty {
            return localCards
        }
        throw lastError ?? CardGeneratorError.noCardsGenerated
    }

    @MainActor
    static func localStarterCards(
        subject: Subject,
        topicName: String,
        subtopic: String,
        count: Int,
        startingIndex: Int = 0,
        profile: AdaptiveProfile
    ) -> [StudyCard] {
        guard let knowledge = SubjectKnowledge.knowledge(for: subject.name) else { return [] }
        let facts = knowledge.keyConcepts.map { statement in
            let label = statement.components(separatedBy: ":").first?
                .components(separatedBy: ",").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? statement
            return (front: "What should you understand about \(label)?", answer: statement, hint: "Reconstruct the core idea before revealing it.")
        } + knowledge.commonMisconceptions.map { statement in
            let claim = statement.components(separatedBy: " — ").first ?? statement
            return (front: "Why is this claim misleading: \"\(claim)\"?", answer: statement, hint: "Identify the correction and explain why it matters.")
        }
        guard !facts.isEmpty else { return [] }
        let metadata = SyllabusSeeder.metadata(for: subject.name)
        let safeCount = min(max(count, 1), min(50, max(0, facts.count - max(startingIndex, 0))))
        return (0..<safeCount).map { index in
            let absoluteIndex = max(startingIndex, 0) + index
            let fact = facts[absoluteIndex]
            let skill = profile.skillMix.isEmpty ? CardCognitiveSkill.recall : profile.skillMix[absoluteIndex % profile.skillMix.count]
            let card = StudyCard(
                topicName: topicName,
                subtopic: subtopic,
                front: fact.front,
                back: fact.answer,
                subject: subject,
                isCustom: false,
                isAIGenerated: false,
                generationSource: "Local syllabus starter",
                hint: fact.hint,
                difficulty: profile.difficulty,
                cognitiveSkill: skill,
                sourceTitle: metadata.sourceTitle,
                sourceURLString: metadata.sourceURL.absoluteString,
                syllabusReference: syllabusReference(subject: subject, topicName: topicName, subtopic: subtopic),
                adaptationReason: "Offline source-grounded starter: \(profile.reason)",
                generationPromptVersion: promptVersion
            )
            return card
        }
    }

    @MainActor
    static func generateCoverage(
        subject: Subject,
        topic: CurriculumTopic,
        cardsPerSubtopic: Int,
        context: ModelContext,
        onProgress: @escaping @MainActor (_ current: Int, _ total: Int, _ subtopic: String) -> Void
    ) async -> CoverageResult {
        let target = max(cardsPerSubtopic, 1)
        var generated: [StudyCard] = []
        var coveredSubtopics = 0
        var skippedSubtopics = 0
        var failures: [String] = []

        for (index, subtopic) in topic.subtopics.enumerated() {
            onProgress(index + 1, topic.subtopics.count, subtopic)
            let existingCount = subject.cards.filter {
                $0.topicName == topic.name && $0.subtopic == subtopic
            }.count
            let remaining = max(target - existingCount, 0)

            guard remaining > 0 else {
                coveredSubtopics += 1
                skippedSubtopics += 1
                continue
            }

            do {
                let cards = try await generateCards(
                    subject: subject,
                    topicName: topic.name,
                    subtopic: subtopic,
                    count: remaining,
                    context: context
                )
                generated.append(contentsOf: cards)
                if existingCount + cards.count >= target {
                    coveredSubtopics += 1
                } else {
                    failures.append("\(subtopic) returned only \(cards.count) of \(remaining) requested cards")
                }
            } catch {
                failures.append("\(subtopic): \(error.localizedDescription)")
            }
        }

        return CoverageResult(
            cards: generated,
            coveredSubtopics: coveredSubtopics,
            skippedSubtopics: skippedSubtopics,
            failures: failures
        )
    }

    /// Parse ARIA's response into StudyCard objects
    static func parseFlashcards(
        from response: String,
        subject: Subject,
        topicName: String,
        subtopic: String,
        profile: AdaptiveProfile? = nil
    ) throws -> [StudyCard] {
        // Clean response — strip markdown code fences if present
        var cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Find the JSON array
        guard let startIdx = cleaned.firstIndex(of: "["),
              let endIdx = cleaned.lastIndex(of: "]") else {
            throw CardGeneratorError.invalidFormat
        }
        cleaned = String(cleaned[startIdx...endIdx])

        if let data = cleaned.data(using: .utf8),
           let payloads = try? JSONDecoder().decode([GeneratedCardPayload].self, from: data) {
            let cards = cardsFromPayloads(
                payloads,
                subject: subject,
                topicName: topicName,
                subtopic: subtopic,
                profile: profile ?? adaptiveProfile(for: subject, topicName: topicName, subtopic: subtopic)
            )
            if !cards.isEmpty {
                return cards
            }
        }

        let textPairs = parseFrontBackBlocks(from: response)
        let cards = cardsFromPairs(
            textPairs,
            subject: subject,
            topicName: topicName,
            subtopic: subtopic,
            profile: profile ?? adaptiveProfile(for: subject, topicName: topicName, subtopic: subtopic)
        )
        guard !cards.isEmpty else { throw CardGeneratorError.invalidFormat }
        return cards
    }

    private static func cardsFromPayloads(
        _ payloads: [GeneratedCardPayload],
        subject: Subject,
        topicName: String,
        subtopic: String,
        profile: AdaptiveProfile
    ) -> [StudyCard] {
        let metadata = SyllabusSeeder.metadata(for: subject.name)
        return deduplicated(payloads.compactMap { payload in
            let front = normalizedMath(payload.front).trimmingCharacters(in: .whitespacesAndNewlines)
            let back = normalizedMath(payload.back).trimmingCharacters(in: .whitespacesAndNewlines)
            guard isUsefulAnswer(front: front, back: back) else { return nil }
            return StudyCard(
                topicName: topicName,
                subtopic: subtopic,
                front: front,
                back: back,
                subject: subject,
                isCustom: false,
                isAIGenerated: true,
                generationSource: AIConfiguration.provider.displayName,
                hint: payload.hint.map(normalizedMath),
                difficulty: parsedDifficulty(payload.difficulty) ?? profile.difficulty,
                cognitiveSkill: parsedSkill(payload.skill) ?? profile.skillMix.first ?? .explain,
                sourceTitle: metadata.sourceTitle,
                sourceURLString: metadata.sourceURL.absoluteString,
                syllabusReference: syllabusReference(subject: subject, topicName: topicName, subtopic: subtopic),
                adaptationReason: profile.reason,
                generationPromptVersion: promptVersion
            )
        })
    }

    private static func cardsFromPairs(
        _ pairs: [(String, String)],
        subject: Subject,
        topicName: String,
        subtopic: String,
        profile: AdaptiveProfile
    ) -> [StudyCard] {
        let metadata = SyllabusSeeder.metadata(for: subject.name)
        var cards: [StudyCard] = []
        for (frontRaw, backRaw) in pairs {
            let front = normalizedMath(frontRaw).trimmingCharacters(in: .whitespacesAndNewlines)
            let back = normalizedMath(backRaw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard isUsefulAnswer(front: front, back: back) else { continue }
            cards.append(StudyCard(
                topicName: topicName,
                subtopic: subtopic,
                front: front,
                back: back,
                subject: subject,
                isCustom: false,
                isAIGenerated: true,
                generationSource: AIConfiguration.provider.displayName,
                difficulty: profile.difficulty,
                cognitiveSkill: profile.skillMix.first ?? .explain,
                sourceTitle: metadata.sourceTitle,
                sourceURLString: metadata.sourceURL.absoluteString,
                syllabusReference: syllabusReference(subject: subject, topicName: topicName, subtopic: subtopic),
                adaptationReason: profile.reason,
                generationPromptVersion: promptVersion
            ))
        }
        return deduplicated(cards)
    }

    private static func generationPrompt(
        subject: Subject,
        topicName: String,
        subtopic: String,
        count: Int,
        excludingFronts: [String],
        profile: AdaptiveProfile,
        syllabusVersion: String,
        performanceContext: AcademicPerformanceContext
    ) -> String {
        let unitPart = SyllabusSeeder.unitName(for: subject.name, level: subject.level, topicName: topicName).map { "\nUnit: \($0)" } ?? ""
        let subtopicPart = subtopic.isEmpty ? "" : "\nSubtopic: \(subtopic)"
        let validSubtopics = SyllabusSeeder.subtopics(for: subject.name, level: subject.level, topicName: topicName)
        let scopeLine = validSubtopics.isEmpty ? "" : "\nValid syllabus subtopics: \(validSubtopics.joined(separator: "; "))"
        let exclusionLines = excludingFronts.isEmpty
            ? ""
            : "\nAlready generated question fronts to avoid repeating:\n" + excludingFronts.prefix(20).map { "- \($0)" }.joined(separator: "\n")

        let isPersonalCourse = subject.name == SyllabusSeeder.lifeCourseName ||
            subject.name == "Advanced Mathematics" || subject.name == "Fundamentals of the Universe"
        let courseLabel = isPersonalCourse ? "personal course" : "IB course"
        let levelRules = isPersonalCourse
            ? "- Treat this as a practical personal curriculum; do not invent IB exams, mark schemes, or assessment rules"
            : "- Match IB exam style where useful and do not include HL-only content for an SL subject"

        return """
        Generate exactly \(count) high-quality flashcards for this \(courseLabel):
        Subject: \(subject.name) \(subject.level)
        Curriculum catalog: \(syllabusVersion)
        Topic: \(topicName)\(unitPart)\(subtopicPart)\(scopeLine)
        Adaptive target: \(profile.difficulty.rawValue)
        Cognitive skills: \(profile.skillMix.map(\.rawValue).joined(separator: ", "))
        Adaptation reason: \(profile.reason)
        School-performance context: \(performanceContext.promptSummary)

        REQUIREMENTS:
        - Each card must test a SPECIFIC concept, fact, definition, or application
        - Every card must stay anchored to the named unit/topic and avoid unrelated areas
        - The back must directly answer the front with the actual definition, mechanism, worked step, example, or reason
        - Never use an instruction-only back such as "draw a diagram", "define the term", "state the model", or "explain why"
        - Answers should be concise but complete enough to self-correct without another source
        - Use the requested cognitive-skill mix instead of making every card simple recall
        - Include a short useful hint that does not reveal the answer
        - For science/math: include formulas, calculations, units, assumptions, and diagram interpretation where relevant
        - For humanities: include precise concepts, application, counterarguments, and evaluation where relevant
        \(levelRules)
        - Use $...$ for inline equations and $$...$$ for display equations; never use Unicode-only equation substitutes when LaTeX is clearer
        - Every card must be materially distinct from the others\(excludingFronts.isEmpty ? "" : " and must not repeat the excluded question fronts")
        \(exclusionLines)

        RESPOND IN EXACTLY THIS JSON FORMAT (no markdown, no code fences, just raw JSON):
        [
          {"front": "question text here", "back": "answer text here", "hint": "small cue", "difficulty": "\(profile.difficulty.rawValue)", "skill": "\(profile.skillMix.first?.rawValue ?? CardCognitiveSkill.explain.rawValue)"},
          {"front": "question text here", "back": "answer text here", "hint": "small cue", "difficulty": "\(profile.difficulty.rawValue)", "skill": "\(profile.skillMix.last?.rawValue ?? CardCognitiveSkill.apply.rawValue)"}
        ]
        """
    }

    static func adaptiveProfile(for subject: Subject, topicName: String, subtopic: String, evidence: Double? = nil) -> AdaptiveProfile {
        let scoped = subject.cards.filter { card in
            card.topicName == topicName && (subtopic.isEmpty || card.subtopic == subtopic)
        }
        let reviewed = scoped.filter { $0.totalReviewCount > 0 }
        if let evidence, evidence < 0.55 {
            return AdaptiveProfile(
                difficulty: .foundation,
                skillMix: [.recall, .explain, .apply],
                reason: "Approved school evidence is below target, so the set rebuilds the assessed prerequisite knowledge."
            )
        }
        guard !reviewed.isEmpty else {
            if let evidence, evidence >= 0.85 {
                return AdaptiveProfile(
                    difficulty: .exam,
                    skillMix: [.apply, .analyze, .evaluate],
                    reason: "School performance is strong, so the set targets exam transfer before expanding coverage."
                )
            }
            return AdaptiveProfile(
                difficulty: .standard,
                skillMix: [.recall, .explain, .apply],
                reason: "No recall history exists for this scope, so the set establishes a balanced baseline."
            )
        }

        let totalReviews = reviewed.reduce(0) { $0 + $1.totalReviewCount }
        let successful = reviewed.reduce(0) { $0 + $1.successfulReviewCount }
        let successRate = totalReviews == 0 ? 0 : Double(successful) / Double(totalReviews)
        let strugglingShare = Double(reviewed.filter(\.isStruggling).count) / Double(reviewed.count)

        if successRate < 0.55 || strugglingShare >= 0.35 {
            return AdaptiveProfile(
                difficulty: .foundation,
                skillMix: [.recall, .explain, .apply],
                reason: "Recent recall is below target, so the set rebuilds prerequisite knowledge before exam transfer."
            )
        }
        if successRate >= 0.82 && reviewed.allSatisfy({ $0.proficiency == .proficient || $0.proficiency == .mastered }) {
            return AdaptiveProfile(
                difficulty: .stretch,
                skillMix: [.apply, .analyze, .evaluate],
                reason: "Recall is strong in this scope, so the set increases transfer, synthesis, and evaluation demands."
            )
        }
        return AdaptiveProfile(
            difficulty: .exam,
            skillMix: [.explain, .apply, .analyze],
            reason: "Recall is developing, so the set targets exam-style explanation and application."
        )
    }

    @MainActor
    private static func academicPerformanceContext(
        subject: Subject,
        topicName: String,
        subtopic: String,
        context: ModelContext
    ) -> AcademicPerformanceContext {
        let assessments = ((try? context.fetch(FetchDescriptor<AcademicAssessment>())) ?? []).filter {
            $0.subjectName.caseInsensitiveCompare(subject.name) == .orderedSame &&
                $0.courseLevel.caseInsensitiveCompare(subject.level) == .orderedSame
        }
        let mappings = ((try? context.fetch(FetchDescriptor<AcademicAssessmentMapping>())) ?? []).filter {
            $0.subjectName.caseInsensitiveCompare(subject.name) == .orderedSame &&
                $0.courseLevel.caseInsensitiveCompare(subject.level) == .orderedSame
        }
        let reports = ((try? context.fetch(FetchDescriptor<AcademicReportSnapshot>())) ?? [])
            .filter {
                $0.subjectName.caseInsensitiveCompare(subject.name) == .orderedSame &&
                    $0.courseLevel.caseInsensitiveCompare(subject.level) == .orderedSame
            }
            .sorted { ($0.reportDate ?? .distantPast) > ($1.reportDate ?? .distantPast) }
        let cards = subject.cards.filter { $0.topicName == topicName && (subtopic.isEmpty || $0.subtopic == subtopic) }
        let evidence = ProgressEvidenceService.score(
            subjectName: subject.name,
            courseLevel: subject.level,
            topicName: topicName,
            subtopicName: subtopic,
            cards: cards,
            assessments: assessments,
            mappings: mappings
        )
        let feedback = reports.first(where: { !$0.teacherComment.isEmpty })?.teacherComment
        return AcademicPerformanceContext(evidence: evidence, teacherFeedback: feedback)
    }

    private static func parsedDifficulty(_ rawValue: String?) -> CardDifficulty? {
        guard let rawValue else { return nil }
        return CardDifficulty.allCases.first { $0.rawValue.caseInsensitiveCompare(rawValue) == .orderedSame }
    }

    private static func parsedSkill(_ rawValue: String?) -> CardCognitiveSkill? {
        guard let rawValue else { return nil }
        return CardCognitiveSkill.allCases.first { $0.rawValue.caseInsensitiveCompare(rawValue) == .orderedSame }
    }

    private static func normalizedMath(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\(", with: "$")
            .replacingOccurrences(of: "\\)", with: "$")
            .replacingOccurrences(of: "\\[", with: "$$")
            .replacingOccurrences(of: "\\]", with: "$$")
    }

    private static func syllabusReference(subject: Subject, topicName: String, subtopic: String) -> String {
        let parts = [
            subject.name + " " + subject.level,
            SyllabusSeeder.unitName(for: subject.name, level: subject.level, topicName: topicName),
            topicName,
            subtopic.isEmpty ? nil : subtopic
        ].compactMap { $0 }
        return parts.joined(separator: " > ")
    }

    private static func parseFrontBackBlocks(from response: String) -> [(String, String)] {
        let normalized = response.replacingOccurrences(of: "\r\n", with: "\n")
        let pattern = #"FRONT:\s*(.*?)\nBACK:\s*(.*?)(?=\n\s*FRONT:|\z)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }
        let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        return regex.matches(in: normalized, options: [], range: nsRange).compactMap { match in
            guard
                let frontRange = Range(match.range(at: 1), in: normalized),
                let backRange = Range(match.range(at: 2), in: normalized)
            else { return nil }
            return (String(normalized[frontRange]), String(normalized[backRange]))
        }
    }

    private static func deduplicated(_ cards: [StudyCard]) -> [StudyCard] {
        var seen = Set<String>()
        return cards.filter { card in
            let key = normalizedQuestionKey(card.front)
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    nonisolated static func isUsefulAnswer(front: String, back: String) -> Bool {
        let cleanedFront = front.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedBack = back.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedFront.isEmpty, !cleanedBack.isEmpty else { return false }
        guard normalizedQuestionKey(cleanedFront) != normalizedQuestionKey(cleanedBack) else { return false }

        let lower = cleanedBack.lowercased()
        let instructionOnlyPrefixes = [
            "draw a diagram", "do a diagram", "define ", "state ", "name what", "write the chain",
            "choose a concrete", "give a precise definition", "explain why", "describe ", "use the command term"
        ]
        if instructionOnlyPrefixes.contains(where: { lower.hasPrefix($0) }) {
            let explanatoryMarkers = [" is ", " are ", " means ", " because ", " therefore ", " refers to ", " results in ", " leads to "]
            guard explanatoryMarkers.contains(where: { lower.contains($0) }) else { return false }
        }
        return true
    }

    nonisolated private static func normalizedQuestionKey(_ value: String) -> String {
        value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func mergeUnique(existing: [StudyCard], incoming: [StudyCard]) -> [StudyCard] {
        deduplicated(existing + incoming)
    }
}

enum CardGeneratorError: Error, LocalizedError, Sendable {
    case invalidFormat
    case noCardsGenerated

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "ARIA returned an unexpected format. Try again."
        case .noCardsGenerated: return "No cards could be parsed from ARIA's response."
        }
    }
}
