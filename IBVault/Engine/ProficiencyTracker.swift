import Foundation
import SwiftData

struct ProficiencyConfig {
    var masteryRepetitionsThreshold: Int = 6
    var masteryIntervalThreshold: Int = 21
    var masterySuccessRateThreshold: Double = 0.85
    
    var proficientRepetitionsThreshold: Int = 3
    var proficientIntervalThreshold: Int = 7
    var proficientSuccessRateThreshold: Double = 0.65
    
    var developingConsecutiveThreshold: Int = 2
    var developingReviewCountThreshold: Int = 2
    
    static let `default` = ProficiencyConfig()
}

enum ProficiencyTracker {
    static func updateProficiency(for card: StudyCard, config: ProficiencyConfig = .default) {
        let successRate = card.effectivenessRate
        let reviewCount = card.totalReviewCount
        
        let level: ProficiencyLevel
        
        if card.repetitions >= config.masteryRepetitionsThreshold &&
            card.interval >= config.masteryIntervalThreshold &&
            successRate >= config.masterySuccessRateThreshold {
            level = .mastered
        } else if card.repetitions >= config.proficientRepetitionsThreshold &&
                    card.interval >= config.proficientIntervalThreshold &&
                    successRate >= config.proficientSuccessRateThreshold {
            level = .proficient
        } else if card.consecutiveCorrect >= config.developingConsecutiveThreshold ||
                    reviewCount >= config.developingReviewCountThreshold {
            level = .developing
        } else {
            level = .novice
        }
        
        card.proficiency = level
    }
    
    static func masteryPercentage(for subject: Subject) -> Double {
        calculateMastery(for: subject.cards)
    }
    
    static func masteryPercentage(for subject: Subject, topicName: String) -> Double {
        let topicCards = subject.cards.filter { $0.topicName == topicName }
        return calculateMastery(for: topicCards)
    }
    
    static func masteryPercentage(for subject: Subject, topicName: String, subtopic: String) -> Double {
        let subtopicCards = subject.cards.filter {
            $0.topicName == topicName && $0.subtopic == subtopic
        }
        return calculateMastery(for: subtopicCards)
    }
    
    static func weakTopics(for subject: Subject) -> [StudyCard] {
        subject.cards
            .filter { $0.proficiency == .novice || $0.proficiency == .developing }
            .sorted { $0.consecutiveCorrect < $1.consecutiveCorrect }
    }
    
    static func effectiveAICards(for subject: Subject) -> [StudyCard] {
        subject.cards.filter { ($0.isAIGenerated ?? false) && $0.isEffective }
    }
    
    static func strugglingAICards(for subject: Subject) -> [StudyCard] {
        subject.cards.filter { ($0.isAIGenerated ?? false) && $0.isStruggling }
    }
    
    static func topicEffectiveness(
        for subject: Subject,
        topicName: String
    ) -> (effective: Int, struggling: Int, total: Int) {
        let topicCards = subject.cards.filter {
            $0.topicName == topicName && ($0.isAIGenerated ?? false)
        }
        let effective = topicCards.filter { $0.isEffective }.count
        let struggling = topicCards.filter { $0.isStruggling }.count
        return (effective, struggling, topicCards.count)
    }
    
    static func overallAIEffectiveness(for subject: Subject) -> Double {
        let aiCards = subject.cards.filter {
            ($0.isAIGenerated ?? false) && $0.totalReviewCount >= 3
        }
        guard !aiCards.isEmpty else { return 0 }
        let effectiveCount = aiCards.filter { $0.isEffective }.count
        return Double(effectiveCount) / Double(aiCards.count)
    }
    
    static func retentionRate(from sessions: [ReviewSession]) -> Double {
        guard !sessions.isEmpty else { return 0 }
        let correct = sessions.filter { $0.wasCorrect }.count
        return Double(correct) / Double(sessions.count)
    }
    
    private static func calculateMastery(for cards: [StudyCard]) -> Double {
        guard !cards.isEmpty else { return 0 }
        
        let weights: [ProficiencyLevel: Double] = [
            .novice: 0,
            .developing: 0.33,
            .proficient: 0.66,
            .mastered: 1.0
        ]
        
        let score = cards.reduce(0.0) { sum, card in
            sum + (weights[card.proficiency] ?? 0)
        }
        
        return score / Double(cards.count)
    }
}