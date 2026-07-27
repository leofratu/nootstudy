import Testing
import Foundation
import SwiftData
@testable import IBVault

@Suite("Adaptive Card Generator Tests")
struct CardGeneratorServiceTests {
    @Test("A new topic starts with a balanced baseline")
    func newTopicProfile() {
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        let profile = CardGeneratorService.adaptiveProfile(
            for: subject,
            topicName: "Cells and Cell Structure",
            subtopic: "Prokaryotic cell structure"
        )

        #expect(profile.difficulty == .standard)
        #expect(profile.skillMix == [.recall, .explain, .apply])
    }

    @Test("Low recall generates foundation cards")
    func strugglingTopicProfile() {
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        let card = StudyCard(topicName: "Genetics", subtopic: "Genes, alleles and the genome", front: "Q", back: "A", subject: subject)
        card.totalReviewCount = 10
        card.successfulReviewCount = 3
        card.proficiency = .novice
        subject.cards.append(card)

        let profile = CardGeneratorService.adaptiveProfile(for: subject, topicName: "Genetics", subtopic: "Genes, alleles and the genome")
        #expect(profile.difficulty == .foundation)
    }

    @Test("Strong recall generates transfer-heavy stretch cards")
    func strongTopicProfile() {
        let subject = Subject(name: "Economics", level: "HL", accentColorHex: "F59E0B")
        let card = StudyCard(topicName: "Demand", subtopic: "The law of demand", front: "Q", back: "A", subject: subject)
        card.totalReviewCount = 10
        card.successfulReviewCount = 9
        card.proficiency = .mastered
        subject.cards.append(card)

        let profile = CardGeneratorService.adaptiveProfile(for: subject, topicName: "Demand", subtopic: "The law of demand")
        #expect(profile.difficulty == .stretch)
        #expect(profile.skillMix.contains(.evaluate))
    }

    @Test("Generated JSON preserves metadata and normalizes math delimiters")
    func parsesRichCardPayload() throws {
        let subject = Subject(name: "Mathematics AA", level: "SL", accentColorHex: "3B82F6")
        let response = #"[{"front":"Differentiate \\(x^2\\)","back":"\\[2x\\]","hint":"Use the power rule","difficulty":"Exam","skill":"Apply"}]"#

        let cards = try CardGeneratorService.parseFlashcards(
            from: response,
            subject: subject,
            topicName: "Differentiation",
            subtopic: "Power rule"
        )

        #expect(cards.count == 1)
        #expect(cards[0].front == "Differentiate $x^2$")
        #expect(cards[0].back == "$$2x$$")
        #expect(cards[0].difficulty == .exam)
        #expect(cards[0].cognitiveSkill == .apply)
        #expect(cards[0].sourceURL != nil)
        #expect(cards[0].generationPromptVersion == CardGeneratorService.promptVersion)
    }

    @MainActor
    @Test("Inserting a generated card preserves one inverse subject relationship")
    func generatedCardRelationshipIsNotDuplicated() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Subject.self,
            StudyCard.self,
            StudySession.self,
            UserProfile.self,
            configurations: configuration
        )
        let context = container.mainContext
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "10B981")
        context.insert(subject)

        let card = StudyCard(
            topicName: "Genetics",
            subtopic: "Gene expression",
            front: "What is transcription?",
            back: "The synthesis of RNA from a DNA template.",
            subject: subject
        )
        context.insert(card)
        try context.save()

        #expect(subject.cards.count == 1)
        #expect(subject.cards.first?.id == card.id)
    }
}

