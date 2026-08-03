import Testing
import Foundation

@testable import IBVault

@Suite("SM2Engine Tests")
struct SM2EngineTests {
    
    @Test("Initial card state should have correct defaults")
    func testInitialCardState() {
        let card = createTestCard()
        
        #expect(card.easeFactor == 2.5)
        #expect(card.interval == 0)
        #expect(card.repetitions == 0)
        #expect(card.consecutiveCorrect == 0)
        #expect(card.totalReviewCount == 0)
    }
    
    @Test("Again quality should reset repetitions")
    func testAgainResetsRepetitions() {
        let card = createTestCard()
        card.repetitions = 5
        card.interval = 10
        
        let result = SM2Engine.calculateNextReview(card: card, quality: .again)
        
        #expect(result.repetitions == 0)
        #expect(result.interval == 1)
    }
    
    @Test("Hard quality should reset repetitions")
    func testHardResetsRepetitions() {
        let card = createTestCard()
        card.repetitions = 5
        card.interval = 10
        
        let result = SM2Engine.calculateNextReview(card: card, quality: .hard)
        
        #expect(result.repetitions == 0)
        #expect(result.interval == 1)
    }
    
    @Test("First successful recall should set interval to 1")
    func testFirstSuccessInterval() {
        let card = createTestCard()
        
        let result = SM2Engine.calculateNextReview(card: card, quality: .good)
        
        #expect(result.interval == 1)
        #expect(result.repetitions == 1)
    }
    
    @Test("Second successful recall should set interval to 6")
    func testSecondSuccessInterval() {
        let card = createTestCard()
        card.repetitions = 1
        
        let result = SM2Engine.calculateNextReview(card: card, quality: .good)
        
        #expect(result.interval == 6)
        #expect(result.repetitions == 2)
    }
    
    @Test("Third successful recall should use ease factor")
    func testThirdSuccessInterval() {
        let card = createTestCard()
        card.repetitions = 2
        card.interval = 6
        card.easeFactor = 2.5
        
        let result = SM2Engine.calculateNextReview(card: card, quality: .good)
        
        let expectedInterval = Int(round(6.0 * 2.5))
        #expect(result.interval == expectedInterval)
        #expect(result.repetitions == 3)
    }
    
    @Test("Easy quality should increase ease factor")
    func testEasyIncreasesEaseFactor() {
        let card = createTestCard()
        
        let result = SM2Engine.calculateNextReview(card: card, quality: .easy)
        
        #expect(result.easeFactor > 2.5)
    }
    
    @Test("Again quality should decrease ease factor")
    func testAgainDecreasesEaseFactor() {
        let card = createTestCard()
        card.easeFactor = 2.5
        
        let result = SM2Engine.calculateNextReview(card: card, quality: .again)
        
        #expect(result.easeFactor < 2.5)
    }
    
    @Test("Ease factor should not go below minimum")
    func testMinimumEaseFactor() {
        let card = createTestCard()
        card.easeFactor = 1.4
        
        let result = SM2Engine.calculateNextReview(card: card, quality: .again)
        
        #expect(result.easeFactor >= 1.3)
    }
    
    @Test("XP for review should return correct values")
    func testXPForReview() {
        #expect(SM2Engine.xpForReview(.again) == 2)
        #expect(SM2Engine.xpForReview(.hard) == 5)
        #expect(SM2Engine.xpForReview(.good) == 10)
        #expect(SM2Engine.xpForReview(.easy) == 15)
    }
    
    @Test("Apply review should update card properties")
    func testApplyReview() {
        let card = createTestCard()
        
        SM2Engine.applyReview(to: card, quality: .good)
        
        #expect(card.totalReviewCount == 1)
        #expect(card.successfulReviewCount == 1)
        #expect(card.consecutiveCorrect == 1)
        #expect(card.repetitions == 1)
    }
    
    @Test("Apply review with again should reset consecutive correct")
    func testApplyReviewAgainResetsConsecutive() {
        let card = createTestCard()
        card.consecutiveCorrect = 5
        
        SM2Engine.applyReview(to: card, quality: .again)
        
        #expect(card.consecutiveCorrect == 0)
        #expect(card.successfulReviewCount == 0)
    }

    @Test("Apply review handles every recall quality and its counters")
    func testApplyReviewAllQualities() {
        let again = createTestCard()
        SM2Engine.applyReview(to: again, quality: .again)
        #expect(again.interval == 1)
        #expect(again.repetitions == 0)
        #expect(again.consecutiveCorrect == 0)
        #expect(again.successfulReviewCount == 0)
        #expect(again.totalReviewCount == 1)
        #expect(again.proficiency == .novice)

        let hard = createTestCard()
        SM2Engine.applyReview(to: hard, quality: .hard)
        #expect(hard.interval == 1)
        #expect(hard.repetitions == 0)
        #expect(hard.consecutiveCorrect == 0)
        #expect(hard.successfulReviewCount == 0)
        #expect(hard.totalReviewCount == 1)

        let good = createTestCard()
        SM2Engine.applyReview(to: good, quality: .good)
        #expect(good.interval == 1)
        #expect(good.repetitions == 1)
        #expect(good.consecutiveCorrect == 1)
        #expect(good.successfulReviewCount == 1)
        #expect(good.totalReviewCount == 1)

        let easy = createTestCard()
        SM2Engine.applyReview(to: easy, quality: .easy)
        #expect(easy.interval == 1)
        #expect(easy.repetitions == 1)
        #expect(easy.consecutiveCorrect == 1)
        #expect(easy.successfulReviewCount == 1)
        #expect(easy.totalReviewCount == 1)
        #expect(easy.easeFactor > 2.5)
    }

    @Test("Hard quality should reset consecutive correct like again")
    func testHardResetsConsecutiveCorrect() {
        let card = createTestCard()
        card.consecutiveCorrect = 5
        card.repetitions = 4
        card.interval = 12

        SM2Engine.applyReview(to: card, quality: .hard)

        #expect(card.consecutiveCorrect == 0)
        #expect(card.repetitions == 0)
        #expect(card.interval == 1)
    }

    @Test("Apply review schedules the next review on the SM2 interval")
    func testApplyReviewSchedulesNextDate() {
        let card = createTestCard()
        let before = Date()

        SM2Engine.applyReview(to: card, quality: .good)

        // interval == 1 day, so the next review lands one calendar day out
        // (tolerance 1...2 absorbs a midnight boundary crossing).
        let days = Calendar.current.dateComponents([.day], from: before, to: card.nextReviewDate).day ?? 0
        #expect(card.nextReviewDate > Date())
        #expect((1...2).contains(days))
    }

    @Test("Repeated good reviews climb to mastered, a failure drops proficiency")
    func testApplyReviewMovesProficiencyBothDirections() {
        let card = createTestCard()
        for _ in 0..<6 {
            SM2Engine.applyReview(to: card, quality: .good)
        }

        #expect(card.repetitions == 6)
        #expect(card.interval >= 21)
        #expect(card.effectivenessRate == 1.0)
        #expect(card.proficiency == .mastered)

        SM2Engine.applyReview(to: card, quality: .again)

        #expect(card.repetitions == 0)
        #expect(card.interval == 1)
        #expect(card.consecutiveCorrect == 0)
        // 7 reviews logged but the last one failed: falls back to developing.
        #expect(card.proficiency == .developing)
    }
    
    private func createTestCard() -> StudyCard {
        StudyCard(
            topicName: "Test Topic",
            subtopic: "Test Subtopic",
            front: "Test Front",
            back: "Test Back"
        )
    }
}