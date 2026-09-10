import Testing
import Foundation
import SwiftData
@testable import IBVault

@Suite("Performance Benchmarks", .serialized)
struct PerformanceBenchmarks {

    @MainActor
    private static func makePopulatedContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Subject.self, StudyCard.self, ReviewSession.self, UserProfile.self, StudySession.self, Grade.self, AcademicAssessment.self, AcademicAssessmentMapping.self, AcademicReportSnapshot.self, CurriculumNode.self, configurations: config)
        let context = container.mainContext
        // 20 subjects
        let subjects: [Subject] = (0..<20).map { i in
            let s = Subject(name: "Subject\(i)", level: i % 2 == 0 ? "HL" : "SL", accentColorHex: "#123456")
            context.insert(s)
            return s
        }
        // 2000 cards distributed
        let now = Date()
        for i in 0..<2000 {
            let subject = subjects[i % subjects.count]
            let card = StudyCard(topicName: "Topic\(i % 10)", subtopic: "Sub\(i % 5)", front: "Q\(i) What is concept \(i)?", back: "A\(i) Detailed answer for concept \(i) with explanation.", subject: subject)
            card.nextReviewDate = i % 3 == 0 ? now.addingTimeInterval(-Double(i) * 10) : now.addingTimeInterval(Double(i) * 100)
            if i % 4 == 0 {
                card.totalReviewCount = 5
                card.successfulReviewCount = 4
                card.proficiency = .proficient
            }
            context.insert(card)
        }
        // 500 review sessions
        for i in 0..<500 {
            let cardID = subjects[i % subjects.count].cards.first?.id ?? UUID()
            let rs = ReviewSession(cardID: cardID, subjectName: "Subject\(i % 20)", topicName: "Topic\(i % 10)", qualityRating: [0,2,3,5].randomElement() ?? 3, sessionDuration: 5)
            rs.timestamp = now.addingTimeInterval(-Double(i) * 1000)
            context.insert(rs)
        }
        // 200 assessments + mappings
        for i in 0..<200 {
            let assessment = AcademicAssessment(sourceKey: "k\(i)", sourceFileName: "file\(i).xlsx", subjectName: "Subject\(i % 20)", courseLevel: i % 2 == 0 ? "HL" : "SL", sourceClassLabel: "Class", assessmentDate: nil, title: "Assessment \(i)", assessmentType: "Test", category: "Summative", status: "Graded", percentage: Double(50 + i % 50))
            context.insert(assessment)
            let mapping = AcademicAssessmentMapping(assessmentID: assessment.id, subjectName: "Subject\(i % 20)", courseLevel: i % 2 == 0 ? "HL" : "SL", curriculumNodeKey: "key\(i)", unitName: "Unit", topicName: "Topic\(i % 10)", subtopicName: "Sub\(i % 5)", status: .approved, confidence: 0.9)
            context.insert(mapping)
        }
        // Study sessions
        for i in 0..<50 {
            let ss = StudySession(subjectName: "Subject\(i % 20)", topicsCovered: "Topic\(i % 10)", startDate: now.addingTimeInterval(-Double(i)*3600), endDate: now, cardsReviewed: 10, correctCount: 8, xpEarned: 20)
            context.insert(ss)
        }
        let profile = UserProfile()
        context.insert(profile)
        try context.save()
        return container
    }

    @MainActor
    @Test("Benchmark: review queue refresh 2000 cards")
    func benchmarkReviewQueue() throws {
        let container = try Self.makePopulatedContainer()
        let context = container.mainContext
        let manager = ReviewQueueManager()
        manager.resetFingerprintForTesting()
        let clock = ContinuousClock()
        let start = clock.now
        manager.refreshDueCardsSynchronously(context: context)
        let ms = elapsedMS(from: start, clock: clock)
        print("bench reviewQueue 2000: \(ms) ms due=\(manager.dueCards.count)")
        #expect(ms < 200, "review queue should be <200ms, was \(ms)")
    }

    @MainActor
    @Test("Benchmark: evidence scoring 20 subjects")
    func benchmarkEvidenceScoring() throws {
        let container = try Self.makePopulatedContainer()
        let context = container.mainContext
        let subjects = try context.fetch(FetchDescriptor<Subject>())
        let assessments = try context.fetch(FetchDescriptor<AcademicAssessment>())
        let mappings = try context.fetch(FetchDescriptor<AcademicAssessmentMapping>())
        let clock = ContinuousClock()
        let start = clock.now
        for subject in subjects {
            _ = ProgressEvidenceService.score(subjectName: subject.name, courseLevel: subject.level, cards: subject.cards, assessments: assessments, mappings: mappings)
        }
        let ms = elapsedMS(from: start, clock: clock)
        print("bench evidence 20 subjects: \(ms) ms")
        #expect(ms < 600, "evidence scoring 20 subjects <600ms, was \(ms)")
    }

    @Test("Benchmark: formatter parse 50KB markdown+math")
    func benchmarkFormatterParse() {
        var md = ""
        for i in 0..<500 {
            md += "## Heading \(i)\n\nThis is paragraph \(i) with $F = ma$ inline math and **bold** text.\n\n- Item \(i) with $a^2 + b^2 = c^2$\n\n"
        }
        md += "\n$$\\frac{a}{b} = c$$\n\n"
        // Ensure ~50KB
        while md.utf8.count < 50 * 1024 {
            md += "Extra line with $x = y$ and text.\n"
        }
        let clock = ContinuousClock()
        let start = clock.now
        let sections = FormattedMessageFormatter.sections(from: md)
        let ms = elapsedMS(from: start, clock: clock)
        print("bench formatter 50KB: \(ms) ms sections=\(sections.count)")
        #expect(ms < 400, "formatter 50KB <400ms was \(ms)")
        #expect(!sections.isEmpty)
    }

    @MainActor
    @Test("Benchmark: card payload parse 100 cards")
    func benchmarkCardPayloadParse() async throws {
        var payloads: [[String: String]] = []
        for i in 0..<100 {
            payloads.append(["front": "Q\(i) front with some content \(i)", "back": "A\(i) back detailed answer that is self-contained and teaches concept.", "hint": "hint", "difficulty": "Standard", "skill": "Recall", "cardStyle": "basic"])
        }
        let data = try JSONEncoder().encode(payloads)
        let json = String(data: data, encoding: .utf8)!
        let clock = ContinuousClock()
        let start = clock.now
        let dtos = try await Task.detached(priority: .userInitiated) {
            try CardGeneratorService.extractCardDTOs(from: json)
        }.value
        let ms = elapsedMS(from: start, clock: clock)
        print("bench card payload 100: \(ms) ms dtos=\(dtos.count)")
        #expect(ms < 250, "card payload 100 <250ms was \(ms)")
        #expect(dtos.count == 100)
    }

    @MainActor
    @Test("Benchmark: backup encode in-memory")
    func benchmarkBackupEncode() throws {
        let container = try Self.makePopulatedContainer()
        let clock = ContinuousClock()
        let start = clock.now
        let dir = try BackupService.exportBackup(container: container)
        let ms = elapsedMS(from: start, clock: clock)
        print("bench backup encode: \(ms) ms dir=\(dir.lastPathComponent)")
        #expect(ms < 2000, "backup encode <2000ms was \(ms)")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: dir.deletingLastPathComponent().appendingPathComponent("backup_meta.json"))
    }

    private func elapsedMS(from start: ContinuousClock.Instant, clock: ContinuousClock) -> Double {
        let elapsed = clock.now - start
        return Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
    }
}
