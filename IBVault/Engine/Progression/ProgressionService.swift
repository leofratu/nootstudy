import Foundation
import SwiftData

/// Recomputes progression from recorded work and reports what changed.
/// Call after any session completes. Safe to call repeatedly.
///
/// Contract: `context` must be the main-actor `ModelContext` (the app's
/// `container.mainContext`). Every read and the final save run against it, so
/// this must be called from the main actor. It is deliberately not annotated
/// `@MainActor` — that would force every test and view to await it — but a
/// background context must never be passed in.
enum ProgressionService: Sendable {

    @discardableResult
    static func recompute(context: ModelContext, now: Date = Date()) -> [ProgressionEvent] {
        let subjects: [Subject]
        let reviews: [ReviewSession]
        let profiles: [UserProfile]
        let achievements: [Achievement]
        let tracks: [SubjectTrack]
        do {
            subjects = try context.fetch(FetchDescriptor<Subject>())
            reviews = try context.fetch(FetchDescriptor<ReviewSession>())
            profiles = try context.fetch(FetchDescriptor<UserProfile>())
            achievements = try context.fetch(FetchDescriptor<Achievement>())
            tracks = try context.fetch(FetchDescriptor<SubjectTrack>())
        } catch {
            // A partial read must not recompute from half a store: that could
            // overwrite good cached mastery with zeroes. Abort the pass so a
            // later call retries against the full picture.
            #if DEBUG
            assertionFailure("Progression recompute read failed: \(error.localizedDescription)")
            #endif
            return []
        }
        guard let profile = profiles.first else { return [] }

        var events: [ProgressionEvent] = []
        let snapshots = SnapshotBuilder.snapshots(for: subjects, reviews: reviews)

        // Per-subject tracks.
        for snapshot in snapshots {
            let mastery = MasteryCalculator.mastery(for: snapshot, now: now)
            let track = tracks.first { $0.subjectName == snapshot.name }
                ?? {
                    let created = SubjectTrack(subjectName: snapshot.name)
                    context.insert(created)
                    return created
                }()

            let previous = track.achievedStep
            track.cachedMastery = mastery
            track.lastComputed = now
            track.achievedStep = RankProgress.advanced(mark: previous, liveMastery: mastery)
            if track.achievedStep > previous {
                events.append(.tierUp(subjectName: snapshot.name, to: track.achievedStep))
            }
        }

        // Global rank.
        let globalMastery = MasteryCalculator.globalMastery(for: snapshots, now: now)
        let previousGlobal = profile.achievedStep
        if let advanced = profile.advanceRank(liveMastery: globalMastery) {
            events.append(.rankUp(from: previousGlobal, to: advanced))
        }

        // Achievements.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let todaysReviews = reviews.filter { calendar.startOfDay(for: $0.timestamp) == today }
        let achievementContext = AchievementContext(
            // Counted from the review history rather than a stored tally: the
            // tally had no writer, so every .cardsReviewed rule was
            // unsatisfiable. Deriving it is also self-healing for existing
            // users and cannot drift out of step with recorded work.
            totalCardsReviewed: reviews.count,
            currentStreak: profile.currentStreak,
            totalXP: profile.totalXP,
            globalMastery: globalMastery,
            distinctSubjectsToday: Set(todaysReviews.map(\.subjectName)).count,
            lastReviewHour: reviews.map(\.timestamp).max().map { calendar.component(.hour, from: $0) }
        )
        for unlocked in AchievementEvaluator.evaluate(achievements: achievements, context: achievementContext) {
            events.append(.achievementUnlocked(id: unlocked.id, title: unlocked.title))
        }

        do {
            try context.save()
        } catch {
            // Never present a rank-up/tier-up that did not persist: the caller
            // uses the returned events to congratulate the user, and a fake
            // celebration for a reverted write is worse than a quiet skip.
            #if DEBUG
            assertionFailure("Progression save failed: \(error.localizedDescription)")
            #endif
            return []
        }
        return events
    }
}
