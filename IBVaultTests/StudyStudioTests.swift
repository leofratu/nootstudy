import Testing
import Foundation
import SwiftData
@testable import IBVault

@Suite("Study studio regressions")
struct StudyStudioTests {
    @MainActor
    @Test func batchGenerationPreservesScopeAndFormatWithoutPersisting() async throws {
        let schema = Schema([Subject.self, StudyCard.self, Grade.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "34533B")
        container.mainContext.insert(subject)
        let jobs = try CardBatchService.plan(scopes: [.init(topic: "Cells"), .init(topic: "Genetics")],
                                             styles: [.multipleChoice], count: 5)
        var observed: [CardBatchJob] = []
        let result = try await CardBatchService.generate(subject: subject, jobs: jobs, options: .default,
            context: container.mainContext, generateCards: { detached, job, settings, _ in
                #expect(detached !== subject)
                #expect(settings.count == job.count)
                #expect(settings.style == .multipleChoice)
                observed.append(job)
                return (0..<settings.count).map { index in
                    StudyCard(topicName: job.scope.topic, subtopic: job.scope.subtopic,
                              front: "\(job.scope.topic) question \(index)", back: "Correct",
                              subject: detached, cardStyle: settings.style, choices: ["Correct", "Other", "Third"])
                }
            }, onProgress: { _, _, _ in })
        #expect(observed == jobs)
        #expect(result.drafts.count == 5)
        #expect(result.issues.isEmpty)
        #expect(result.drafts.allSatisfy { $0.style == .multipleChoice && $0.isValid })
        #expect(try container.mainContext.fetchCount(FetchDescriptor<StudyCard>()) == 0)
        #expect(subject.cards.isEmpty)
    }

    @MainActor
    @Test func partialFailureKeepsSuccessfulDraftsAndReportsMissingScope() async throws {
        let schema = Schema([Subject.self, StudyCard.self, Grade.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "34533B")
        let jobs = try CardBatchService.plan(scopes: [.init(topic: "Cells"), .init(topic: "Genetics")], styles: [.basic], count: 2)
        let result = try await CardBatchService.generate(subject: subject, jobs: jobs, options: .default,
            context: container.mainContext, generateCards: { detached, job, _, _ in
                if job.scope.topic == "Genetics" { throw AIProviderError.invalidResponse }
                return [StudyCard(topicName: "Cells", front: "What is a cell?", back: "A basic unit of life.", subject: detached)]
            }, onProgress: { _, _, _ in })
        #expect(result.drafts.count == 1)
        #expect(result.issues.count == 1)
        #expect(result.issues[0].contains("Genetics"))
    }

    @MainActor
    @Test func cancellationStopsBeforeNextScope() async throws {
        let schema = Schema([Subject.self, StudyCard.self, Grade.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "34533B")
        let jobs = try CardBatchService.plan(scopes: [.init(topic: "Cells"), .init(topic: "Genetics")], styles: [.basic], count: 2)
        var calls = 0
        do {
            _ = try await CardBatchService.generate(subject: subject, jobs: jobs, options: .default,
                context: container.mainContext, generateCards: { _, _, _, _ in
                    calls += 1
                    throw CancellationError()
                }, onProgress: { _, _, _ in })
            Issue.record("Expected cancellation to propagate")
        } catch is CancellationError {
            #expect(calls == 1)
        }
    }

    @Test func distributesTotalAcrossTopicsAndFormats() throws {
        let scopes = [CardTopicSelection(topic: "Cells"), CardTopicSelection(topic: "Genetics")]
        let jobs = try CardBatchService.plan(scopes: scopes, styles: [.basic, .multipleChoice], count: 11)
        #expect(jobs.count == 4)
        #expect(jobs.reduce(0) { $0 + $1.count } == 11)
        #expect(jobs.allSatisfy { $0.count >= 2 && $0.count <= 3 })
        #expect(Set(jobs.map(\.scope)) == Set(scopes))
    }

    @Test func wholeTopicSubsumesSubtopicsAndDuplicates() throws {
        let topic = CardTopicSelection(topic: "Cells")
        let jobs = try CardBatchService.plan(scopes: [topic, topic, .init(topic: "Cells", subtopic: "Organelles")],
                                            styles: [.basic, .basic], count: 8)
        #expect(jobs == [CardBatchJob(scope: topic, style: .basic, count: 8)])
    }

    @Test func refusesZeroAndUndersizedBatches() {
        #expect(throws: CardBatchError.self) {
            try CardBatchService.plan(scopes: [], styles: [.basic], count: 10)
        }
        #expect(throws: CardBatchError.self) {
            try CardBatchService.plan(scopes: [.init(topic: "Cells")], styles: [], count: 10)
        }
        #expect(throws: CardBatchError.self) {
            try CardBatchService.plan(scopes: [.init(topic: "Cells"), .init(topic: "Genetics")],
                                      styles: [.basic, .cloze], count: 3)
        }
        #expect(throws: CardBatchError.self) {
            try CardBatchService.plan(scopes: [.init(topic: "Cells")], styles: [.basic], count: 51)
        }
    }

    @Test func chosenFormatRejectsInvalidMultipleChoice() throws {
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "34533B")
        let response = #"[{"front":"Which organelle makes ATP?","back":"Mitochondrion","cardStyle":"basic","choices":["Nucleus","Ribosome","Chloroplast"]}]"#
        #expect(throws: (any Error).self) {
            try CardGeneratorService.parseFlashcards(from: response, subject: subject, topicName: "Cells",
                                                      subtopic: "", options: .init(style: .multipleChoice))
        }
    }

    @MainActor
    @Test func dtoPathCannotSilentlyRepairSelectedFormat() throws {
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "34533B")
        let response = #"[{"front":"Which organelle makes ATP?","back":"Mitochondrion","choices":["Mitochondrion","Mitochondrion","Nucleus"]}]"#
        let dtos = try CardGeneratorService.extractCardDTOs(from: response)
        let cards = CardGeneratorService.cardsFromDTOs(dtos, subject: subject, topicName: "Cells", subtopic: "",
            profile: .init(difficulty: .exam, skillMix: [.recall], reason: "test"), options: .init(style: .multipleChoice))
        #expect(cards.isEmpty)
    }

    @Test func selectedStyleAndSkillsWinOverPayload() throws {
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "34533B")
        let response = #"[{"front":"Which organelle makes ATP?","back":"Mitochondrion","cardStyle":"basic","skill":"Recall","choices":["Mitochondrion","Ribosome","Nucleus"]}]"#
        let cards = try CardGeneratorService.parseFlashcards(from: response, subject: subject, topicName: "Cells", subtopic: "",
            options: .init(style: .multipleChoice, cognitiveSkills: [.apply]))
        #expect(cards.count == 1)
        #expect(cards[0].cardStyle == .multipleChoice)
        #expect(cards[0].cognitiveSkill == .apply)
    }

    @Test func clozeConcealsEveryDeletionAndHintUntilRevealed() {
        let front = "The {{c1::nucleus::organelle}} contains {{c2::DNA}}."
        let hidden = CardRecallPresentation.prompt(front: front, style: .cloze, revealed: false)
        #expect(!hidden.contains("nucleus"))
        #expect(!hidden.contains("DNA"))
        #expect(!hidden.contains("organelle"))
        #expect(hidden == "The ______ contains ______.")
        let revealed = CardRecallPresentation.prompt(front: front, style: .cloze, revealed: true)
        #expect(revealed == "The nucleus contains DNA.")
    }

    @Test func choiceMatchingTrimsAndIgnoresCase() {
        #expect(CardRecallPresentation.isCorrect(" Mitochondrion ", answer: "mitochondrion"))
        #expect(!CardRecallPresentation.isCorrect("Nucleus", answer: "mitochondrion"))
    }

    @MainActor
    @Test func previewIsDetachedAndSaveDeduplicates() throws {
        let schema = Schema([Subject.self, StudyCard.self, Grade.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "34533B")
        context.insert(subject)
        try context.save()
        let detached = Subject(name: subject.name, level: subject.level, accentColorHex: subject.accentColorHex)
        let preview = StudyCard(topicName: "Cells", front: "Which organelle makes ATP?", back: "Mitochondrion",
                                subject: detached, cardStyle: .multipleChoice, choices: ["Mitochondrion", "Nucleus", "Ribosome"])
        var draft = CardDraft(card: preview)
        #expect(try context.fetchCount(FetchDescriptor<StudyCard>()) == 0)
        #expect(subject.cards.isEmpty)
        draft.front = "Which organelle produces ATP?"
        #expect(try CardBatchService.save([draft, draft], subject: subject, context: context) == 1)
        #expect(try CardBatchService.save([draft], subject: subject, context: context) == 0)
        let saved = try context.fetch(FetchDescriptor<StudyCard>())
        #expect(saved.count == 1)
        #expect(saved[0].subject?.id == subject.id)
        #expect(saved[0].front == draft.front)
        #expect(saved[0].choices == draft.choices)
    }

    @MainActor
    @Test func invalidEditedDraftCannotBeSaved() throws {
        let schema = Schema([Subject.self, StudyCard.self, Grade.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "34533B")
        container.mainContext.insert(subject)
        let draft = CardDraft(card: StudyCard(topicName: "Cells", front: "Which organelle?", back: "Missing",
                                              cardStyle: .multipleChoice, choices: ["A", "B", "C"]))
        #expect(throws: CardBatchError.self) {
            try CardBatchService.save([draft], subject: subject, context: container.mainContext)
        }
        #expect(try container.mainContext.fetchCount(FetchDescriptor<StudyCard>()) == 0)
    }

    @MainActor
    @Test func exhaustedLocalStarterDoesNotIndexPastFacts() {
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "34533B")
        let cards = CardGeneratorService.localStarterCards(subject: subject, topicName: "Cells", subtopic: "", count: 10,
            startingIndex: Int.max, profile: .init(difficulty: .standard, skillMix: [.recall], reason: "test"))
        #expect(cards.isEmpty)
    }
}