@Suite("Curriculum Progress Tests")
struct CurriculumProgressTests {
    @MainActor
    @Test("Recorded mastery persists without flashcards")
    func recordedMasteryPersistsWithoutCards() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Subject.self,
            StudyCard.self,
            CurriculumNode.self,
            configurations: configuration
        )
        let context = container.mainContext
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "10B981")
        context.insert(subject)

        let node = try CurriculumProgressService.setMastery(
            .proficient,
            subject: subject,
            unitName: "Cell biology",
            topicName: "Cells and Cell Structure",
            subtopicName: "Prokaryotic cell structure",
            source: "Test",
            context: context
        )

        #expect(node.recordedProficiency == .proficient)
        #expect(node.masterySource == "Test")
        #expect(CurriculumProgressService.effectiveMastery(cards: [], node: node) == 0.66)
    }

    @Test("Scoped work only appears on matching curriculum subunits")
    func scopedWorkMatchesSubunit() {
        let matching = StudySession(
            subjectName: "Biology",
            topicsCovered: "Cells and Cell Structure",
            subtopicsCovered: "Prokaryotic cell structure",
            startDate: Date().addingTimeInterval(-1800),
            cardsReviewed: 0,
            correctCount: 0,
            xpEarned: 10
        )
        let other = StudySession(
            subjectName: "Biology",
            topicsCovered: "Genetics",
            startDate: Date().addingTimeInterval(-1200),
            cardsReviewed: 0,
            correctCount: 0,
            xpEarned: 5
        )

        let sessions = CurriculumProgressService.matchingWorkSessions(
            in: [matching, other],
            subjectName: "Biology",
            topicName: "Cells and Cell Structure",
            subtopicName: "Prokaryotic cell structure"
        )

        #expect(sessions.map(\.id) == [matching.id])
    }

    @Test("Study session backups retain subunit scope")
    func studySessionBackupRetainsSubunitScope() {
        let original = StudySession(
            subjectName: "Economics",
            topicsCovered: "Demand",
            subtopicsCovered: "The law of demand",
            startDate: Date().addingTimeInterval(-2400),
            cardsReviewed: 3,
            correctCount: 2,
            xpEarned: 12
        )

        let restored = StudySessionBackup(from: original).toModel()

        #expect(restored.subtopicsCovered == "The law of demand")
        #expect(restored.studyScope.subtopicNames == ["The law of demand"])
    }
}

@Suite("Local Codex Event Tests")
struct LocalCodexEventTests {
    @Test("Completed agent messages become learner-visible output")
    func parsesAgentMessage() {
        let line = #"{"type":"item.completed","item":{"type":"agent_message","text":"  Use $F = ma$.  "}}"#
        let update = AIProviderService.parseCodexEvent(line)

        #expect(update?.message == "Use $F = ma$.")
        #expect(update?.status == nil)
        #expect(update?.error == nil)
    }

    @Test("Web search events expose research progress")
    func parsesWebSearchStatus() {
        let line = #"{"type":"item.started","item":{"type":"web_search"}}"#
        let update = AIProviderService.parseCodexEvent(line)

        #expect(update?.status == "Researching supporting sources")
        #expect(update?.message == nil)
    }

    @Test("Failed turns preserve the CLI error detail")
    func parsesFailure() {
        let line = #"{"type":"turn.failed","error":{"message":"Saved login was rejected"}}"#
        let update = AIProviderService.parseCodexEvent(line)

        #expect(update?.error == "Saved login was rejected")
    }

    @Test("Codex runs preserve the user's CLI configuration")
    func preservesUserConfiguration() {
        let temporaryDirectory = URL(fileURLWithPath: "/tmp/ibvault-codex-test")
        let finalMessageURL = temporaryDirectory.appendingPathComponent("final.md")
        let arguments = AIProviderService.codexArguments(
            temporaryDirectory: temporaryDirectory,
            finalMessageURL: finalMessageURL,
            model: "gpt-5.6-sol",
            reasoningEffort: "high",
            verbosity: "medium",
            webSearchMode: .cached
        )

        #expect(!arguments.contains("--ignore-user-config"))
        #expect(!arguments.contains("--ignore-rules"))
        #expect(!arguments.contains(where: { $0.contains("model_provider") }))
        #expect(arguments.contains("--model"))
        #expect(arguments.contains("model_reasoning_effort=\"high\""))
    }

