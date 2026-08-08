import Foundation

nonisolated enum SubjectLevel: String, Codable, Sendable {
    case hl = "HL"
    case sl = "SL"

    /// HL is 240 teaching hours against SL's 150, so it weighs more.
    var masteryWeight: Double {
        switch self {
        case .hl: return 1.5
        case .sl: return 1.0
        }
    }

    /// Coerces a persisted level string into the typed level.
    ///
    /// `Subject.level` is stored as a bare `String`, so this is the boundary
    /// between untyped storage and the engine. Anything that is not "HL"
    /// is treated as SL; that is deliberate, but it traps in debug builds so a
    /// bad value surfaces in development instead of silently skewing mastery.
    ///
    /// Note this is intentionally lenient, unlike the synthesized failable
    /// `init?(rawValue:)`.
    init(rawLevel: String) {
        let normalized = rawLevel.uppercased()
        assert(
            normalized == "HL" || normalized == "SL",
            "Unrecognized subject level '\(rawLevel)' coerced to SL"
        )
        self = normalized == "HL" ? .hl : .sl
    }
}

nonisolated struct CardSnapshot: Sendable, Equatable {
    /// Compatibility mirror of the scheduler's successful-review count.
    let repetitions: Int
    let intervalDays: Int

    init(repetitions: Int, intervalDays: Int) {
        self.repetitions = repetitions
        self.intervalDays = intervalDays
    }
}

nonisolated struct ReviewSnapshot: Sendable, Equatable {
    let timestamp: Date
    let qualityRating: Int

    /// A recall counts as successful at `RecallQuality.good` (3) or better on
    /// the app's 0–5 recall scale; `again` (0) and `hard` (2) do not.
    var isSuccessful: Bool { qualityRating >= 3 }

    init(timestamp: Date, qualityRating: Int) {
        self.timestamp = timestamp
        self.qualityRating = qualityRating
    }
}

nonisolated struct SubjectSnapshot: Sendable, Equatable {
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