@Suite("Exam marker regressions")
struct ExamMarkerTests {
    private var valid: String {
        #"{"criteria":[{"name":"Definition","awarded":1,"available":2,"evidence":"Student identifies diffusion.","feedback":"Include the concentration gradient."}],"summary":"One point earned.","improvedAnswer":"Diffusion is net movement down a concentration gradient.","nextSteps":["Practise describing the gradient."]}"#
    }

    @Test func parsesAndComputesScoreFromCriteria() throws {
        let result = try ExamMarkingService.parse("Result:\n\(valid)\n", maximumMarks: 2)
        #expect(result.awarded == 1)
        #expect(result.available == 2)
        #expect(result.transcript(hasScheme: false).contains("Practice estimate"))
    }

    @Test func rejectsInconsistentOrOutOfRangeMarks() {
        for response in [
            valid.replacingOccurrences(of: #""awarded":1"#, with: #""awarded":3"#),
            valid.replacingOccurrences(of: #""awarded":1"#, with: #""awarded":-1"#),
            valid.replacingOccurrences(of: #""available":2"#, with: #""available":1"#),
            valid.replacingOccurrences(of: #""available":2"#, with: #""available":0"#),
            "Not JSON"
        ] {
            #expect(throws: ExamMarkingError.self) { try ExamMarkingService.parse(response, maximumMarks: 2) }
        }
    }

    @Test func requiresEvidenceAndActionableFeedback() {
        let missingEvidence = valid.replacingOccurrences(of: "Student identifies diffusion.", with: "")
        #expect(throws: ExamMarkingError.self) { try ExamMarkingService.parse(missingEvidence, maximumMarks: 2) }
        let missingNextSteps = valid.replacingOccurrences(of: "Practise describing the gradient.", with: " ")
        #expect(throws: ExamMarkingError.self) { try ExamMarkingService.parse(missingNextSteps, maximumMarks: 2) }
    }

    @Test func validatesInputsAndLabelsMissingScheme() {
        var request = ExamMarkingRequest(subject: "Biology", level: "HL", question: "Define diffusion.",
                                         answer: "Net movement.", markScheme: " ", maximumMarks: 2)
        #expect(request.isValid)
        #expect(!request.hasScheme)
        #expect(request.transcript.contains("practice estimate"))
        request.answer = " "
        #expect(!request.isValid)
        request.answer = String(repeating: "x", count: 40_001)
        #expect(!request.isValid)
    }
}
