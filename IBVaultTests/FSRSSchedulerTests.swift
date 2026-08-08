import Testing
import Foundation
@testable import IBVault

@Suite("FSRS Scheduler")
struct FSRSSchedulerTests {
    @Test("Review XP retains the existing reward scale")
    func reviewXPMatchesRewardScale() {
        #expect(FSRSScheduler.xp(for: .again) == 2)
        #expect(FSRSScheduler.xp(for: .hard) == 5)
        #expect(FSRSScheduler.xp(for: .good) == 10)
        #expect(FSRSScheduler.xp(for: .easy) == 15)
    }

    @MainActor
    @Test("A review persists FSRS state and records a versioned rating")
    func appliesFSRSReview() throws {
        let card = StudyCard(topicName: "Cells", subtopic: "Membranes", front: "Q", back: "A")
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        try FSRSScheduler.applyReview(to: card, quality: .good, now: now)
        let session = ReviewSession(cardID: card.id, subjectName: "Biology", topicName: "Cells", qualityRating: RecallQuality.good.rawValue)
        FSRSScheduler.configure(session, quality: .good)

        #expect(card.fsrsSchedulerVersion == FSRSScheduler.schedulerVersion)
        #expect(card.fsrsStability != nil)
        #expect(card.fsrsStateRaw != nil)
        #expect(card.nextReviewDate >= now)
        #expect(card.totalReviewCount == 1)
        #expect(card.successfulReviewCount == 1)
        #expect(session.fsrsRatingRaw != nil)
        #expect(session.schedulerVersion == FSRSScheduler.schedulerVersion)
    }

    @MainActor
    @Test("Legacy review history is replayed during migration")
    func migrationReplaysHistory() {
        let card = StudyCard(topicName: "Cells", subtopic: "Membranes", front: "Q", back: "A")
        card.createdDate = Date(timeIntervalSince1970: 1_700_000_000)
        let session = ReviewSession(cardID: card.id, subjectName: "Biology", topicName: "Cells", qualityRating: RecallQuality.good.rawValue)
        session.timestamp = card.createdDate.addingTimeInterval(86_400)

        FSRSScheduler.migrate(cards: [card], reviewSessions: [session])

        #expect(card.fsrsSchedulerVersion == FSRSScheduler.schedulerVersion)
        #expect(card.fsrsRepetitions == 1)
        #expect(card.fsrsLastReviewDate == session.timestamp)
    }
}
