import Testing
import Foundation
@testable import IBVault

@Suite("Rank Ladder Tests")
struct RankLadderTests {

    @Test("The ladder has ten ranks and thirty steps")
    func ladderShape() {
        #expect(Rank.allCases.count == 10)
        #expect(RankTier.allCases.count == 3)
        #expect(RankStep.maxOrdinal == 29)
    }

    @Test("Zero mastery is Electron III")
    func floorOfLadder() {
        let step = RankStep(forMastery: 0)
        #expect(step.rank == .electron)
        #expect(step.tier == .three)
        #expect(step.ordinal == 0)
    }

    @Test("Negative mastery clamps to the bottom rather than crashing")
    func negativeMasteryClamps() {
        #expect(RankStep(forMastery: -5).ordinal == 0)
    }

    @Test("Supernova I is entered at exactly 0.87 and not at 0.869")
    func topOfLadderBoundary() {
        // Guards the floating point trap: 0.87 / 0.03 == 28.999999999999996.
        let atBoundary = RankStep(forMastery: 0.87)
        #expect(atBoundary.rank == .supernova)
        #expect(atBoundary.tier == .one)
        #expect(atBoundary.ordinal == 29)

        // Supernova occupies ordinals 27, 28, 29 — so one step below the top is
        // Supernova II, not the previous rank.
        let justBelow = RankStep(forMastery: 0.869)
        #expect(justBelow.ordinal == 28)
        #expect(justBelow.rank == .supernova)
        #expect(justBelow.tier == .two)

        // Star I is the last step before Supernova, at ordinal 26.
        let starTop = RankStep(forMastery: 0.78)
        #expect(starTop.ordinal == 26)
        #expect(starTop.rank == .star)
        #expect(starTop.tier == .one)
    }

    @Test("Mastery above the top of the ladder stays at Supernova I")
    func aboveTopClamps() {
        #expect(RankStep(forMastery: 1.0).ordinal == 29)
        #expect(RankStep(forMastery: 99).ordinal == 29)
    }

    @Test("Tiers ascend III to II to I within a rank")
    func tiersAscendWithinRank() {
        // Atom occupies ordinals 3, 4, 5.
        #expect(RankStep(forMastery: 0.09).rank == .atom)
        #expect(RankStep(forMastery: 0.09).tier == .three)
        #expect(RankStep(forMastery: 0.12).tier == .two)
        #expect(RankStep(forMastery: 0.15).tier == .one)
        #expect(RankStep(forMastery: 0.18).rank == .molecule)
    }

    @Test("Steps order by ordinal")
    func stepsAreComparable() {
        #expect(RankStep(forMastery: 0.10) < RankStep(forMastery: 0.50))
        #expect(max(RankStep(forMastery: 0.10), RankStep(forMastery: 0.50)).ordinal == 16)
    }

    @Test("Display name combines rank and tier numeral")
    func displayName() {
        #expect(RankStep(forMastery: 0.87).displayName == "Supernova I")
        #expect(RankStep(forMastery: 0).displayName == "Electron III")
    }
}
