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
        for definition in Achievement.definitions {
            context.insert(
                Achievement(
                    id: definition.id,
                    title: definition.title,
                    desc: definition.desc,
                    icon: definition.icon,
                    category: definition.category,
                    ruleRaw: definition.rule.rawValue,
                    tier: definition.tier
                )
            )
        }
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
    ) -> StudyCard {
        let card = StudyCard(topicName: topic, front: "Q", back: "A", subject: subject)
        context.insert(card)

        for _ in 0..<recalls {
            SM2Engine.applyReview(to: card, quality: .good)
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

    @MainActor
    @Test("Recompute is idempotent and never re-announces an unlocked achievement")
    func recomputeIsIdempotent() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        context.insert(UserProfile())
        Self.seedAchievements(into: context)

        let subject = Subject(name: "Physics", level: "HL", accentColorHex: "#3B82F6")
        context.insert(subject)
        Self.recordReviewedCard(topic: "Mechanics", in: subject, context: context)

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
            Self.recordReviewedCard(topic: "Bonding \(index)", in: subject, context: context)
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
