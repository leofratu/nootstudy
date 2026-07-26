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
        // Ordinal 3 spans 0.09 to 0.12; 0.105 is halfway.
        let progress = RankProgress(liveMastery: 0.105, achieved: RankStep(ordinal: 0))
        #expect(abs(progress.fractionToNextStep - 0.5) < 0.0001)

        // At the top of the ladder there is nowhere further to go.
        let topped = RankProgress(liveMastery: 0.95, achieved: RankStep(ordinal: 29))
        #expect(topped.fractionToNextStep == 1.0)
    }
}
