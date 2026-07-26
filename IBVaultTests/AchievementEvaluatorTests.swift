import Testing
import Foundation
@testable import IBVault

@Suite("Achievement Evaluator Tests")
struct AchievementEvaluatorTests {

    private func context(
        cards: Int = 0,
        streak: Int = 0,
        xp: Int = 0,
        mastery: Double = 0,
        subjectsToday: Int = 0,
        hour: Int? = nil
    ) -> AchievementContext {
        AchievementContext(
            totalCardsReviewed: cards,
            currentStreak: streak,
            totalXP: xp,
            globalMastery: mastery,
            distinctSubjectsToday: subjectsToday,
            lastReviewHour: hour
        )
    }

    @Test("A volume rule unlocks once its threshold is met")
    func volumeRuleUnlocks() {
        #expect(AchievementRule.cardsReviewed(100).isSatisfied(by: context(cards: 100)))
        #expect(!AchievementRule.cardsReviewed(100).isSatisfied(by: context(cards: 99)))
    }

    @Test("A streak rule unlocks at its threshold")
    func streakRuleUnlocks() {
        #expect(AchievementRule.streakDays(7).isSatisfied(by: context(streak: 7)))
        #expect(!AchievementRule.streakDays(30).isSatisfied(by: context(streak: 29)))
    }

    @Test("Time-of-day rules respect their windows")
    func timeOfDayRules() {
        #expect(AchievementRule.studiedAfterHour(22).isSatisfied(by: context(hour: 23)))
        #expect(!AchievementRule.studiedAfterHour(22).isSatisfied(by: context(hour: 21)))
        #expect(AchievementRule.studiedBeforeHour(7).isSatisfied(by: context(hour: 6)))
        #expect(!AchievementRule.studiedBeforeHour(7).isSatisfied(by: context(hour: 8)))
        #expect(!AchievementRule.studiedAfterHour(22).isSatisfied(by: context(hour: nil)))
    }

    @Test("Rules round-trip through their raw string form")
    func rulesRoundTrip() {
        let rules: [AchievementRule] = [
            .cardsReviewed(500), .streakDays(30), .totalXP(1000),
            .globalMastery(0.75), .subjectsInOneDay(6),
            .studiedAfterHour(22), .studiedBeforeHour(7),
        ]
        for rule in rules {
            #expect(AchievementRule(rawValue: rule.rawValue) == rule)
        }
        #expect(AchievementRule(rawValue: "nonsense") == nil)
        #expect(AchievementRule(rawValue: "cardsReviewed:notanumber") == nil)
    }

    @Test("The evaluator unlocks only newly satisfied achievements")
    func evaluatorUnlocksNewOnly() {
        let alreadyDone = Achievement(id: "cards_100", title: "Century", desc: "", icon: "", category: "volume")
        alreadyDone.ruleRaw = AchievementRule.cardsReviewed(100).rawValue
        alreadyDone.unlocked = true

        let pending = Achievement(id: "cards_500", title: "Conqueror", desc: "", icon: "", category: "volume")
        pending.ruleRaw = AchievementRule.cardsReviewed(500).rawValue

        let unlocked = AchievementEvaluator.evaluate(
            achievements: [alreadyDone, pending],
            context: context(cards: 500)
        )

        #expect(unlocked.count == 1)
        #expect(unlocked.first?.id == "cards_500")
        #expect(pending.unlocked)
        #expect(pending.unlockDate != nil)
    }

    @Test("Re-running the evaluator reports nothing new")
    func evaluationIsIdempotent() {
        let achievement = Achievement(id: "streak_7", title: "Warrior", desc: "", icon: "", category: "streak")
        achievement.ruleRaw = AchievementRule.streakDays(7).rawValue

        let first = AchievementEvaluator.evaluate(achievements: [achievement], context: context(streak: 7))
        let second = AchievementEvaluator.evaluate(achievements: [achievement], context: context(streak: 7))

        #expect(first.count == 1)
        #expect(second.isEmpty)
    }
}
