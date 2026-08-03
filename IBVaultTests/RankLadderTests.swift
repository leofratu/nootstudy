import Testing
import Foundation
@testable import IBVault

@Suite("Rank Ladder Tests")
struct RankLadderTests {

    @Test("The ladder has fifteen ranks and forty-five steps")
    func ladderShape() {
        #expect(Rank.allCases.count == 15)
        #expect(RankTier.allCases.count == 3)
        #expect(RankStep.maxOrdinal == 44)
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

    @Test("Universe I is entered at full mastery")
    func topOfLadderBoundary() {
        let atBoundary = RankStep(forMastery: 1.0)
        #expect(atBoundary.rank == .universe)
        #expect(atBoundary.tier == .one)
        #expect(atBoundary.ordinal == 44)

        let justBelow = RankStep(ordinal: 43)
        #expect(justBelow.rank == .universe)
        #expect(justBelow.tier == .two)

        let cosmicWebTop = RankStep(ordinal: 41)
        #expect(cosmicWebTop.rank == .cosmicWeb)
        #expect(cosmicWebTop.tier == .one)
    }

    @Test("Mastery above the top of the ladder stays at Universe I")
    func aboveTopClamps() {
        #expect(RankStep(forMastery: 1.0).ordinal == 44)
        #expect(RankStep(forMastery: 99).ordinal == 44)
    }

    @Test("Tiers ascend III to II to I within a rank")
    func tiersAscendWithinRank() {
        #expect(RankStep(ordinal: 3).rank == .atom)
        #expect(RankStep(ordinal: 3).tier == .three)
        #expect(RankStep(ordinal: 4).tier == .two)
        #expect(RankStep(ordinal: 5).tier == .one)
        #expect(RankStep(ordinal: 6).rank == .molecule)
    }

    @Test("Steps order by ordinal")
    func stepsAreComparable() {
        #expect(RankStep(forMastery: 0.10) < RankStep(forMastery: 0.50))
        #expect(max(RankStep(forMastery: 0.10), RankStep(forMastery: 0.50)).ordinal == 22)
    }

    @Test("Display name combines rank and tier numeral")
    func displayName() {
        #expect(RankStep(forMastery: 1.0).displayName == "Universe I")
        #expect(RankStep(forMastery: 0).displayName == "Electron III")
    }
}
