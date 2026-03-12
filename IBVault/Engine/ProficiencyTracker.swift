import Foundation
import SwiftData

struct ProficiencyTracker {
    /// Update proficiency using both recall streak and longer-term SM-2 stability.
    static func updateProficiency(for card: StudyCard) {
        let successRate = card.effectivenessRate
        let reviewCount = card.totalReviewCount

        let level: ProficiencyLevel
        if card.repetitions >= 6 && card.interval >= 21 && successRate >= 0.85 {
            level = .mastered
        } else if card.repetitions >= 3 && card.interval >= 7 && successRate >= 0.65 {
            level = .proficient
        } else if card.consecutiveCorrect >= 2 || reviewCount >= 2 {
            level = .developing
        } else {
            level = .novice
        }

        card.proficiency = level
    }

    /// Calculate overall mastery percentage for a subject
    static func masteryPercentage(for subject: Subject) -> Double {
        calculateMastery(for: subject.cards)
    }

    /// Calculate mastery percentage for a specific topic
    static func masteryPercentage(for subject: Subject, topicName: String) -> Double {
        let topicCards = subject.cards.filter { $0.topicName == topicName }
        return calculateMastery(for: topicCards)
    }

    /// Calculate mastery percentage for a specific subtopic
    static func masteryPercentage(for subject: Subject, topicName: String, subtopic: String) -> Double {
        let subtopicCards = subject.cards.filter { $0.topicName == topicName && $0.subtopic == subtopic }
        return calculateMastery(for: subtopicCards)
    }

    /// Internal helper to calculate mastery for any subset of cards
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

    /// Get weak topics for a subject (novice or developing)
    static func weakTopics(for subject: Subject) -> [StudyCard] {
        subject.cards.filter { $0.proficiency == .novice || $0.proficiency == .developing }
            .sorted { $0.consecutiveCorrect < $1.consecutiveCorrect }
    }

    /// Get effective AI-generated cards (working well)
    static func effectiveCards(for subject: Subject) -> [StudyCard] {
        subject.cards.filter { ($0.isAIGenerated ?? false) && $0.isEffective }
    }

    /// Get struggling AI-generated cards (not working well)
    static func strugglingCards(for subject: Subject) -> [StudyCard] {
        subject.cards.filter { ($0.isAIGenerated ?? false) && $0.isStruggling }
    }

    /// Get topic-level effectiveness
    static func topicEffectiveness(for subject: Subject, topicName: String) -> (effective: Int, struggling: Int, total: Int) {
        let topicCards = subject.cards.filter { $0.topicName == topicName && ($0.isAIGenerated ?? false) }
        let effective = topicCards.filter { $0.isEffective }.count
        let struggling = topicCards.filter { $0.isStruggling }.count
        return (effective, struggling, topicCards.count)
    }

    /// Get subject-level AI card effectiveness
    static func overallAIEffectiveness(for subject: Subject) -> Double {
        let aiCards = subject.cards.filter { ($0.isAIGenerated ?? false) && $0.totalReviewCount >= 3 }
        guard !aiCards.isEmpty else { return 0 }
        let effectiveCount = aiCards.filter { $0.isEffective }.count
        return Double(effectiveCount) / Double(aiCards.count)
    }

    /// Calculate retention rate from recent review sessions
    static func retentionRate(from sessions: [ReviewSession]) -> Double {
        guard !sessions.isEmpty else { return 0 }
        let correct = sessions.filter { $0.wasCorrect }.count
        return Double(correct) / Double(sessions.count)
    }
}
