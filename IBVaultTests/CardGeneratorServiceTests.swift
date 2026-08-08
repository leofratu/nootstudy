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

    @Test("Approved low assessment evidence prioritizes foundation cards")
    func lowAssessmentEvidenceProfile() {
        let subject = Subject(name: "Chemistry", level: "HL", accentColorHex: "EF4444")
        let profile = CardGeneratorService.adaptiveProfile(
            for: subject,
            topicName: "Atomic structure",
            subtopic: "Electron configurations",
            evidence: 0.42
        )

        #expect(profile.difficulty == .foundation)
        #expect(profile.reason.contains("school evidence"))
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

    @Test("Instruction-only answers are rejected")
    func rejectsInstructionOnlyAnswers() {
        #expect(!CardGeneratorService.isUsefulAnswer(
            front: "How should an externality diagram be used?",
            back: "Draw a diagram, label the axes, and explain it."
        ))
        #expect(CardGeneratorService.isUsefulAnswer(
            front: "Why does a negative externality cause overproduction?",
            back: "Marginal private cost is below marginal social cost because producers do not pay the external cost, so the market quantity exceeds the socially efficient quantity."
        ))
    }

    @Test("Generated cards collapse repeated question fronts")
    func repeatedFrontsAreDeduplicated() throws {
        let subject = Subject(name: "Economics", level: "HL", accentColorHex: "F59E0B")
        let response = #"[{"front":"What is CAC?","back":"CAC is total acquisition spend divided by new customers."},{"front":"What is CAC?","back":"Customer acquisition cost measures acquisition spend per acquired customer."}]"#
        let cards = try CardGeneratorService.parseFlashcards(
            from: response,
            subject: subject,
            topicName: "Startup metrics",
            subtopic: "CAC"
        )
        #expect(cards.count == 1)
    }

    @MainActor
    @Test("Local starter cards keep an active session usable without an AI response")
    func localStarterCardsProvideScopedFallback() {
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "10B981")
        let profile = CardGeneratorService.adaptiveProfile(
            for: subject,
            topicName: "Cells and Cell Structure",
            subtopic: "Prokaryotic cell structure"
        )

        let cards = CardGeneratorService.localStarterCards(
            subject: subject,
            topicName: "Cells and Cell Structure",
            subtopic: "Prokaryotic cell structure",
            count: 5,
            profile: profile
        )

        #expect(cards.count == 5)
        #expect(cards.allSatisfy { $0.topicName == "Cells and Cell Structure" })
        #expect(cards.allSatisfy { $0.subtopic == "Prokaryotic cell structure" })
        #expect(cards.allSatisfy { $0.generationSource == "Local syllabus starter" })
        #expect(Set(cards.map(\.front)).count == 5)

        let nextBatch = CardGeneratorService.localStarterCards(
            subject: subject,
            topicName: "Cells and Cell Structure",
            subtopic: "Prokaryotic cell structure",
            count: 5,
            startingIndex: cards.count,
            profile: profile
        )
        #expect(Set(cards.map(\.front)).isDisjoint(with: Set(nextBatch.map(\.front))))
    }

    @Test("Local practice paper remains scoped and includes marked questions")
    func localPracticePaperFallback() {
        let paper = PracticeExamFallback.markdown(
            subject: "Economics",
            level: "HL",
            unit: "Microeconomics",
            topics: ["Market failure"],
            subtopics: ["Negative externalities"]
        )

        #expect(paper.contains("Economics HL Practice Set"))
        #expect(paper.contains("Negative externalities"))
        #expect(paper.contains("[8 marks]"))
        #expect(paper.contains("Mark scheme and self-check"))
    }

    @Test("IB exam rubric selects subject criteria and totals paper marks")
    func ibExamRubricUsesSubjectCriteria() {
        let paper = "Question one [3 marks]\nQuestion two [7 marks]\nEssay [10 marks]"
        let rubric = IBExamRubric.markdown(for: "Economics", level: "HL")

        #expect(IBExamRubric.totalMarks(in: paper) == 20)
        #expect(rubric.contains("Application"))
        #expect(rubric.contains("Evaluation"))
        #expect(IBExamRubric.shortName(for: "Russian A Literature").contains("A-D"))
    }

    @Test("Local IB grader returns a bounded mark and improvement actions")
    func localIBExamGraderProducesFeedback() {
        let feedback = IBExamRubric.localFeedback(
            subject: "Economics",
            level: "HL",
            answer: "A negative externality creates an external cost because third parties are affected. For example, pollution creates health costs. Therefore marginal social cost exceeds marginal private cost. However, a tax depends on accurate information and may affect stakeholders differently. Overall, regulation may work better where measurement is difficult.",
            totalMarks: 20,
            scopeTerms: ["Market failure", "Negative externalities"]
        )

        #expect(feedback.contains("Estimated mark:"))
        #expect(feedback.contains("Approximate IB grade:"))
        #expect(feedback.contains("Criterion grading"))
        #expect(feedback.contains("Next actions"))
        #expect(!feedback.contains("| Criterion |"))
    }

    @Test("Unsupported Markdown tables become readable rubric lists")
    func rubricTableFormattingIsDisplaySafe() {
        let source = """
        | Criterion | Focus | Marks |
        |---|---|---:|
        | A Language | Range and accuracy | 6 |
        | B Message | Development and relevance | 6 |
        """
        let converted = IBExamRubric.displaySafeMarkdown(source)

        #expect(converted.contains("A Language"))
        #expect(converted.contains("**Focus:** Range and accuracy"))
        #expect(converted.contains("**Marks:** 6"))
        #expect(!converted.contains("|---|"))
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

    @MainActor
    @Test("Setting mastery again updates the existing node instead of duplicating it")
    func setMasteryUpdatesInPlace() throws {
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

        _ = try CurriculumProgressService.setMastery(
            .developing,
            subject: subject,
            unitName: "Cell biology",
            topicName: "Cells and Cell Structure",
            subtopicName: "Prokaryotic cell structure",
            source: "Review",
            context: context
        )
        _ = try CurriculumProgressService.setMastery(
            .mastered,
            subject: subject,
            unitName: "Cell biology",
            topicName: "Cells and Cell Structure",
            subtopicName: "Prokaryotic cell structure",
            source: "Follow-up",
            context: context
        )

        let nodes = try context.fetch(FetchDescriptor<CurriculumNode>())
        #expect(nodes.count == 1)
        #expect(nodes.first?.recordedProficiency == .mastered)
        #expect(nodes.first?.masterySource == "Follow-up")
        #expect(nodes.first?.masteryNote == nil)
    }

    @MainActor
    @Test("Clearing mastery clears the recording and falls back to card-based mastery")
    func clearMasteryClearsRecordingAndFallsBack() throws {
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

        _ = try CurriculumProgressService.setMastery(
            .mastered,
            subject: subject,
            unitName: "Cell biology",
            topicName: "Cells and Cell Structure",
            subtopicName: "Prokaryotic cell structure",
            source: "Review",
            context: context
        )

        try CurriculumProgressService.clearMastery(
            subject: subject,
            topicName: "Cells and Cell Structure",
            subtopicName: "Prokaryotic cell structure",
            context: context
        )

        let nodes = try context.fetch(FetchDescriptor<CurriculumNode>())
        #expect(nodes.count == 1)
        #expect(nodes.first?.recordedProficiency == nil)
        #expect(nodes.first?.masterySource == nil)

        // With the recording cleared, mastery falls back to the cards.
        let card = StudyCard(topicName: "Cells and Cell Structure", subtopic: "Prokaryotic cell structure", front: "Q", back: "A")
        card.proficiency = .mastered
        #expect(CurriculumProgressService.effectiveMastery(cards: [card], node: nodes.first) == 1.0)
    }

    @Test("effectiveMastery prefers recorded mastery over card-based estimation")
    func effectiveMasteryPrefersRecorded() {
        let node = CurriculumNode(
            subjectName: "Biology", level: "HL", unitName: "Cell biology",
            topicName: "Cells and Cell Structure", subtopicName: "Prokaryotic cell structure",
            catalogVersion: "2026.1", sourceTitle: "IB Biology", sourceURLString: "https://www.ibo.org/"
        )
        node.recordedProficiency = .developing

        let card = StudyCard(topicName: "Cells and Cell Structure", subtopic: "Prokaryotic cell structure", front: "Q", back: "A")
        card.proficiency = .mastered

        // Cards alone would say 1.0; the recorded .developing wins.
        #expect(CurriculumProgressService.effectiveMastery(cards: [card], node: node) == 0.33)
        // With no node, card-based mastery is used.
        #expect(CurriculumProgressService.effectiveMastery(cards: [card], node: nil) == 1.0)
        #expect(CurriculumProgressService.effectiveMastery(cards: [], node: nil) == 0.0)
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
        let planID = UUID()
        let cardID = UUID()
        let entry = StudySessionSubunitEvidence(
            topicName: "Demand",
            subtopicName: "The law of demand",
            minutes: 40,
            confidenceRating: 4,
            cardsReviewed: 3,
            correctCount: 2
        )
        let original = StudySession(
            subjectName: "Economics",
            topicsCovered: "Demand",
            subtopicsCovered: "The law of demand",
            startDate: Date().addingTimeInterval(-2400),
            cardsReviewed: 3,
            correctCount: 2,
            xpEarned: 12,
            sourcePlanID: planID,
            notes: "Compare the welfare-loss diagram with the tax response.",
            subunitEvidence: [entry],
            reviewedCardIDs: [cardID]
        )

        let restored = StudySessionBackup(from: original).toModel()

        #expect(restored.subtopicsCovered == "The law of demand")
        #expect(restored.studyScope.subtopicNames == ["The law of demand"])
        #expect(restored.sourcePlanID == planID)
        #expect(restored.notes == "Compare the welfare-loss diagram with the tax response.")
        #expect(restored.subunitEvidence == [entry])
        #expect(restored.reviewedCardIDs == [cardID])
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

    @Test("Inline math stays inside its sentence")
    func rendersInlineMath() {
        let sections = FormattedMessageFormatter.sections(from: "Use $F = ma$ to solve the force.")

        #expect(sections == [.markdown("Use F = ma to solve the force.")])
    }

    @Test("Explicit display math uses the dedicated math surface")
    func rendersDisplayMath() {
        let sections = FormattedMessageFormatter.sections(from: "Before\n\n$$\\frac{a}{b} = c$$\n\nAfter")

        #expect(sections == [.markdown("Before"), .mathBlock("\\frac{a}{b} = c"), .markdown("After")])
    }

    @Test("Multiple inline expressions preserve natural prose flow")
    func preservesMultipleInlineExpressions() {
        let sections = FormattedMessageFormatter.sections(from: "From $v = u + at$, derive $a = \\frac{v-u}{t}$ directly.")

        #expect(sections == [.markdown("From v = u + at, derive a = (v-u)/t directly.")])
    }

    @Test("Markdown tables become readable labelled rows")
    func convertsMarkdownTables() {
        let source = """
        | Criterion | Marks | Focus |
        |---|---:|---|
        | Language | 6 | Range and accuracy |
        | Message | 6 | Relevance and examples |
        """

        let rendered = MessageRenderingPolicy.displaySafeMarkdown(source)
        #expect(rendered.contains("**Language**"))
        #expect(rendered.contains("**Marks:** 6"))
        #expect(rendered.contains("**Focus:** Range and accuracy"))
        #expect(!rendered.contains("|---|"))
    }

    @Test("Diagram blocks decode into native canvas data")
    func decodesDiagramBlock() {
        let fence = String(repeating: "\u{60}", count: 3)
        let source = """
        \(fence)diagram
        {"type":"coordinate","title":"Parabola","xLabel":"x","yLabel":"y","series":[{"label":"y = x squared","points":[[-1,1],[0,0],[1,1]]}]}
        \(fence)
        """

        let sections = FormattedMessageFormatter.sections(from: source)
        #expect(sections.contains(.diagram(ARIADiagramSpec(
            type: "coordinate",
            title: "Parabola",
            xLabel: "x",
            yLabel: "y",
            series: [.init(label: "y = x squared", color: nil, points: [[-1, 1], [0, 0], [1, 1]])],
            nodes: nil,
            edges: nil,
            simulation: nil,
            particleCount: nil
        ))))
    }

    @Test("Canonical canvas fence decodes validated native content")
    func decodesCanonicalCanvasFence() {
        let fence = String(repeating: "\u{60}", count: 3)
        let source = """
        \(fence)aria-canvas
        {"type":"canvas","title":"Wave","canvas":{"elements":[{"id":"wave","kind":"polyline","color":"#2563EB","points":[[0.1,0.5],[0.5,0.2],[0.9,0.5]]}]}}
        \(fence)
        """

        let sections = FormattedMessageFormatter.sections(from: source)
        #expect(sections.count == 1)
        guard case .diagram(let diagram) = sections[0] else {
            Issue.record("Expected a native diagram")
            return
        }
        #expect(diagram.type == "canvas")
        #expect(diagram.canvas?.elements.first?.points == [[0.1, 0.5], [0.5, 0.2], [0.9, 0.5]])
    }

    @Test("Canvas contract rejects controls referenced by no definition")
    func rejectsUnknownCanvasControl() {
        let source = """
        {"type":"canvas","canvas":{"elements":[{"id":"bob","kind":"circle","x":0.5,"y":0.5,"speedControl":"missing"}]}}
        """

        #expect(ARIAContentContract.decodeDiagram(from: source, language: "aria-canvas") == nil)
    }

    @Test("Canvas prompt uses a real canonical fence")
    func canvasPromptUsesCanonicalFence() {
        #expect(ARIAContentContract.systemInstruction.contains("```aria-canvas"))
        #expect(!ARIAContentContract.systemInstruction.contains("(diagramFence)"))
        #expect(ARIAContentContract.systemInstruction.contains(ARIAContentContract.toolName))
    }

    @Test("Diagram JSON blocks render even when the model uses the json fence")
    func decodesDiagramJSONFence() {
        let fence = String(repeating: "\u{60}", count: 3)
        let source = """
        \(fence)json
        {"type":"flow","title":"Transport","nodes":[{"id":"a","label":"A"},{"id":"b","label":"B"}],"edges":[{"from":"a","to":"b","label":"causes"}]}
        \(fence)
        """

        let sections = FormattedMessageFormatter.sections(from: source)
        #expect(sections.contains(.diagram(ARIADiagramSpec(
            type: "flow",
            title: "Transport",
            xLabel: nil,
            yLabel: nil,
            series: nil,
            nodes: [.init(id: "a", label: "A", x: nil, y: nil, color: nil), .init(id: "b", label: "B", x: nil, y: nil, color: nil)],
            edges: [.init(from: "a", to: "b", label: "causes")],
            simulation: nil,
            particleCount: nil
        ))))
    }

    @Test("Simulation blocks decode into a live canvas specification")
    func decodesSimulationDiagram() {
        let fence = String(repeating: "\u{60}", count: 3)
        let source = """
        \(fence)diagram
        {"type":"simulation","title":"Electron shells","simulation":"atoms","particleCount":12}
        \(fence)
        """

        let sections = FormattedMessageFormatter.sections(from: source)
        #expect(sections.contains(.diagram(ARIADiagramSpec(
            type: "simulation",
            title: "Electron shells",
            xLabel: nil,
            yLabel: nil,
            series: nil,
            nodes: nil,
            edges: nil,
            simulation: "atoms",
            particleCount: 12
        ))))
    }

    @Test("Legacy canvas refusals still receive a usable native simulation")
    func recoversSimulationFromCanvasRefusal() {
        let sections = FormattedMessageFormatter.sections(from: """
        I can't embed a fully executable canvas with a velocity slider in this chat.
        A compatible viewer can render canvas-ready particle data.
        """)

        #expect(sections.contains(.diagram(ARIADiagramSpec(
            type: "simulation",
            title: "Particle simulation",
            xLabel: nil,
            yLabel: nil,
            series: nil,
            nodes: nil,
            edges: nil,
            simulation: "particles",
            particleCount: 20
        ))))
    }

    @Test("Canvas blocks decode arbitrary scene elements and interactive controls")
    func decodesGenerativeCanvas() {
        let fence = String(repeating: "\u{60}", count: 3)
        let source = """
        \(fence)diagram
        {"type":"canvas","title":"Pendulum","canvas":{"controls":[{"id":"amplitude","label":"Angle","min":0.02,"max":0.3,"value":0.12,"unit":"rad"}],"elements":[{"id":"bob","kind":"circle","x":0.5,"y":0.35,"radius":0.04,"color":"#2563EB","animation":"sine","amplitudeControl":"amplitude"}]}}
        \(fence)
        """

        let sections = FormattedMessageFormatter.sections(from: source)
        #expect(sections.contains(.diagram(ARIADiagramSpec(
            type: "canvas",
            title: "Pendulum",
            xLabel: nil,
            yLabel: nil,
            series: nil,
            nodes: nil,
            edges: nil,
            simulation: nil,
            particleCount: nil,
            canvas: .init(
                elements: [.init(
                    id: "bob",
                    kind: "circle",
                    x: 0.5,
                    y: 0.35,
                    x2: nil,
                    y2: nil,
                    width: nil,
                    height: nil,
                    radius: 0.04,
                    label: nil,
                    color: "#2563EB",
                    animation: "sine",
                    amplitude: nil,
                    speed: nil,
                    phase: nil,
                    speedControl: nil,
                    amplitudeControl: "amplitude",
                    radiusControl: nil,
                    visibilityControl: nil
                )],
                controls: [.init(id: "amplitude", label: "Angle", min: 0.02, max: 0.3, value: 0.12, unit: "rad", kind: nil)]
            )
        ))))
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
        let authFailure = ChatMessageRole.failure(provider: .codexCLI, needsAuthentication: true)
        let cancellation = ChatMessageRole.cancelled(provider: .junali)

        #expect(ChatMessageRole(storedValue: authFailure.storedValue)?.isFailure == true)
        #expect(ChatMessageRole(storedValue: authFailure.storedValue)?.failureProvider == .codexCLI)
        #expect(ChatMessageRole(storedValue: authFailure.storedValue)?.needsCodexAuthentication == true)
        #expect(ChatMessageRole(storedValue: cancellation.storedValue)?.isFailure == true)
        #expect(ChatMessageRole(storedValue: cancellation.storedValue)?.failureProvider == .junali)
    }

    @Test("Recovery records never enter provider conversation history")
    func recoveryRolesAreNotConversationTurns() {
        let userRole = ChatMessageRole.user
        let modelRole = ChatMessageRole.model
        let failureRole = ChatMessageRole.failure(provider: .gemini)
        let dismissedFailure = ChatMessageRole.dismissed(underlying: failureRole)

        #expect(ChatMessageRole(storedValue: userRole.storedValue)?.isConversation == true)
        #expect(ChatMessageRole(storedValue: modelRole.storedValue)?.isConversation == true)
        #expect(ChatMessageRole(storedValue: failureRole.storedValue)?.isConversation == false)
        #expect(ChatMessageRole(storedValue: dismissedFailure.storedValue)?.isFailure == false)
    }

    @Test("Every role shape round-trips byte-for-byte through the stored string")
    func allRolesRoundTripThroughStoredValue() {
        let roles: [ChatMessageRole] = [
            .user,
            .model,
            .failure(provider: .gemini),
            .failure(provider: .codexCLI, needsAuthentication: true),
            .cancelled(provider: .junali),
            .dismissed(underlying: .user),
            .dismissed(underlying: .failure(provider: .gemini, needsAuthentication: true)),
            .dismissed(underlying: .dismissed(underlying: .model))
        ]

        for role in roles {
            #expect(ChatMessageRole(storedValue: role.storedValue) == role,
                    "stored value '\(role.storedValue)' must parse back to the original role")
        }
    }

    @Test("isConversation is true only for user and model turns")
    func isConversationSpansEveryRoleShape() {
        let user = ChatMessageRole.user
        let model = ChatMessageRole.model
        let failure = ChatMessageRole.failure(provider: .gemini)
        let cancelled = ChatMessageRole.cancelled(provider: .junali)
        let dismissed = ChatMessageRole.dismissed(underlying: .model)

        #expect(user.isConversation)
        #expect(model.isConversation)
        #expect(!failure.isConversation)
        #expect(!cancelled.isConversation)
        #expect(!dismissed.isConversation)
    }

    @Test("needsCodexAuthentication is true only for a Codex authentication failure")
    func needsCodexAuthenticationIsNarrow() {
        #expect(ChatMessageRole.failure(provider: .codexCLI, needsAuthentication: true).needsCodexAuthentication)
        #expect(!ChatMessageRole.failure(provider: .codexCLI).needsCodexAuthentication)
        #expect(!ChatMessageRole.failure(provider: .gemini, needsAuthentication: true).needsCodexAuthentication)
        #expect(!ChatMessageRole.cancelled(provider: .codexCLI).needsCodexAuthentication)
        #expect(!ChatMessageRole.user.needsCodexAuthentication)
        #expect(!ChatMessageRole.dismissed(underlying: .failure(provider: .codexCLI, needsAuthentication: true)).needsCodexAuthentication)
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
        #expect(messages.first?.role == ChatMessageRole.cancelled(provider: .junali).storedValue)
        #expect(messages.first?.content.contains("retried") == true)
    }
}
