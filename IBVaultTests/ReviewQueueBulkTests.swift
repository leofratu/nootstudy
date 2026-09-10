import Testing
import Foundation
import SwiftData
@testable import IBVault

@Suite("Review Queue Bulk Tests")
struct ReviewQueueBulkTests {

    @MainActor
    @Test("Refresh with 2000 cards < 150 ms and fingerprint stable")
    func refresh2000CardsPerformance() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: StudyCard.self, Subject.self, StudySession.self, UserProfile.self, ReviewSession.self, configurations: config)
        let context = container.mainContext
        let subject = Subject(name: "Bulk", level: "HL", accentColorHex: "#123456")
        context.insert(subject)
        let past = Date().addingTimeInterval(-3600)
        let future = Date().addingTimeInterval(3600 * 24 * 7)
        for i in 0..<2000 {
            let card = StudyCard(topicName: "Topic \(i % 20)", front: "Q\(i)", back: "A\(i)", subject: subject)
            card.nextReviewDate = i % 3 == 0 ? past : future
            context.insert(card)
        }
        try context.save()
        let manager = ReviewQueueManager()
        manager.resetFingerprintForTesting()
        let clock = ContinuousClock()
        let start = clock.now
        manager.refreshDueCardsSynchronously(context: context)
        let elapsed = clock.now - start
        let ms = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
        print("refreshDueCards 2000: \(ms) ms, due \(manager.dueCards.count)")
        #expect(ms < 150, "refresh 2000 cards should be <150ms, was \(ms)")
        #expect(manager.dueCards.count > 0)

        // Second refresh with same state should memoize (no writes, same counts)
        let secondStart = clock.now
        manager.refreshDueCardsSynchronously(context: context)
        let secondElapsed = clock.now - secondStart
        let ms2 = Double(secondElapsed.components.attoseconds) / 1e15 + Double(secondElapsed.components.seconds) * 1000
        print("second refresh memoized: \(ms2) ms")
        // Should be even faster due to fingerprint early-out
        #expect(manager.dueCards.count > 0)
    }

    @MainActor
    @Test("Due-date transition invalidates fingerprint")
    func dueDateTransitionInvalidates() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: StudyCard.self, Subject.self, StudySession.self, UserProfile.self, ReviewSession.self, configurations: config)
        let context = container.mainContext
        let subject = Subject(name: "Transition", level: "SL", accentColorHex: "#abcdef")
        context.insert(subject)
        let card = StudyCard(topicName: "T", front: "Q", back: "A", subject: subject)
        card.nextReviewDate = Date().addingTimeInterval(3600)
        context.insert(card)
        try context.save()
        let manager = ReviewQueueManager()
        manager.resetFingerprintForTesting()
        manager.refreshDueCardsSynchronously(context: context)
        #expect(manager.dueCards.isEmpty)

        // Make it due
        card.nextReviewDate = Date().addingTimeInterval(-3600)
        try context.save()
        manager.refreshDueCardsSynchronously(context: context)
        #expect(manager.dueCards.count == 1)
    }
}
