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

    private struct GeneratedCardPayload: Decodable, Sendable {
        let front: String
        let back: String
        let hint: String?
        let difficulty: String?
        let skill: String?
        let cardStyle: String?
        let choices: [String]?

        enum CodingKeys: String, CodingKey {
            case front
            case back
            case hint
            case difficulty
            case skill
            case cardStyle
            case choices
        }
    }

    /// Sendable DTO extracted off-main before StudyCard construction.
    struct CardParseDTO: Sendable {
        let front: String
        let back: String
        let hint: String?
        let difficulty: String?
        let skill: String?
        let cardStyle: String?
        let choices: [String]?
    }

    /// Pure, nonisolated extraction of payloads from raw model JSON.
    /// Runs off-main via Task.detached so JSON parsing and string scrubbing
    /// never block the MainActor.
    nonisolated static func extractCardDTOs(from response: String) throws -> [CardParseDTO] {
        var cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let startIdx = cleaned.firstIndex(of: "["),
           let endIdx = cleaned.lastIndex(of: "]") {
            cleaned = String(cleaned[startIdx...endIdx])
            if let data = cleaned.data(using: .utf8),
               let payloads = try? JSONDecoder().decode([GeneratedCardPayload].self, from: data),
               !payloads.isEmpty {
                return payloads.map {
                    CardParseDTO(front: $0.front, back: $0.back, hint: $0.hint, difficulty: $0.difficulty, skill: $0.skill, cardStyle: $0.cardStyle, choices: $0.choices)
                }
            }
        }
        let pairs = parseFrontBackBlocks(from: response)
        guard !pairs.isEmpty else { throw CardGeneratorError.invalidFormat }
        return pairs.map { CardParseDTO(front: $0.0, back: $0.1, hint: nil, difficulty: nil, skill: nil, cardStyle: nil, choices: nil) }
    }

    /// MainActor mapping from Sendable DTOs to StudyCard models. Preserves
    /// dedup, repair-to-basic, and useInternalTools post-processing.
    @MainActor
    static func cardsFromDTOs(
        _ dtos: [CardParseDTO],
        subject: Subject,
        topicName: String,
        subtopic: String,
        profile: AdaptiveProfile,
        options: CardGenerationOptions?
    ) -> [StudyCard] {
        let payloads = dtos.map {
            GeneratedCardPayload(front: $0.front, back: $0.back, hint: $0.hint, difficulty: $0.difficulty, skill: $0.skill, cardStyle: $0.cardStyle, choices: $0.choices)
        }
        let cards = cardsFromPayloads(payloads, subject: subject, topicName: topicName, subtopic: subtopic, profile: profile, options: options)
        if !cards.isEmpty { return cards }
        // Fallback when payloads produced no useful cards but DTOs came from FRONT/BACK blocks.
        let pairs = dtos.map { ($0.front, $0.back) }
        return cardsFromPairs(pairs, subject: subject, topicName: topicName, subtopic: subtopic, profile: profile)
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
        let effectiveOptions = options ?? CardGenerationOptions(
            count: count,
            difficulty: profile.difficulty,
            style: .basic,
            tone: .exam,
            cognitiveSkills: profile.skillMix,
            useInternalTools: false
        )
        // options.count overrides the direct count parameter when options is provided
        let requestedCount = options?.count ?? count
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
                count: min(max(requestedCount, 1), 50),
                startingIndex: localStartingIndex,
                profile: profile,
                options: effectiveOptions
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
        let targetCount = min(max(requestedCount, 1), 50)
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
                    performanceContext: performanceContext,
                    options: effectiveOptions
                )

                do {
                    let response = try await AIProviderService.generateContent(
                        messages: [GeminiMessage(role: "user", text: prompt)],
                        systemInstruction: systemPrompt,
                        modelOverride: model,
                        timeout: model == AIConfiguration.selectedModel ? 120 : 90
                    )
                    let dtos = try await Task.detached(priority: .userInitiated) {
                        try Self.extractCardDTOs(from: response)
                    }.value
                    let parsed = cardsFromDTOs(dtos, subject: subject, topicName: topicName, subtopic: subtopic, profile: profile, options: effectiveOptions)
                    guard !parsed.isEmpty else { throw CardGeneratorError.invalidFormat }
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
        let localOptions = effectiveOptions
        let localCards = localStarterCards(
            subject: subject,
            topicName: topicName,
            subtopic: subtopic,
            count: targetCount,
            startingIndex: localStartingIndex,
            profile: adaptiveProfile(for: subject, topicName: topicName, subtopic: subtopic),
            options: localOptions
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
        localStarterCards(
            subject: subject,
            topicName: topicName,
            subtopic: subtopic,
            count: count,
            startingIndex: startingIndex,
            profile: profile,
            options: nil
        )
    }

    @MainActor
    static func localStarterCards(
        subject: Subject,
        topicName: String,
        subtopic: String,
        count: Int,
        startingIndex: Int = 0,
        profile: AdaptiveProfile,
        options: CardGenerationOptions?
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
        let requestedStyle = options?.style ?? .basic
        return (0..<safeCount).map { index in
            let absoluteIndex = max(startingIndex, 0) + index
            let fact = facts[absoluteIndex]
            let skill = profile.skillMix.isEmpty ? CardCognitiveSkill.recall : profile.skillMix[absoluteIndex % profile.skillMix.count]
            let difficulty = options?.difficulty ?? profile.difficulty
            let factBack = fact.answer
            let factFront: String
            let cardStyle: CardStyle
            let choices: [String]
            switch requestedStyle {
            case .basic:
                factFront = fact.front
                cardStyle = .basic
                choices = []
            case .cloze:
                // Simple cloze from the fact's answer as the deletion.
                // Front uses {{c1::answer}} with deletion equal to back.
                factFront = "Complete: {{c1::\(factBack)}}"
                cardStyle = .cloze
                choices = []
            case .multipleChoice:
                factFront = fact.front
                cardStyle = .multipleChoice
                // Build 3 distractors from other facts + generic fallbacks
                var distractors: [String] = []
                let otherFacts = facts.filter { $0.answer != factBack }
                // Deterministic shuffle by absoluteIndex
                if !otherFacts.isEmpty {
                    let start = absoluteIndex % otherFacts.count
                    for offset in 0..<min(3, otherFacts.count) {
                        let idx = (start + offset) % otherFacts.count
                        let candidate = otherFacts[idx].answer
                        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty, trimmed.lowercased() != factBack.lowercased() {
                            distractors.append(trimmed)
                        }
                    }
                }
                let fallbacks = ["Not applicable", "Insufficient data", "Depends on context"]
                var fallbackIndex = 0
                while distractors.count < 3, fallbackIndex < fallbacks.count {
                    let fb = fallbacks[fallbackIndex]
                    if fb.lowercased() != factBack.lowercased(),
                       !distractors.contains(where: { $0.lowercased() == fb.lowercased() }) {
                        distractors.append(fb)
                    }
                    fallbackIndex += 1
                }
                var allChoices = [factBack] + distractors.prefix(3)
                // Deterministic rotation instead of random
                let rotate = absoluteIndex % allChoices.count
                if rotate > 0 {
                    let prefix = Array(allChoices.prefix(rotate))
                    let suffix = Array(allChoices.suffix(from: rotate))
                    allChoices = suffix + prefix
                }
                choices = Array(allChoices.prefix(4))
            }
            let card = StudyCard(
                topicName: topicName,
                subtopic: subtopic,
                front: factFront,
                back: factBack,
                subject: subject,
                isCustom: false,
                isAIGenerated: false,
                generationSource: "Local syllabus starter",
                hint: fact.hint,
                difficulty: difficulty,
                cognitiveSkill: skill,
                cardStyle: cardStyle,
                choices: choices,
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
        try parseFlashcards(from: response, subject: subject, topicName: topicName, subtopic: subtopic, profile: profile, options: nil)
    }

    static func parseFlashcards(
        from response: String,
        subject: Subject,
        topicName: String,
        subtopic: String,
        profile: AdaptiveProfile? = nil,
        options: CardGenerationOptions?
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
                profile: profile ?? adaptiveProfile(for: subject, topicName: topicName, subtopic: subtopic),
                options: options
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
        cardsFromPayloads(payloads, subject: subject, topicName: topicName, subtopic: subtopic, profile: profile, options: nil)
    }

    private static func cardsFromPayloads(
        _ payloads: [GeneratedCardPayload],
        subject: Subject,
        topicName: String,
        subtopic: String,
        profile: AdaptiveProfile,
        options: CardGenerationOptions?
    ) -> [StudyCard] {
        let metadata = SyllabusSeeder.metadata(for: subject.name)
        let rawCards: [StudyCard] = payloads.compactMap { payload in
            let front = normalizedMath(payload.front).trimmingCharacters(in: .whitespacesAndNewlines)
            let back = normalizedMath(payload.back).trimmingCharacters(in: .whitespacesAndNewlines)
            guard isUsefulAnswer(front: front, back: back) else { return nil }
            let requestedStyle = parsedCardStyle(payload.cardStyle) ?? options?.style ?? .basic
            let difficulty = clampDifficulty(parsedDifficulty(payload.difficulty) ?? profile.difficulty, options: options, profile: profile)
            let skill = parsedSkill(payload.skill) ?? profile.skillMix.first ?? .explain
            let finalFront = front
            var finalStyle = requestedStyle
            var finalChoices: [String] = []
            switch requestedStyle {
            case .basic:
                finalChoices = []
            case .cloze:
                if isValidCloze(front: front, back: back) {
                    finalChoices = []
                } else {
                    // Repair invalid cloze to basic rather than saving broken
                    finalStyle = .basic
                    finalChoices = []
                }
            case .multipleChoice:
                if let validated = validatedChoices(back: back, choices: payload.choices) {
                    finalChoices = validated
                } else {
                    finalStyle = .basic
                    finalChoices = []
                }
            }
            // useInternalTools deterministic enforcement: correct syllabusReference already applied, difficulty clamped, dedup handled downstream
            let syllabusRef = syllabusReference(subject: subject, topicName: topicName, subtopic: subtopic)
            return StudyCard(
                topicName: topicName,
                subtopic: subtopic,
                front: finalFront,
                back: back,
                subject: subject,
                isCustom: false,
                isAIGenerated: true,
                generationSource: AIConfiguration.provider.displayName,
                hint: payload.hint.map(normalizedMath),
                difficulty: difficulty,
                cognitiveSkill: skill,
                cardStyle: finalStyle,
                choices: finalChoices,
                sourceTitle: metadata.sourceTitle,
                sourceURLString: metadata.sourceURL.absoluteString,
                syllabusReference: syllabusRef,
                adaptationReason: profile.reason,
                generationPromptVersion: promptVersion
            )
        }
        // When useInternalTools is true, the generationPrompt tells the model the app handles dedup, but we also enforce it deterministically.
        return deduplicated(rawCards)
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
        generationPrompt(
            subject: subject,
            topicName: topicName,
            subtopic: subtopic,
            count: count,
            excludingFronts: excludingFronts,
            profile: profile,
            syllabusVersion: syllabusVersion,
            performanceContext: performanceContext,
            options: nil
        )
    }

    private static func generationPrompt(
        subject: Subject,
        topicName: String,
        subtopic: String,
        count: Int,
        excludingFronts: [String],
        profile: AdaptiveProfile,
        syllabusVersion: String,
        performanceContext: AcademicPerformanceContext,
        options: CardGenerationOptions?
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
        let effectiveOptions = options ?? CardGenerationOptions(count: count, difficulty: profile.difficulty, style: .basic, tone: .exam, cognitiveSkills: profile.skillMix, useInternalTools: false)
        let styleLine: String = switch effectiveOptions.style {
        case .basic: "- Card style: basic — front is a clear question, back is the answer."
        case .cloze: "- Card style: cloze — front must contain a single deletion as {{c1::answer}} where the deletion text equals the back exactly (trimmed). Example: front \"The {{c1::mitochondrion}} is the powerhouse...\" with back \"mitochondrion\"."
        case .multipleChoice: "- Card style: multiple_choice — front is the stem, back is the correct answer, and choices must be 3-4 unique options with exactly one equal to the back (case-insensitive trimmed)."
        }
        let toneLine = "- Tone: \(effectiveOptions.tone.rawValue) — adapt phrasing to this voice while keeping accuracy."
        let internalToolsLine = effectiveOptions.useInternalTools
            ? "- The app performs curriculum-reference lookup, duplicate detection, and scheduling with its internal tools. Focus on content quality; the app will assign syllabusReference, deduplicate by normalized front, and clamp difficulty to \(effectiveOptions.difficulty.rawValue)."
            : ""
        let jsonExample: String = switch effectiveOptions.style {
        case .basic:
            """
            [
              {"front": "question text here", "back": "answer text here", "hint": "small cue", "difficulty": "\(profile.difficulty.rawValue)", "skill": "\(profile.skillMix.first?.rawValue ?? CardCognitiveSkill.explain.rawValue)", "cardStyle": "basic"},
              {"front": "question text here", "back": "answer text here", "hint": "small cue", "difficulty": "\(profile.difficulty.rawValue)", "skill": "\(profile.skillMix.last?.rawValue ?? CardCognitiveSkill.apply.rawValue)", "cardStyle": "basic"}
            ]
            """
        case .cloze:
            """
            [
              {"front": "The {{c1::mitochondrion}} produces ATP via cellular respiration.", "back": "mitochondrion", "hint": "powerhouse of the cell", "difficulty": "\(profile.difficulty.rawValue)", "skill": "\(profile.skillMix.first?.rawValue ?? CardCognitiveSkill.recall.rawValue)", "cardStyle": "cloze"},
              {"front": "Photosynthesis converts {{c1::carbon dioxide}} and water into glucose.", "back": "carbon dioxide", "hint": "reactant from air", "difficulty": "\(profile.difficulty.rawValue)", "skill": "\(profile.skillMix.last?.rawValue ?? CardCognitiveSkill.apply.rawValue)", "cardStyle": "cloze"}
            ]
            """
        case .multipleChoice:
            """
            [
              {"front": "Which organelle produces ATP?", "back": "Mitochondrion", "hint": "powerhouse", "difficulty": "\(profile.difficulty.rawValue)", "skill": "\(profile.skillMix.first?.rawValue ?? CardCognitiveSkill.recall.rawValue)", "cardStyle": "multiple_choice", "choices": ["Mitochondrion", "Chloroplast", "Nucleus", "Ribosome"]},
              {"front": "What is opportunity cost?", "back": "Value of the next best alternative foregone", "hint": "choice trade-off", "difficulty": "\(profile.difficulty.rawValue)", "skill": "\(profile.skillMix.last?.rawValue ?? CardCognitiveSkill.explain.rawValue)", "cardStyle": "multiple_choice", "choices": ["Value of the next best alternative foregone", "Total revenue minus cost", "Price times quantity", "Marginal benefit"]}
            ]
            """
        }

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
        \(styleLine)
        \(toneLine)
        \(internalToolsLine)
        - Every card must be materially distinct from the others\(excludingFronts.isEmpty ? "" : " and must not repeat the excluded question fronts")
        \(exclusionLines)

        RESPOND IN EXACTLY THIS JSON FORMAT (no markdown, no code fences, just raw JSON):
        \(jsonExample)
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

    private static func parsedCardStyle(_ rawValue: String?) -> CardStyle? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let lower = trimmed.lowercased()
        // Support both "multiple_choice" and "multipleChoice" spellings
        if lower == "multiplechoice" || lower == "multiple_choice" || lower == "multiple-choice" {
            return .multipleChoice
        }
        return CardStyle.allCases.first { $0.rawValue.lowercased() == lower }
    }

    private static func normalizedMath(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\(", with: "$")
            .replacingOccurrences(of: "\\)", with: "$")
            .replacingOccurrences(of: "\\[", with: "$$")
            .replacingOccurrences(of: "\\]", with: "$$")
    }

    // MARK: - Card style validation (P0)

    nonisolated static func isValidCloze(front: String, back: String) -> Bool {
        let trimmedBack = back.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBack.isEmpty else { return false }
        // Front must contain exactly {{c1::back}} with trimmed equality
        // Use regex to extract deletion
        let pattern = #"\{\{c1::(.*?)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        let nsFront = front as NSString
        let matches = regex.matches(in: front, options: [], range: NSRange(location: 0, length: nsFront.length))
        guard matches.count == 1,
              let range = Range(matches[0].range(at: 1), in: front) else { return false }
        let deletion = String(front[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return deletion == trimmedBack
    }

    nonisolated static func validatedChoices(back: String, choices: [String]?) -> [String]? {
        guard let choices, choices.count >= 3, choices.count <= 4 else { return nil }
        let trimmedBack = back.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBack.isEmpty else { return nil }
        let trimmedChoices = choices.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard trimmedChoices.count >= 3, trimmedChoices.count <= 4 else { return nil }
        // Unique case-insensitive trimmed
        var seenLower = Set<String>()
        var unique: [String] = []
        for choice in trimmedChoices {
            let lower = choice.lowercased()
            if seenLower.contains(lower) { return nil }
            seenLower.insert(lower)
            unique.append(choice)
        }
        // Exactly one must equal back case-insensitive trimmed
        let matchingCount = unique.filter { $0.lowercased() == trimmedBack.lowercased() }.count
        guard matchingCount == 1 else { return nil }
        return unique
    }

    nonisolated static func clampDifficulty(_ difficulty: CardDifficulty, options: CardGenerationOptions?, profile: AdaptiveProfile) -> CardDifficulty {
        // When useInternalTools is true, clamp to the options-chosen difficulty if provided.
        if let options, options.useInternalTools {
            return options.difficulty
        }
        // Otherwise ensure difficulty is a valid enum case (already guaranteed) — no clamp needed.
        // But also respect options difficulty when it differs from profile.
        if let options {
            return options.difficulty
        }
        return difficulty
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

    nonisolated private static func parseFrontBackBlocks(from response: String) -> [(String, String)] {
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
