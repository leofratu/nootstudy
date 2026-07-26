import Testing
import Foundation
@testable import IBVault

@Suite("User Profile Progression Tests")
struct UserProfileProgressionTests {

    @Test("A new profile starts at the bottom of the ladder")
    func newProfileStartsAtElectronIII() {
        let profile = UserProfile()
        #expect(profile.achievedStep == RankStep(ordinal: 0))
        #expect(profile.totalXP == 0)
    }

    @Test("Recording XP never changes rank")
    func xpDoesNotAffectRank() {
        let profile = UserProfile()
        profile.recordXP(10_000)
        #expect(profile.totalXP == 10_000)
        #expect(profile.achievedStep == RankStep(ordinal: 0))
    }

    @Test("Non-positive XP is ignored")
    func nonPositiveXPIsIgnored() {
        let profile = UserProfile()
        profile.recordXP(500)
        profile.recordXP(-200)
        profile.recordXP(0)
        #expect(profile.totalXP == 500)
    }

    @Test("Advancing rank raises the mark and reports the new step")
    func advancingRaisesMark() {
        let profile = UserProfile()
        let advanced = profile.advanceRank(liveMastery: 0.30)
        #expect(advanced == RankStep(forMastery: 0.30))
        #expect(profile.achievedStep == RankStep(forMastery: 0.30))
        #expect(profile.rankUpDate != nil)
    }

    @Test("Falling mastery never lowers the mark and reports no change")
    func fallingMasteryDoesNotDemote() {
        let profile = UserProfile()
        profile.advanceRank(liveMastery: 0.60)
        let mark = profile.achievedStep

        let advanced = profile.advanceRank(liveMastery: 0.05)
        #expect(advanced == nil)
        #expect(profile.achievedStep == mark)
    }
}
