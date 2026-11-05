import Testing
import Foundation
import SwiftData
@testable import IBVault

@Suite("Progression Service Tests")
struct ProgressionServiceTests {

    // MARK: - Fixtures

    /// Every model `ProgressionService.recompute` reads or writes, in memory.
    @MainActor
    private static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Subject.self,
            StudyCard.self,
            Grade.self,
            ReviewSession.self,
            UserProfile.self,
            Achievement.self,
            SubjectTrack.self,
            configurations: config
        )
    }

    /// Populates the achievement catalogue the way a real launch does.
    @MainActor
    private static func seedAchievements(into context: ModelContext) {
        Achievement.reconcile(context: context)
    }

    /// A card driven to `repetitions == 3` by three good recalls, plus one
    /// `ReviewSession` row per recall so the engine can see the history.
    @MainActor
    @discardableResult
    private static func recordReviewedCard(
        topic: String,
        in subject: Subject,
        context: ModelContext,
        recalls: Int = 3
    ) throws -> StudyCard {
        let card = StudyCard(topicName: topic, front: "Q", back: "A", subject: subject)
        context.insert(card)

        for _ in 0..<recalls {
            try FSRSScheduler.applyReview(to: card, quality: .good)
            context.insert(
                ReviewSession(
                    cardID: card.id,
                    subjectName: subject.name,
                    topicName: topic,
                    qualityRating: RecallQuality.good.rawValue
                )
            )
        }

        return card
    }

    // MARK: - Achievements

    /// Regression: `.cardsReviewed` rules were evaluated against a stored
    /// tally that nothing ever incremented, so "First Steps" was unreachable.
    @MainActor
    @Test("A single recorded review unlocks the first_review achievement")
    func firstReviewUnlocksAfterOneReview() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        context.insert(UserProfile())
        Self.seedAchievements(into: context)

        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "#10B981")
        context.insert(subject)
        try Self.recordReviewedCard(topic: "Cells", in: subject, context: context, recalls: 1)

        let events = ProgressionService.recompute(context: context)

        let achievements = try context.fetch(FetchDescriptor<Achievement>())
        let firstReview = try #require(achievements.first { $0.id == "first_review" })
        #expect(firstReview.unlocked)
        #expect(firstReview.unlockDate != nil)
        #expect(events.contains(.achievementUnlocked(id: "first_review", title: firstReview.title)))

        // The volume tiers above one review must stay locked.
        #expect(achievements.first { $0.id == "cards_100" }?.unlocked == false)
    }

    @MainActor
    @Test("Recompute is idempotent and never re-announces an unlocked achievement")
    func recomputeIsIdempotent() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        context.insert(UserProfile())
        Self.seedAchievements(into: context)

        let subject = Subject(name: "Physics", level: "HL", accentColorHex: "#3B82F6")
        context.insert(subject)
        try Self.recordReviewedCard(topic: "Mechanics", in: subject, context: context)

        let first = ProgressionService.recompute(context: context)
        let second = ProgressionService.recompute(context: context)

        func unlockedIDs(_ events: [ProgressionEvent]) -> [String] {
            events.compactMap {
                if case .achievementUnlocked(let id, _) = $0 { return id }
                return nil
            }
        }

        #expect(!unlockedIDs(first).isEmpty)
        #expect(unlockedIDs(second).isEmpty)
        #expect(Set(unlockedIDs(first)).intersection(unlockedIDs(second)).isEmpty)

        // A second pass must not fork the cached state either.
        let tracks = try context.fetch(FetchDescriptor<SubjectTrack>())
        #expect(tracks.filter { $0.subjectName == "Physics" }.count == 1)
    }

    // MARK: - Mastery and rank

    @MainActor
    @Test("A subject with recorded successful reviews earns a track with non-zero mastery")
    func reviewedSubjectProducesMastery() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        context.insert(UserProfile())
        let subject = Subject(name: "Chemistry", level: "HL", accentColorHex: "#F59E0B")
        context.insert(subject)

        for index in 0..<4 {
            try Self.recordReviewedCard(topic: "Bonding \(index)", in: subject, context: context)
        }

        ProgressionService.recompute(context: context)

        let tracks = try context.fetch(FetchDescriptor<SubjectTrack>())
        let track = try #require(tracks.first { $0.subjectName == "Chemistry" })
        #expect(track.cachedMastery > 0)
        #expect(track.achievedStep.ordinal > 0)
    }

    @MainActor
    @Test("A brand-new profile with no reviews stays at the bottom of the ladder")
    func emptyHistoryProducesNoRankUp() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        let profile = UserProfile()
        context.insert(profile)
        Self.seedAchievements(into: context)

        // Cards exist, but nothing has ever been reviewed.
        let subject = Subject(name: "Economics", level: "SL", accentColorHex: "#8B5CF6")
        context.insert(subject)
        context.insert(StudyCard(topicName: "Demand", front: "Q", back: "A", subject: subject))

        let events = ProgressionService.recompute(context: context)

        #expect(profile.achievedStep == RankStep(ordinal: 0))
        let rankUps = events.filter {
            if case .rankUp = $0 { return true }
            return false
        }
        #expect(rankUps.isEmpty)

        let track = try #require(
            try context.fetch(FetchDescriptor<SubjectTrack>()).first { $0.subjectName == "Economics" }
        )
        #expect(track.cachedMastery == 0)
    }

    // MARK: - SnapshotBuilder

    @MainActor
    @Test("snapshot(for:reviews:) keeps only the reviews belonging to that subject")
    func snapshotFiltersReviewsBySubjectName() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        let biology = Subject(name: "Biology", level: "SL", accentColorHex: "#10B981")
        let physics = Subject(name: "Physics", level: "HL", accentColorHex: "#3B82F6")
        context.insert(biology)
        context.insert(physics)

        let biologyReviews = [
            ReviewSession(cardID: UUID(), subjectName: "Biology", topicName: "Cells", qualityRating: 5),
            ReviewSession(cardID: UUID(), subjectName: "Biology", topicName: "Genetics", qualityRating: 3),
        ]
        let physicsReview = ReviewSession(
            cardID: UUID(),
            subjectName: "Physics",
            topicName: "Mechanics",
            qualityRating: 4
        )
        let allReviews = biologyReviews + [physicsReview]

        let snapshot = SnapshotBuilder.snapshot(for: biology, reviews: allReviews)

        #expect(snapshot.name == "Biology")
        #expect(snapshot.level == .sl)
        #expect(snapshot.reviews.count == 2)
        #expect(Set(snapshot.reviews.map(\.qualityRating)) == [5, 3])

        let physicsSnapshot = SnapshotBuilder.snapshot(for: physics, reviews: allReviews)
        #expect(physicsSnapshot.reviews.map(\.qualityRating) == [4])
        #expect(physicsSnapshot.level == .hl)
    }
}

