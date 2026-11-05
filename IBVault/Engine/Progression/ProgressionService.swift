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
    private static var lastFingerprint: String?
    private static var lastFingerprintContextID: ObjectIdentifier?

    static func resetFingerprintForTesting() {
        lastFingerprint = nil
        lastFingerprintContextID = nil
    }

    private static func makeFingerprint(
        subjects: [Subject],
        reviews: [ReviewSession],
        profiles: [UserProfile],
        tracks: [SubjectTrack],
        studySessions: [StudySession],
        assessments: [AcademicAssessment],
        mappings: [AcademicAssessmentMapping],
        reports: [AcademicReportSnapshot],
        achievements: [Achievement],
        now: Date
    ) -> String {
        var hasher = Hasher()
        hasher.combine(subjects.count)
        hasher.combine(reviews.count)
        hasher.combine(assessments.count)
        hasher.combine(mappings.count)
        hasher.combine(reports.count)
        hasher.combine(studySessions.count)
        hasher.combine(achievements.count)
        hasher.combine(tracks.count)
        if let profile = profiles.first {
            hasher.combine(profile.totalXP)
            hasher.combine(profile.currentStreak)
            hasher.combine(profile.achievedRankRaw)
            hasher.combine(profile.achievedTierRaw)
        }
        // Counts + lastUpdated signals: include per-card mastery signals and
        // review timestamps so any material change invalidates the cache.
        // Truncate now to day so daily freshness decay still triggers recompute.
        hasher.combine(Calendar.current.startOfDay(for: now).timeIntervalSince1970)
        for subject in subjects.sorted(by: { $0.name < $1.name }) {
            hasher.combine(subject.name)
            hasher.combine(subject.level)
            hasher.combine(subject.cards.count)
            for card in subject.cards.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                hasher.combine(card.id)
                hasher.combine(card.totalReviewCount)
                hasher.combine(card.successfulReviewCount)
                hasher.combine(card.proficiencyRaw)
                hasher.combine(card.lastReviewedDate?.timeIntervalSince1970 ?? 0)
                hasher.combine(card.nextReviewDate.timeIntervalSince1970)
                hasher.combine(card.interval)
                hasher.combine(card.repetitions)
            }
        }
        for review in reviews.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(review.id)
            hasher.combine(review.timestamp.timeIntervalSince1970)
            hasher.combine(review.qualityRating)
        }
        for track in tracks.sorted(by: { $0.subjectName < $1.subjectName }) {
            hasher.combine(track.subjectName)
            hasher.combine(track.cachedMastery)
            hasher.combine(track.achievedRankRaw)
            hasher.combine(track.achievedTierRaw)
        }
        hasher.combine(studySessions.reduce(0) { $0 + $1.xpEarned })
        return String(hasher.finalize())
    }

    @discardableResult
    static func recompute(context: ModelContext, now: Date = Date()) -> [ProgressionEvent] {
        let subjects: [Subject]
        let reviews: [ReviewSession]
        let profiles: [UserProfile]
        let achievements: [Achievement]
        let tracks: [SubjectTrack]
        let studySessions: [StudySession]
        do {
            subjects = try context.fetch(FetchDescriptor<Subject>())
            reviews = try context.fetch(FetchDescriptor<ReviewSession>())
            profiles = try context.fetch(FetchDescriptor<UserProfile>())
            achievements = try context.fetch(FetchDescriptor<Achievement>())
            tracks = try context.fetch(FetchDescriptor<SubjectTrack>())
            studySessions = (try? context.fetch(FetchDescriptor<StudySession>())) ?? []
        } catch {
            // A partial read must not recompute from half a store: that could
            // overwrite good cached mastery with zeroes. Abort the pass so a
            // later call retries against the full picture.
            #if DEBUG
            assertionFailure("Progression recompute read failed: \(error.localizedDescription)")
            #endif
            return []
        }
        // Academic imports were added after the core progression store. Treat
        // them as optional evidence so an older or deliberately narrow model
        // container can still recompute from cards and review history.
        let assessments = (try? context.fetch(FetchDescriptor<AcademicAssessment>())) ?? []
        let mappings = (try? context.fetch(FetchDescriptor<AcademicAssessmentMapping>())) ?? []
        let reports = (try? context.fetch(FetchDescriptor<AcademicReportSnapshot>())) ?? []
        guard let profile = profiles.first else { return [] }

        let fingerprint = makeFingerprint(
            subjects: subjects,
            reviews: reviews,
            profiles: profiles,
            tracks: tracks,
            studySessions: studySessions,
            assessments: assessments,
            mappings: mappings,
            reports: reports,
            achievements: achievements,
            now: now
        )
        let contextID = ObjectIdentifier(context.container)
        if let last = lastFingerprint, last == fingerprint, lastFingerprintContextID == contextID {
            return []
        }

        var events: [ProgressionEvent] = []
        let snapshots = SnapshotBuilder.snapshots(for: subjects, reviews: reviews)
        var masteryBySubject: [String: Double] = [:]

        // Per-subject tracks.
        for (subject, snapshot) in zip(subjects, snapshots) {
            let mastery = ProgressEvidenceService.score(
                subjectName: subject.name,
                courseLevel: subject.level,
                cards: subject.cards,
                assessments: assessments,
                mappings: mappings,
                reports: reports,
                workSessions: studySessions,
                now: now
            ).blendedMastery ?? MasteryCalculator.mastery(for: snapshot, now: now)
            masteryBySubject[subject.name] = mastery
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
        let totalWeight = subjects.reduce(0.0) { $0 + SubjectLevel(rawLevel: $1.level).masteryWeight }
        let globalMastery = totalWeight > 0
            ? subjects.reduce(0.0) {
                $0 + (masteryBySubject[$1.name] ?? 0) * SubjectLevel(rawLevel: $1.level).masteryWeight
            } / totalWeight
            : 0
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
            lastFingerprint = fingerprint
            lastFingerprintContextID = contextID
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

/// Review sittings closed before their last card used to reschedule the cards
/// without paying XP or logging a session. Rebuilds both from the review history,
/// then pays logged sessions that never reached the XP total and restores
/// streak days those reviews should have earned.
enum UnpaidReviewRepair: Sendable {
    /// A sitting left open overnight must not count as a day of study.
    private static let maximumMinutesPerSitting = 180.0

    /// Returns the XP credited. Reviews whose session already exists are skipped.
    @discardableResult
    static func run(context: ModelContext, now: Date = IBLocalClock.now, calendar: Calendar = IBLocalClock.calendar) throws -> Int {
        guard let profile = try context.fetch(FetchDescriptor<UserProfile>()).first else { return 0 }
        let logged = try context.fetch(FetchDescriptor<StudySession>())
        let loggedIDs = Set(logged.map(\.id))
        let unpaid = try context.fetch(FetchDescriptor<ReviewSession>()).filter {
            guard let id = $0.studySessionID else { return false }
            return !loggedIDs.contains(id)
        }
        let sittings = Dictionary(grouping: unpaid) { $0.studySessionID ?? UUID() }
        // Keyed by local day: rows written under another time zone or clock are
        // not stored at exactly this calendar's midnight.
        var activities = Dictionary(
            try context.fetch(FetchDescriptor<StudyActivity>()).map { (calendar.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // Read before sittings below add days of their own.
        let unpaidSessions = logged.filter { session in
            guard session.xpEarned > 0 else { return false }
            let day = calendar.startOfDay(for: session.startDate)
            // Activity can sit a day either side when a session crossed midnight
            // or was logged in another time zone; that session was still paid.
            return (-1...1).allSatisfy { offset in
                calendar.date(byAdding: .day, value: offset, to: day).map { activities[$0] == nil } ?? true
            }
        }

        var totalXP = 0
        for (id, reviews) in sittings {
            let start = reviews.map(\.timestamp).min() ?? Date()
            let end = reviews.map(\.timestamp).max() ?? start
            let minutes = min(end.timeIntervalSince(start) / 60, maximumMinutesPerSitting)
            let qualities = reviews.map { quality(forStoredRating: $0.qualityRating) }
            let xp = XPCalculator.xp(forQualities: qualities, intensity: profile.studyIntensity)
            let subjects = Set(reviews.map(\.subjectName))
            let evidence = Dictionary(grouping: reviews, by: \.topicName).map { topic, entries in
                StudySessionSubunitEvidence(
                    topicName: topic,
                    subtopicName: "",
                    minutes: minutes * Double(entries.count) / Double(reviews.count),
                    confidenceRating: confidence(for: entries),
                    cardsReviewed: entries.count,
                    correctCount: entries.filter(\.wasCorrect).count
                )
            }
            context.insert(StudySession(
                id: id,
                subjectName: subjects.count == 1 ? subjects.first ?? "Mixed" : "Mixed",
                topicsCovered: Set(reviews.map(\.topicName)).sorted().joined(separator: ", "),
                startDate: start,
                endDate: end,
                cardsReviewed: reviews.count,
                correctCount: reviews.filter(\.wasCorrect).count,
                xpEarned: xp,
                subunitEvidence: evidence,
                reviewedCardIDs: reviews.map(\.cardID)
            ))

            let day = calendar.startOfDay(for: end)
            if let activity = activities[day] {
                activity.cardsReviewed += reviews.count
                activity.minutesStudied += minutes
                activity.xpEarned += xp
            } else {
                let activity = StudyActivity(date: day, cardsReviewed: reviews.count, minutesStudied: minutes, xpEarned: xp)
                context.insert(activity)
                activities[day] = activity
            }
            totalXP += xp
        }
        for session in unpaidSessions {
            let day = calendar.startOfDay(for: session.startDate)
            if let activity = activities[day] {
                activity.cardsReviewed += session.cardsReviewed
                activity.minutesStudied += min(session.duration / 60, maximumMinutesPerSitting)
                activity.xpEarned += session.xpEarned
            } else {
                let activity = StudyActivity(
                    date: day,
                    cardsReviewed: session.cardsReviewed,
                    minutesStudied: min(session.duration / 60, maximumMinutesPerSitting),
                    xpEarned: session.xpEarned
                )
                context.insert(activity)
                activities[day] = activity
            }
            totalXP += session.xpEarned
        }
        profile.recordXP(totalXP)
        let studied = try context.fetch(FetchDescriptor<ReviewSession>()).map(\.timestamp) + logged.map(\.startDate)
        restoreStreak(for: profile, studied: studied, now: now, calendar: calendar)
        try context.save()
        return totalXP
    }

    /// Only raises: freezes can legitimately hold a streak above what the
    /// history alone shows, and past achievements must not be taken back.
    private static func restoreStreak(for profile: UserProfile, studied: [Date], now: Date, calendar: Calendar) {
        let days = Set(studied.filter { $0 <= now }.map { calendar.startOfDay(for: $0) }).sorted()
        guard let latest = days.last else { return }
        var longest = 1
        var run = 1
        for (previous, day) in zip(days, days.dropFirst()) {
            let isNextDay = calendar.date(byAdding: .day, value: 1, to: previous) == day
            run = isNextDay ? run + 1 : 1
            longest = max(longest, run)
        }
        profile.longestStreak = max(profile.longestStreak, longest)
        let daysSince = calendar.dateComponents([.day], from: latest, to: calendar.startOfDay(for: now)).day ?? 0
        if daysSince <= 1 {
            profile.currentStreak = max(profile.currentStreak, run)
        }
        if profile.lastStudyDate.map({ $0 < latest }) ?? true {
            profile.lastStudyDate = latest
        }
    }

    private static func quality(forStoredRating rating: Int) -> RecallQuality {
        switch rating {
        case ..<1: return .again
        case 1...2: return .hard
        case 3...4: return .good
        default: return .easy
        }
    }

    /// Same scale the review sheet uses when it logs a finished sitting.
    private static func confidence(for reviews: [ReviewSession]) -> Int {
        let total = reviews.reduce(0.0) { sum, review in
            switch quality(forStoredRating: review.qualityRating) {
            case .again: return sum + 1
            case .hard: return sum + 2
            case .good: return sum + 4
            case .easy: return sum + 5
            }
        }
        return Int((total / Double(max(reviews.count, 1))).rounded())
    }
}
