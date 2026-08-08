import Foundation
import SwiftData

/// Cached progression state for one subject. Recomputed from review history by
/// the engine; never authoritative on its own.
@Model
nonisolated final class SubjectTrack {
    var id: UUID
    var subjectName: String
    var cachedMastery: Double
    var achievedRankRaw: Int
    var achievedTierRaw: Int
    var lastComputed: Date

    var achievedStep: RankStep {
        get {
            RankStep(
                rank: Rank(rawValue: achievedRankRaw) ?? .electron,
                tier: RankTier(rawValue: achievedTierRaw) ?? .three
            )
        }
        set {
            achievedRankRaw = newValue.rank.rawValue
            achievedTierRaw = newValue.tier.rawValue
        }
    }

    var progress: RankProgress {
        RankProgress(liveMastery: cachedMastery, achieved: achievedStep)
    }

    init(subjectName: String) {
        self.id = UUID()
        self.subjectName = subjectName
        self.cachedMastery = 0
        self.achievedRankRaw = Rank.electron.rawValue
        self.achievedTierRaw = RankTier.three.rawValue
        self.lastComputed = Date()
    }
}