@Suite("Achievement Reconcile Tests")
struct AchievementReconcileTests {

    @MainActor
    private static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Achievement.self, configurations: config)
    }

    @MainActor
    @Test("Reconciling an empty store installs the whole catalogue with usable rules")
    func reconcileSeedsEmptyStore() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        Achievement.reconcile(context: context)

        let rows = try context.fetch(FetchDescriptor<Achievement>())
        #expect(rows.count == Achievement.definitions.count)
        #expect(Set(rows.map(\.id)) == Set(Achievement.definitions.map(\.id)))
        #expect(rows.allSatisfy { AchievementRule(rawValue: $0.ruleRaw) != nil })
    }

    @MainActor
    @Test("Reconciling twice does not duplicate rows")
    func reconcileIsIdempotent() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        Achievement.reconcile(context: context)
        Achievement.reconcile(context: context)
        Achievement.reconcile(context: context)

        let rows = try context.fetch(FetchDescriptor<Achievement>())
        #expect(rows.count == Achievement.definitions.count)
    }

    @MainActor
    @Test("An upgraded row with an empty rule is repaired without being re-locked")
    func reconcileBackfillsRuleAndPreservesUnlock() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        // How a pre-progression row migrates in: ruleRaw defaulted to "".
        let earned = Achievement(
            id: "first_review",
            title: "First Steps",
            desc: "Complete your first review",
            icon: "figure.walk",
            category: "milestone"
        )
        earned.unlocked = true
        let unlockDate = Date(timeIntervalSince1970: 1_700_000_000)
        earned.unlockDate = unlockDate
        context.insert(earned)

        Achievement.reconcile(context: context)

        let rows = try context.fetch(FetchDescriptor<Achievement>())
        let repaired = try #require(rows.first { $0.id == "first_review" })
        #expect(AchievementRule(rawValue: repaired.ruleRaw) == .cardsReviewed(1))
        #expect(repaired.unlocked)
        #expect(repaired.unlockDate == unlockDate)
        #expect(rows.count == Achievement.definitions.count)
    }

    @MainActor
    @Test("A stored rule that still parses is left untouched")
    func reconcileDoesNotOverwriteStoredRules() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        let customised = Achievement(
            id: "cards_100",
            title: "Century Club",
            desc: "Review 100 cards total",
            icon: "square.stack.3d.up.fill",
            category: "volume",
            ruleRaw: AchievementRule.cardsReviewed(42).rawValue,
            tier: 3
        )
        context.insert(customised)

        Achievement.reconcile(context: context)

        let rows = try context.fetch(FetchDescriptor<Achievement>())
        let row = try #require(rows.first { $0.id == "cards_100" })
        #expect(AchievementRule(rawValue: row.ruleRaw) == .cardsReviewed(42))
        #expect(row.tier == 3)
    }

    @MainActor
    @Test("Retired ids are deleted and duplicates collapse onto the earned row")
    func reconcileRemovesGhostsAndCollapsesDuplicates() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        for ghostID in ["perfect_10", "bio_master", "econ_master", "math_master"] {
            context.insert(
                Achievement(id: ghostID, title: ghostID, desc: "", icon: "star", category: "legacy")
            )
        }

        // The old seed ran without an existence check, so stores can hold
        // more than one row per id.
        let locked = Achievement(
            id: "streak_7",
            title: "7-Day Warrior",
            desc: "Maintain a 7-day streak",
            icon: "flame.fill",
            category: "streak"
        )
        let earned = Achievement(
            id: "streak_7",
            title: "7-Day Warrior",
            desc: "Maintain a 7-day streak",
            icon: "flame.fill",
            category: "streak"
        )
        earned.unlocked = true
        context.insert(locked)
        context.insert(earned)

        Achievement.reconcile(context: context)

        let rows = try context.fetch(FetchDescriptor<Achievement>())
        #expect(Set(rows.map(\.id)) == Set(Achievement.definitions.map(\.id)))
        #expect(rows.count == Achievement.definitions.count)

        let streak = rows.filter { $0.id == "streak_7" }
        #expect(streak.count == 1)
        #expect(streak.first?.unlocked == true)
    }

    @MainActor
    @Test("Unpaid review sittings are credited once and logged sittings are left alone")
    func unpaidReviewRepair() throws {
        let container = try ModelContainer(
            for: Subject.self, StudyCard.self, Grade.self, ReviewSession.self, UserProfile.self,
            StudySession.self, StudyActivity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = UserProfile()
        profile.totalXP = 100
        context.insert(profile)

        let unpaidID = UUID()
        let loggedID = UUID()
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        func review(_ rating: Int, session: UUID?, offset: TimeInterval = 0) {
            let entry = ReviewSession(cardID: UUID(), subjectName: "Biology", topicName: "Cells", qualityRating: rating, studySessionID: session)
            entry.timestamp = at.addingTimeInterval(offset)
            context.insert(entry)
        }
        review(3, session: unpaidID)
        review(5, session: unpaidID, offset: 600)
        review(5, session: loggedID)
        review(5, session: nil)
        context.insert(StudySession(id: loggedID, subjectName: "Biology", topicsCovered: "Cells", startDate: at,
                                    endDate: at, cardsReviewed: 1, correctCount: 1, xpEarned: 0))
        try context.save()

        // Good (10) + Easy (15) at the default 1.0 multiplier.
        #expect(try UnpaidReviewRepair.run(context: context) == 25)
        #expect(profile.totalXP == 125)
        let sessions = try context.fetch(FetchDescriptor<StudySession>())
        #expect(sessions.count == 2)
        let repaired = try #require(sessions.first { $0.id == unpaidID })
        #expect(repaired.cardsReviewed == 2 && repaired.correctCount == 2 && repaired.xpEarned == 25)
        #expect(repaired.evidenceVersion != nil)
        let activity = try #require(context.fetch(FetchDescriptor<StudyActivity>()).first)
        #expect(activity.cardsReviewed == 2 && activity.xpEarned == 25 && abs(activity.minutesStudied - 10) < 0.001)

        #expect(try UnpaidReviewRepair.run(context: context) == 0)
        #expect(profile.totalXP == 125)
    }

    @Test("Repair pays logged sessions no activity ever recorded, once")
    func unpaidLoggedSessions() throws {
        let container = try ModelContainer(
            for: Subject.self, StudyCard.self, Grade.self, ReviewSession.self, UserProfile.self,
            StudySession.self, StudyActivity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = UserProfile()
        context.insert(profile)
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func date(daysAgo: Int) -> Date { calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now }
        func session(daysAgo: Int, xp: Int) {
            context.insert(StudySession(subjectName: "Economics", topicsCovered: "Demand", startDate: date(daysAgo: daysAgo),
                                        endDate: date(daysAgo: daysAgo), cardsReviewed: 2, correctCount: 2, xpEarned: xp))
        }
        session(daysAgo: 40, xp: 70)
        // Paid, with its activity a day away: the time-zone offset seen in real history.
        session(daysAgo: 20, xp: 30)
        context.insert(StudyActivity(date: calendar.startOfDay(for: date(daysAgo: 21)), cardsReviewed: 2, minutesStudied: 1, xpEarned: 30))
        // Paid, with its activity stored away from this calendar's midnight.
        session(daysAgo: 30, xp: 40)
        let offsetActivity = StudyActivity(cardsReviewed: 2, minutesStudied: 1, xpEarned: 40)
        offsetActivity.date = calendar.startOfDay(for: date(daysAgo: 30)).addingTimeInterval(3_600)
        context.insert(offsetActivity)
        try context.save()

        #expect(try UnpaidReviewRepair.run(context: context, now: now, calendar: calendar) == 70)
        #expect(profile.totalXP == 70)
        #expect(try UnpaidReviewRepair.run(context: context, now: now, calendar: calendar) == 0)
        #expect(profile.totalXP == 70)
    }

    @Test("Repair restores streak days from history and never lowers a streak")
    func repairRestoresStreak() throws {
        let container = try ModelContainer(
            for: Subject.self, StudyCard.self, Grade.self, ReviewSession.self, UserProfile.self,
            StudySession.self, StudyActivity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = UserProfile()
        profile.currentStreak = 1
        profile.longestStreak = 2
        context.insert(profile)
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // Two days ending yesterday, and an older four-day run. Nil sessions pay nothing.
        for daysAgo in [1, 2, 10, 11, 12, 13] {
            let entry = ReviewSession(cardID: UUID(), subjectName: "Biology", topicName: "Cells", qualityRating: 3, sessionDuration: 1)
            entry.timestamp = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            context.insert(entry)
        }
        try context.save()

        #expect(try UnpaidReviewRepair.run(context: context, now: now, calendar: calendar) == 0)
        #expect(profile.currentStreak == 2)
        #expect(profile.longestStreak == 4)

        profile.currentStreak = 9
        _ = try UnpaidReviewRepair.run(context: context, now: now, calendar: calendar)
        #expect(profile.currentStreak == 9)
    }
}
