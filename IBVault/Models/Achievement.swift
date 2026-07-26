import Foundation
import SwiftData

@Model
final class Achievement {
    var id: String
    var title: String
    var desc: String
    var icon: String
    var unlocked: Bool
    var unlockDate: Date?
    var category: String
    var ruleRaw: String = ""
    var tier: Int = 1

    init(
        id: String,
        title: String,
        desc: String,
        icon: String,
        category: String = "general",
        ruleRaw: String = "",
        tier: Int = 1
    ) {
        self.id = id
        self.title = title
        self.desc = desc
        self.icon = icon
        self.unlocked = false
        self.category = category
        self.ruleRaw = ruleRaw
        self.tier = tier
    }

    static let definitions: [(id: String, title: String, desc: String, icon: String, category: String, rule: AchievementRule, tier: Int)] = [
        ("first_review", "First Steps", "Complete your first review", "figure.walk", "milestone", .cardsReviewed(1), 1),
        ("cards_100", "Century Club", "Review 100 cards total", "square.stack.3d.up.fill", "volume", .cardsReviewed(100), 1),
        ("cards_500", "Card Conqueror", "Review 500 cards total", "trophy.fill", "volume", .cardsReviewed(500), 2),
        ("cards_2000", "Card Sovereign", "Review 2,000 cards total", "crown.fill", "volume", .cardsReviewed(2000), 3),
        ("streak_7", "7-Day Warrior", "Maintain a 7-day streak", "flame.fill", "streak", .streakDays(7), 1),
        ("streak_30", "Monthly Master", "Maintain a 30-day streak", "flame.circle.fill", "streak", .streakDays(30), 2),
        ("streak_100", "Centurion", "Maintain a 100-day streak", "medal.fill", "streak", .streakDays(100), 3),
        ("xp_1000", "Momentum", "Earn 1,000 XP total", "star.circle.fill", "xp", .totalXP(1000), 1),
        ("xp_5000", "XP Legend", "Earn 5,000 XP total", "star.fill", "xp", .totalXP(5000), 2),
        ("xp_20000", "Unstoppable", "Earn 20,000 XP total", "sparkles", "xp", .totalXP(20000), 3),
        ("mastery_25", "Foundations", "Reach 25% overall mastery", "chart.bar.fill", "mastery", .globalMastery(0.25), 1),
        ("mastery_50", "Halfway There", "Reach 50% overall mastery", "chart.bar.doc.horizontal.fill", "mastery", .globalMastery(0.50), 2),
        ("mastery_75", "Deep Knowledge", "Reach 75% overall mastery", "brain.head.profile", "mastery", .globalMastery(0.75), 3),
        ("all_subjects", "Renaissance Scholar", "Review all 6 subjects in one day", "graduationcap.fill", "consistency", .subjectsInOneDay(6), 1),
        ("night_owl", "Night Owl", "Study after 10 PM", "moon.stars.fill", "special", .studiedAfterHour(22), 1),
        ("early_bird", "Early Bird", "Study before 7 AM", "sunrise.fill", "special", .studiedBeforeHour(7), 1),
    ]
}
