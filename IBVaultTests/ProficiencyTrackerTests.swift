import Testing
import Foundation

@testable import IBVault

@Suite("ProficiencyTracker Tests")
struct ProficiencyTrackerTests {
    
    @Test("Empty cards should return zero mastery")
    func testEmptyCardsMastery() {
        let mastery = calculateMasteryForCards([])
        
        #expect(mastery == 0.0)
    }
    
    @Test("All novice cards should return zero mastery")
    func testAllNoviceCardsMastery() {
        let cards = [
            createTestCard(proficiency: .novice),
            createTestCard(proficiency: .novice),
            createTestCard(proficiency: .novice)
        ]
        
        let mastery = calculateMasteryForCards(cards)
        
        #expect(mastery == 0.0)
    }
    
    @Test("All mastered cards should return full mastery")
    func testAllMasteredCardsMastery() {
        let cards = [
            createTestCard(proficiency: .mastered),
            createTestCard(proficiency: .mastered),
            createTestCard(proficiency: .mastered)
        ]
        
        let mastery = calculateMasteryForCards(cards)
        
        #expect(abs(mastery - 1.0) < 0.001)
    }
    
    @Test("Mixed proficiency should return correct average")
    func testMixedProficiencyMastery() {
        let cards = [
            createTestCard(proficiency: .novice),
            createTestCard(proficiency: .developing),
            createTestCard(proficiency: .proficient),
            createTestCard(proficiency: .mastered)
        ]
        
        let mastery = calculateMasteryForCards(cards)
        
        #expect(abs(mastery - 0.4975) < 0.01)
    }
    
    @Test("Card with necessary repetitions and interval should become mastered")
    func testMasteredProficiency() {
        let card = createTestCard(proficiency: .developing)
        card.repetitions = 6
        card.interval = 21
        card.totalReviewCount = 10
        card.successfulReviewCount = 9
        
        ProficiencyTracker.updateProficiency(for: card)
        
        #expect(card.proficiency == .mastered)
    }
    
    @Test("Card with moderate stats should become proficient")
    func testProficientProficiency() {
        let card = createTestCard(proficiency: .novice)
        card.repetitions = 3
        card.interval = 7
        card.totalReviewCount = 5
        card.successfulReviewCount = 4
        
        ProficiencyTracker.updateProficiency(for: card)
        
        #expect(card.proficiency == .proficient)
    }
    
    @Test("Card with consecutive correct should become developing")
    func testDevelopingProficiency() {
        let card = createTestCard(proficiency: .novice)
        card.consecutiveCorrect = 2
        card.totalReviewCount = 2
        
        ProficiencyTracker.updateProficiency(for: card)
        
        #expect(card.proficiency == .developing)
    }
    
    @Test("New card should be novice")
    func testNoviceProficiency() {
        let card = createTestCard(proficiency: .novice)
        
        ProficiencyTracker.updateProficiency(for: card)
        
        #expect(card.proficiency == .novice)
    }
    
    @Test("Effective AI card should have high success rate")
    func testEffectiveAICard() {
        let card = createTestCard()
        card.isAIGenerated = true
        card.totalReviewCount = 5
        card.successfulReviewCount = 4
        
        #expect(card.isEffective == true)
        #expect(card.isStruggling == false)
    }
    
    @Test("Struggling AI card should have low success rate")
    func testStrugglingAICard() {
        let card = createTestCard()
        card.isAIGenerated = true
        card.totalReviewCount = 5
        card.successfulReviewCount = 1
        
        #expect(card.isEffective == false)
        #expect(card.isStruggling == true)
    }
    
    @Test("Card with insufficient reviews should not be effective or struggling")
    func testCardWithFewReviews() {
        let card = createTestCard()
        card.isAIGenerated = true
        card.totalReviewCount = 2
        card.successfulReviewCount = 0
        
        #expect(card.isEffective == false)
        #expect(card.isStruggling == false)
    }
    
