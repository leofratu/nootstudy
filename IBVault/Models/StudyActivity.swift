import Foundation
import SwiftData

@Model
nonisolated final class StudyActivity {
    var id: UUID
    var date: Date
    var cardsReviewed: Int
    var minutesStudied: Double
    var xpEarned: Int

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var dateString: String {
        Self.dateOnlyFormatter.string(from: date)
    }

    var intensity: Int {
        Self.intensity(cardsReviewed: cardsReviewed, minutesStudied: minutesStudied)
    }

    static func intensity(cardsReviewed: Int, minutesStudied: Double) -> Int {
        if cardsReviewed >= 30 || minutesStudied >= 120 { return 4 }
        if cardsReviewed >= 20 || minutesStudied >= 60 { return 3 }
        if cardsReviewed >= 10 || minutesStudied >= 30 { return 2 }
        if cardsReviewed > 0 || minutesStudied > 0 { return 1 }
        return 0
    }

    init(date: Date = Date(), cardsReviewed: Int = 0, minutesStudied: Double = 0, xpEarned: Int = 0) {
        self.id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.cardsReviewed = cardsReviewed
        self.minutesStudied = minutesStudied
        self.xpEarned = xpEarned
    }
}
