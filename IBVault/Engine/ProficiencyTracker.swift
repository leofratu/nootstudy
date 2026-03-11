import Foundation

struct ProficiencyTracker {
    /// Update proficiency level based on consecutive correct recalls
    static func updateProficiency(for card: StudyCard) {
        let level: ProficiencyLevel
        switch card.consecutiveCorrect {
        case 0...1:
            level = .novice
        case 2...3:
            level = .developing
        case 4...6:
            level = .proficient
        default:
            level = .mastered
        }
        card.proficiency = level
    }

    /// Calculate overall mastery percentage for a subject
    static func masteryPercentage(for subject: Subject) -> Double {
        guard !subject.cards.isEmpty else { return 0 }
        let total = subject.cards.count
        let weights: [ProficiencyLevel: Double] = [
            .novice: 0,
            .developing: 0.33,
            .proficient: 0.66,
            .mastered: 1.0
        ]
        let score = subject.cards.reduce(0.0) { sum, card in
            sum + (weights[card.proficiency] ?? 0)
        }
        return score / Double(total)
    }

    /// Get weak topics for a subject (novice or developing)
    static func weakTopics(for subject: Subject) -> [StudyCard] {
        subject.cards.filter { $0.proficiency == .novice || $0.proficiency == .developing }
            .sorted { $0.consecutiveCorrect < $1.consecutiveCorrect }
    }

    /// Calculate retention rate from recent review sessions
    static func retentionRate(from sessions: [ReviewSession]) -> Double {
        guard !sessions.isEmpty else { return 0 }
        let correct = sessions.filter { $0.wasCorrect }.count
        return Double(correct) / Double(sessions.count)
    }
}
