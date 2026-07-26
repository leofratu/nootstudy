import Foundation
import SwiftData

/// Recomputes progression from recorded work and reports what changed.
/// Call after any session completes. Safe to call repeatedly.
enum ProgressionService {

    @discardableResult
    static func recompute(context: ModelContext, now: Date = Date()) -> [ProgressionEvent] {
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        let reviews = (try? context.fetch(FetchDescriptor<ReviewSession>())) ?? []
        let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        let achievements = (try? context.fetch(FetchDescriptor<Achievement>())) ?? []
        guard let profile = profiles.first else { return [] }

        var events: [ProgressionEvent] = []
        let snapshots = SnapshotBuilder.snapshots(for: subjects, reviews: reviews)

        // Per-subject tracks.
        let tracks = (try? context.fetch(FetchDescriptor<SubjectTrack>())) ?? []
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
            // The events above have already been handed to the caller to
            // present. Losing this save would silently undo a rank-up the user
            // has been congratulated on.
            assertionFailure("Progression save failed: \(error.localizedDescription)")
        }
        return events
    }
}
