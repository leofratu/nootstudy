// IBVaultTests/RankProgressTests.swift
import Testing
import Foundation
@testable import IBVault

@Suite("Rank Progress Tests")
struct RankProgressTests {

    @Test("Displayed rank is the live rank when it is at or above the mark")
    func displayedFollowsLiveWhenClimbing() {
        let progress = RankProgress(liveMastery: 0.30, achieved: RankStep(forMastery: 0.20))
        #expect(progress.displayed == RankStep(forMastery: 0.30))
        #expect(progress.isFading == false)
    }

    @Test("Displayed rank holds at the high-water mark when mastery falls")
    func displayedHoldsWhenFalling() {
        let progress = RankProgress(liveMastery: 0.10, achieved: RankStep(forMastery: 0.60))
        #expect(progress.displayed == RankStep(forMastery: 0.60))
        #expect(progress.isFading == true)
    }

    @Test("A track exactly at its mark is not fading")
    func atMarkIsNotFading() {
        let progress = RankProgress(liveMastery: 0.60, achieved: RankStep(forMastery: 0.60))
        #expect(progress.isFading == false)
    }

    @Test("Advancing returns the new mark only when it improves")
    func advancingMarkOnlyImproves() {
        let mark = RankStep(forMastery: 0.60)
        #expect(RankProgress.advanced(mark: mark, liveMastery: 0.90) == RankStep(forMastery: 0.90))
        #expect(RankProgress.advanced(mark: mark, liveMastery: 0.10) == mark)
    }

    @Test("Progress towards the next step is a clamped fraction")
    func progressToNextStep() {
        let ordinal = 3
        let halfway = RankStep(ordinal: ordinal).masteryThreshold + (RankStep.stepSize / 2)
        let progress = RankProgress(liveMastery: halfway, achieved: RankStep(ordinal: 0))
        #expect(abs(progress.fractionToNextStep - 0.5) < 0.0001)

        // At the top of the ladder there is nowhere further to go.
        let topped = RankProgress(liveMastery: 1.0, achieved: RankStep(ordinal: RankStep.maxOrdinal))
        #expect(topped.fractionToNextStep == 1.0)
    }
}
