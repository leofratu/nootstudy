import Foundation

enum SubjectLevel: String, Codable, Sendable {
    case hl = "HL"
    case sl = "SL"

    /// HL is 240 teaching hours against SL's 150, so it weighs more.
    var masteryWeight: Double {
        switch self {
        case .hl: return 1.5
        case .sl: return 1.0
        }
    }

    init(rawLevel: String) {
        self = rawLevel.uppercased() == "HL" ? .hl : .sl
    }
}

struct CardSnapshot: Sendable, Equatable {
    let repetitions: Int
    let intervalDays: Int

    init(repetitions: Int, intervalDays: Int) {
        self.repetitions = repetitions
        self.intervalDays = intervalDays
    }
}

struct ReviewSnapshot: Sendable, Equatable {
    let timestamp: Date
    let qualityRating: Int

    var isSuccessful: Bool { qualityRating >= 3 }

    init(timestamp: Date, qualityRating: Int) {
        self.timestamp = timestamp
        self.qualityRating = qualityRating
    }
}

struct SubjectSnapshot: Sendable, Equatable {
    let name: String
    let level: SubjectLevel
    let cards: [CardSnapshot]
    let reviews: [ReviewSnapshot]

    var lastReviewDate: Date? {
        reviews.map(\.timestamp).max()
    }

    init(name: String, level: SubjectLevel, cards: [CardSnapshot], reviews: [ReviewSnapshot]) {
        self.name = name
        self.level = level
        self.cards = cards
        self.reviews = reviews
    }
}