    @Test("Retention rate should be calculated correctly")
    func testRetentionRate() {
        let sessions = [
            createTestReviewSession(wasCorrect: true),
            createTestReviewSession(wasCorrect: true),
            createTestReviewSession(wasCorrect: false),
            createTestReviewSession(wasCorrect: true)
        ]
        
        let rate = ProficiencyTracker.retentionRate(from: sessions)
        
        #expect(abs(rate - 0.75) < 0.001)
    }
    
    @Test("Empty sessions should return zero retention rate")
    func testEmptyRetentionRate() {
        let rate = ProficiencyTracker.retentionRate(from: [])
        
        #expect(rate == 0.0)
    }

    // MARK: - Division-by-zero guards on the real engine

    @Test("Real engine returns zero mastery for an empty card array, not NaN")
    func realEngineEmptyCardsMasteryIsZero() {
        #expect(ProficiencyTracker.masteryPercentage(for: []) == 0.0)
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        #expect(ProficiencyTracker.masteryPercentage(for: subject) == 0.0)
        #expect(subject.masteryProgress == 0.0)
    }

    @Test("AI effectiveness with no qualifying AI cards is zero, not NaN")
    func aiEffectivenessWithNoQualifyingCardsIsZero() {
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        let card = StudyCard(topicName: "Cells", subtopic: "Prokaryotic structure", front: "Q", back: "A", subject: subject)
        card.isAIGenerated = true
        card.totalReviewCount = 2
        card.successfulReviewCount = 2
        subject.cards.append(card)

        // Only 2 reviews: below the >= 3 gate, so the divisor pool is empty.
        #expect(ProficiencyTracker.overallAIEffectiveness(for: subject) == 0.0)
        #expect(ProficiencyTracker.strugglingAICards(for: subject).isEmpty)
    }

    @Test("Topic mastery for a topic with no cards is zero, not NaN")
    func topicMasteryEmptyIsZero() {
        let subject = Subject(name: "Economics", level: "HL", accentColorHex: "F59E0B")
        let card = StudyCard(topicName: "Demand", front: "Q", back: "A", subject: subject)
        card.proficiency = .mastered
        subject.cards.append(card)

        #expect(ProficiencyTracker.masteryPercentage(for: subject, topicName: "Macro") == 0.0)
        #expect(ProficiencyTracker.masteryPercentage(for: subject, topicName: "Demand") > 0.0)
    }

    @Test("Weighted grade average with a zero-weight grade is still finite")
    func zeroWeightGradeAverageIsFinite() {
        let subject = Subject(name: "Chemistry", level: "HL", accentColorHex: "EF4444")
        let grade = Grade(component: "Paper 1", score: 5, weightPercent: 0, subject: subject)
        subject.grades.append(grade)

        #expect(subject.weightedGradeAverage != nil)
        #expect(subject.weightedGradeAverage?.isFinite == true)
    }
    
    private func createTestCard(proficiency: ProficiencyLevel = .novice) -> StudyCard {
        let card = StudyCard(
            topicName: "Test Topic",
            subtopic: "Test Subtopic",
            front: "Test Front",
            back: "Test Back"
        )
        card.proficiency = proficiency
        return card
    }
    
    private func createTestReviewSession(wasCorrect: Bool) -> ReviewSession {
        let session = ReviewSession(
            cardID: UUID(),
            subjectName: "Test Subject",
            topicName: "Test Topic",
            qualityRating: wasCorrect ? 3 : 0,
            sessionDuration: 10
        )
        session.wasCorrect = wasCorrect
        return session
    }
    
    private func calculateMasteryForCards(_ cards: [StudyCard]) -> Double {
        let weights: [ProficiencyLevel: Double] = [
            .novice: 0,
            .developing: 0.33,
            .proficient: 0.66,
            .mastered: 1.0
        ]
        
        guard !cards.isEmpty else { return 0 }
        
        let score = cards.reduce(0.0) { sum, card in
            sum + (weights[card.proficiency] ?? 0)
        }
        
        return score / Double(cards.count)
    }
}