    @Test("Codex inherits the user's login-shell environment")
    func usesLoginShellEnvironment() {
        let executable = URL(fileURLWithPath: "/Users/student/.local/bin/codex")
        let arguments = AIProviderService.codexLoginShellArguments(
            executableURL: executable,
            arguments: ["login", "status"]
        )

        #expect(arguments == [
            "-lc",
            "exec \"$@\"",
            "ibvault-codex",
            "/Users/student/.local/bin/codex",
            "login",
            "status"
        ])
    }
}

@Suite("ARIA Message Formatting Tests")
struct ARIAMessageFormattingTests {
    @Test("Markdown lists remain distinct renderable rows")
    func preservesListRows() {
        let sections = FormattedMessageFormatter.sections(from: """
        Priorities:
        - Review concepts
        - Practise for 25 - 30 minutes
        1. Check the markscheme
        """)

        #expect(sections.contains(.listItem(marker: "•", text: "Review concepts")))
        #expect(sections.contains(.listItem(marker: "•", text: "Practise for 25 - 30 minutes")))
        #expect(sections.contains(.listItem(marker: "1.", text: "Check the markscheme")))
    }
}

@Suite("AI Configuration Tests")
struct AIConfigurationTests {
    @Test("Local Codex exposes only supported GPT-5.6 effort levels")
    func codexEffortLevels() {
        let efforts = AIConfiguration.supportedReasoningEfforts(for: .codexCLI)

        #expect(efforts == [.low, .medium, .high, .xhigh, .max, .ultra])
        #expect(AIConfiguration.normalizedReasoningEffort(.none, for: .codexCLI) == .low)
        #expect(AIConfiguration.normalizedReasoningEffort(.ultra, for: .junali) == .max)
        #expect(AIConfiguration.supportedReasoningEfforts(for: .gemini).isEmpty)
    }

    @Test("Known model slugs receive human-readable names")
    func modelDisplayNames() {
        #expect(AIConfiguration.modelDisplayName("gpt-5.6-sol", for: .codexCLI) == "GPT-5.6 Sol")
        #expect(AIConfiguration.modelDisplayName("custom-model", for: .junali) == "custom-model")
    }
}

@Suite("ARIA Chat Persistence Tests")
struct ARIAChatPersistenceTests {
    @Test("Failure roles preserve provider and recovery intent")
    func failureRolesRoundTrip() {
        let authFailure = ChatMessageRole.failure(for: .codexCLI, needsAuthentication: true)
        let cancellation = ChatMessageRole.cancellation(for: .junali)

        #expect(ChatMessageRole.isFailure(authFailure))
        #expect(ChatMessageRole.failureProvider(for: authFailure) == .codexCLI)
        #expect(ChatMessageRole.needsCodexAuthentication(authFailure))
        #expect(ChatMessageRole.isFailure(cancellation))
        #expect(ChatMessageRole.failureProvider(for: cancellation) == .junali)
    }

    @Test("Recovery records never enter provider conversation history")
    func recoveryRolesAreNotConversationTurns() {
        #expect(ChatMessageRole.isConversationRole(ChatMessageRole.user))
        #expect(ChatMessageRole.isConversationRole(ChatMessageRole.model))
        #expect(!ChatMessageRole.isConversationRole(ChatMessageRole.failure(for: .gemini)))
        #expect(!ChatMessageRole.isFailure(ChatMessageRole.dismissed(ChatMessageRole.failure(for: .gemini))))
    }

    @MainActor
    @Test("Stopped responses persist a provider-specific retry record")
    func cancellationPersistsRecoveryRecord() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ARIAChatSession.self,
            ChatMessage.self,
            configurations: configuration
        )
        let context = container.mainContext
        let session = ARIAChatSession(title: "Retry test")
        context.insert(session)
        try context.save()

        let service = ARIAService()
        let failureID = service.cancelCurrentRequest(
            context: context,
            session: session,
            provider: .junali
        )
        let messages = try context.fetch(FetchDescriptor<ChatMessage>())

        #expect(failureID != nil)
        #expect(messages.count == 1)
        #expect(messages.first?.role == ChatMessageRole.cancellation(for: .junali))
        #expect(messages.first?.content.contains("retried") == true)
    }
}
