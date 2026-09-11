import Testing
import Foundation
import SwiftData
@testable import IBVault

@Suite("Progression Fingerprint Tests")
struct ProgressionFingerprintTests {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Subject.self, StudyCard.self, Grade.self, ReviewSession.self, UserProfile.self, Achievement.self, SubjectTrack.self, StudySession.self, AcademicAssessment.self, AcademicAssessmentMapping.self, AcademicReportSnapshot.self, configurations: config)
    }

    @MainActor
    @Test("Identical fingerprint returns early with no writes")
    func identicalFingerprintNoWrites() throws {
        ProgressionService.resetFingerprintForTesting()
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(UserProfile())
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "#10B981")
        context.insert(subject)
        let card = StudyCard(topicName: "Cells", front: "Q", back: "A", subject: subject)
        card.totalReviewCount = 3
        card.successfulReviewCount = 3
        card.proficiency = .proficient
        context.insert(card)
        try context.save()

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        _ = ProgressionService.recompute(context: context, now: now)
        let tracks = try context.fetch(FetchDescriptor<SubjectTrack>())
        let firstLastComputed = tracks.first?.lastComputed

        let second = ProgressionService.recompute(context: context, now: now)
        let tracks2 = try context.fetch(FetchDescriptor<SubjectTrack>())
        let secondLastComputed = tracks2.first?.lastComputed

        #expect(second.isEmpty)
        #expect(firstLastComputed == secondLastComputed)
        ProgressionService.resetFingerprintForTesting()
    }

    @MainActor
    @Test("Changed input triggers recompute")
    func changedInputTriggersRecompute() throws {
        ProgressionService.resetFingerprintForTesting()
        let container = try makeContainer()
        let context = container.mainContext
        let profile = UserProfile()
        context.insert(profile)
        let subject = Subject(name: "Chemistry", level: "SL", accentColorHex: "#3B82F6")
        context.insert(subject)
        let card = StudyCard(topicName: "Bonding", front: "Q", back: "A", subject: subject)
        context.insert(card)
        try context.save()

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        _ = ProgressionService.recompute(context: context, now: now)
        let tracks = try context.fetch(FetchDescriptor<SubjectTrack>())
        let before = tracks.first?.cachedMastery ?? -1

        // Change input: add a reviewed card
        let card2 = StudyCard(topicName: "Bonding", front: "Q2", back: "A2", subject: subject)
        card2.totalReviewCount = 5
        card2.successfulReviewCount = 5
        card2.proficiency = .mastered
        context.insert(card2)
        try context.save()
        // Also need review session for global mastery
        try context.save()
        let events = ProgressionService.recompute(context: context, now: now)
        let tracks2 = try context.fetch(FetchDescriptor<SubjectTrack>())
        let after = tracks2.first?.cachedMastery ?? -1
        #expect(before != after || !events.isEmpty || after > 0)
        ProgressionService.resetFingerprintForTesting()
    }
}
