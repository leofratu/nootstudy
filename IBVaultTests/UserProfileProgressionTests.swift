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

    @Test("Repeated same-day calls do not mint unlimited streak freezes")
    func sameDayCallsDoNotMintFreezes() {
        let profile = UserProfile()
        profile.currentStreak = 6
        profile.streakFreezes = 0
        profile.lastStudyDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())

        // First call crosses the 7-day milestone: exactly one freeze.
        profile.checkAndUpdateStreak()
        #expect(profile.currentStreak == 7)
        #expect(profile.streakFreezes == 1)

        // Subsequent same-day calls leave the streak at 7 and must not mint more.
        profile.checkAndUpdateStreak()
        profile.checkAndUpdateStreak()
        #expect(profile.currentStreak == 7)
        #expect(profile.streakFreezes == 1)
    }

    @Test("A streak freeze is consumed for a one-day gap and the streak continues")
    func freezeIsConsumedForOneDayGap() {
        let profile = UserProfile()
        profile.currentStreak = 5
        profile.streakFreezes = 1
        profile.longestStreak = 5
        profile.lastStudyDate = Calendar.current.date(byAdding: .day, value: -2, to: Date())

        // diff == 2: one freeze is spent and the streak survives.
        profile.checkAndUpdateStreak()
        #expect(profile.currentStreak == 6)
        #expect(profile.streakFreezes == 0)
        #expect(profile.longestStreak == 6)
    }

    @Test("Crossing a milestone through a freeze still awards exactly one freeze")
    func milestoneCrossedViaFreezeAwardsOneFreeze() {
        let profile = UserProfile()
        profile.currentStreak = 6
        profile.streakFreezes = 1
        profile.lastStudyDate = Calendar.current.date(byAdding: .day, value: -2, to: Date())

        // 6 -> 7 via freeze consumption (-1) then the 7-day milestone (+1):
        // net balance unchanged, exactly one freeze left.
        profile.checkAndUpdateStreak()
        #expect(profile.currentStreak == 7)
        #expect(profile.streakFreezes == 1)
        #expect(profile.longestStreak == 7)
    }

    @Test("A freeze is not spent for a longer absence than a single missed day")
    func freezeNotSpentForLongerGap() {
        let profile = UserProfile()
        profile.currentStreak = 5
        profile.streakFreezes = 1
        profile.lastStudyDate = Calendar.current.date(byAdding: .day, value: -3, to: Date())

        profile.checkAndUpdateStreak()
        #expect(profile.currentStreak == 1)
        #expect(profile.streakFreezes == 1)
    }

    @Test("A missed day with no freeze resets the streak without awarding a milestone")
    func missedDayWithoutFreezeResetsStreak() {
        let profile = UserProfile()
        profile.currentStreak = 12
        profile.streakFreezes = 0
        profile.longestStreak = 12
        profile.lastStudyDate = Calendar.current.date(byAdding: .day, value: -2, to: Date())

        profile.checkAndUpdateStreak()
        #expect(profile.currentStreak == 1)
        #expect(profile.streakFreezes == 0)
        #expect(profile.longestStreak == 12)
    }

    @Test("The very first streak call starts the streak at one")
    func firstCallStartsStreakAtOne() {
        let profile = UserProfile()
        #expect(profile.lastStudyDate == nil)

        profile.checkAndUpdateStreak()

        #expect(profile.currentStreak == 1)
        #expect(profile.longestStreak == 1)
        #expect(profile.lastStudyDate != nil)
    }

    @Test("A same-day call leaves a non-milestone streak completely unchanged")
    func sameDayCallLeavesNonMilestoneStreakUnchanged() {
        let profile = UserProfile()
        profile.currentStreak = 3
        profile.longestStreak = 3
        profile.streakFreezes = 0
        profile.lastStudyDate = Date()

        profile.checkAndUpdateStreak()

        #expect(profile.currentStreak == 3)
        #expect(profile.longestStreak == 3)
        #expect(profile.streakFreezes == 0)
    }

    @Test("A consecutive-day call increments the streak exactly once")
    func consecutiveDayCallIncrementsStreak() {
        let profile = UserProfile()
        profile.currentStreak = 4
        profile.longestStreak = 4
        profile.streakFreezes = 0
        profile.lastStudyDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())

        profile.checkAndUpdateStreak()

        #expect(profile.currentStreak == 5)
        #expect(profile.longestStreak == 5)
        #expect(profile.streakFreezes == 0)
    }
}
