import Testing
@testable import IBVault

@Suite("User Rank Tests")
struct UserRankTests {
    @Test("Rank lookup chooses the highest threshold not above XP")
    func rankLookupUsesThresholds() {
        #expect(UserRank.rank(forXP: -10) == .electron)
        #expect(UserRank.rank(forXP: 0) == .electron)
        #expect(UserRank.rank(forXP: 499) == .molecule)
        #expect(UserRank.rank(forXP: 500) == .catalyst)
        #expect(UserRank.rank(forXP: 7_000) == .supernova)
    }

    @Test("Progress to next rank is clamped")
    func progressToNextRankIsClamped() {
        let profile = UserProfile()
        profile.totalXP = -50

        #expect(profile.progressToNextRank == 0)

        profile.totalXP = 7_500
        profile.rank = .supernova

        #expect(profile.progressToNextRank == 1)
    }

    @Test("Adding non-positive XP does not demote or mutate profile")
    func nonPositiveXPIsIgnored() {
        let profile = UserProfile()
        profile.totalXP = 500
        profile.rank = .catalyst

        profile.addXP(-200)
        profile.addXP(0)

        #expect(profile.totalXP == 500)
        #expect(profile.rank == .catalyst)
    }
}
