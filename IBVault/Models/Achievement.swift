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

    /// Brings the stored catalogue in line with `definitions`.
    ///
    /// Must run on every launch, not just the first one. Rows that were stored
    /// before progression rules existed migrate in with an empty `ruleRaw`,
    /// which `AchievementRule(rawValue:)` cannot parse, so `evaluate` skips
    /// them forever and the Profile reports zero unlocks permanently. Seeding
    /// only when no profile exists never reaches those users.
    ///
    /// Earned progress is sacred: `unlocked` and `unlockDate` are never
    /// rewritten, so a reconcile can never re-lock an achievement.
    static func reconcile(context: ModelContext) {
        let shippedIDs = Set(definitions.map(\.id))
        let existing = (try? context.fetch(FetchDescriptor<Achievement>())) ?? []

        var kept: [String: Achievement] = [:]
        for row in existing {
            // Ids dropped from `definitions` linger as permanently locked
            // ghosts that no rule can ever satisfy.
            guard shippedIDs.contains(row.id) else {
                context.delete(row)
                continue
            }
            guard let incumbent = kept[row.id] else {
                kept[row.id] = row
                continue
            }
            // The old seed ran from an `onAppear` without an existence check,
            // so a store can hold duplicates. Collapse them, preferring the
            // earned row so no unlock is thrown away.
            let winner = incumbent.unlocked ? incumbent : row
            kept[row.id] = winner
            context.delete(winner === incumbent ? row : incumbent)
        }

        for definition in definitions {
            guard let row = kept[definition.id] else {
                context.insert(
                    Achievement(
                        id: definition.id,
                        title: definition.title,
                        desc: definition.desc,
                        icon: definition.icon,
                        category: definition.category,
                        ruleRaw: definition.rule.rawValue,
                        tier: definition.tier
                    )
                )
                continue
            }
            // Only repair rows that carry no usable rule; a stored rule is
            // left alone so this stays a repair rather than a reset.
            if row.ruleRaw.isEmpty {
                row.ruleRaw = definition.rule.rawValue
                row.tier = definition.tier
            }
        }

        do {
            try context.save()
        } catch {
            #if DEBUG
            assertionFailure("Achievement reconcile failed: \(error.localizedDescription)")
            #endif
        }
    }
}
