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

    init(id: String, title: String, desc: String, icon: String, category: String = "general") {
        self.id = id
        self.title = title
        self.desc = desc
        self.icon = icon
        self.unlocked = false
        self.category = category
    }

    static let definitions: [(id: String, title: String, desc: String, icon: String, category: String)] = [
        ("streak_7", "7-Day Warrior", "Maintain a 7-day study streak", "flame.fill", "streak"),
        ("streak_30", "Monthly Master", "Maintain a 30-day study streak", "flame.circle.fill", "streak"),
        ("perfect_10", "Perfect Recall ×10", "Rate 'Easy' 10 times in a row", "brain.head.profile", "recall"),
        ("bio_master", "Biology Master", "Master all Biology SL topics", "leaf.fill", "subject"),
        ("econ_master", "Economics Master", "Master all Economics HL topics", "chart.line.uptrend.xyaxis", "subject"),
        ("math_master", "Mathematics Master", "Master all Maths AA SL topics", "function", "subject"),
        ("first_review", "First Steps", "Complete your first review session", "footprints", "milestone"),
        ("cards_100", "Century Club", "Review 100 cards total", "square.stack.3d.up.fill", "milestone"),
        ("cards_500", "Card Conqueror", "Review 500 cards total", "trophy.fill", "milestone"),
        ("night_owl", "Night Owl", "Study after 10 PM", "moon.stars.fill", "special"),
        ("early_bird", "Early Bird", "Study before 7 AM", "sunrise.fill", "special"),
        ("all_subjects", "Renaissance Scholar", "Review cards from all 6 subjects in one day", "graduationcap.fill", "special"),
        ("xp_1000", "XP Millionaire", "Earn 1,000 XP total", "star.circle.fill", "xp"),
        ("xp_5000", "XP Legend", "Earn 5,000 XP total", "star.fill", "xp"),
    ]
}
