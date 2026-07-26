// IBVault/Engine/Progression/RankProgress.swift
import Foundation

/// Combines live mastery with the highest step ever reached. Rank never
/// regresses; decay surfaces as a fading state instead.
struct RankProgress: Sendable, Equatable {
    let liveMastery: Double
    let achieved: RankStep

    var live: RankStep { RankStep(forMastery: liveMastery) }

    var displayed: RankStep { max(live, achieved) }

    var isFading: Bool { live < achieved }

    /// How far through the displayed step the live mastery has travelled.
    /// Returns 1.0 at the top of the ladder, where there is no next step.
    var fractionToNextStep: Double {
        let current = displayed
        guard current.ordinal < RankStep.maxOrdinal else { return 1.0 }
        let floorValue = current.masteryThreshold
        let travelled = (liveMastery - floorValue) / RankStep.stepSize
        return min(max(travelled, 0.0), 1.0)
    }

    init(liveMastery: Double, achieved: RankStep) {
        self.liveMastery = liveMastery
        self.achieved = achieved
    }

    /// The new high-water mark after observing `liveMastery`.
    static func advanced(mark: RankStep, liveMastery: Double) -> RankStep {
        max(mark, RankStep(forMastery: liveMastery))
    }
}
