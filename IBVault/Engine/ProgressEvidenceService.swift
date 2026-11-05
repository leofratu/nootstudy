import Foundation
import SwiftData

nonisolated enum ProgressEvidenceService: Sendable {
    /// Case-insensitive subject+level key used to bucket shared evidence once.
    nonisolated struct SubjectLevelKey: Hashable {
        let name: String
        let level: String

        init(name: String, level: String) {
            self.name = name.lowercased()
            self.level = level.lowercased()
        }
    }

    /// Scores every subject in one pass. The shared assessment/mapping/report/
    /// session arrays are grouped once up front, so the work is O(store) rather
    /// than re-scanning the whole store for each subject (the previous
    /// per-subject `score` calls).
    static func scoreBySubject(
        subjects: [Subject],
        assessments: [AcademicAssessment],
        mappings: [AcademicAssessmentMapping],
        reports: [AcademicReportSnapshot],
        workSessions: [StudySession]
    ) -> [UUID: ProgressEvidence] {
        let assessmentsBySubject = Dictionary(grouping: assessments) {
            SubjectLevelKey(name: $0.subjectName, level: $0.courseLevel)
        }
        let mappingsBySubject = Dictionary(grouping: mappings) {
            SubjectLevelKey(name: $0.subjectName, level: $0.courseLevel)
        }
        let reportsBySubject = Dictionary(grouping: reports) {
            SubjectLevelKey(name: $0.subjectName, level: $0.courseLevel)
        }
        let sessionsByName = Dictionary(grouping: workSessions) { $0.subjectName.lowercased() }

        var result: [UUID: ProgressEvidence] = [:]
        result.reserveCapacity(subjects.count)
        for subject in subjects {
            let key = SubjectLevelKey(name: subject.name, level: subject.level)
            result[subject.id] = score(
                subjectName: subject.name,
                courseLevel: subject.level,
                cards: subject.cards,
                assessments: assessmentsBySubject[key] ?? [],
                mappings: mappingsBySubject[key] ?? [],
                reports: reportsBySubject[key] ?? [],
                workSessions: sessionsByName[subject.name.lowercased()] ?? []
            )
        }
        return result
    }

    /// The one subject mastery value: what Subjects, Dashboard and rank all show.
    static func masteryBySubject(subjects: [Subject], context: ModelContext) -> [UUID: Double] {
        scoreBySubject(
            subjects: subjects,
            assessments: (try? context.fetch(FetchDescriptor<AcademicAssessment>())) ?? [],
            mappings: (try? context.fetch(FetchDescriptor<AcademicAssessmentMapping>())) ?? [],
            reports: (try? context.fetch(FetchDescriptor<AcademicReportSnapshot>())) ?? [],
            workSessions: (try? context.fetch(FetchDescriptor<StudySession>())) ?? []
        ).mapValues { $0.blendedMastery ?? 0 }
    }

    static func score(
        subjectName: String,
        courseLevel: String,
        topicName: String? = nil,
        subtopicName: String? = nil,
        cards: [StudyCard],
        assessments: [AcademicAssessment],
        mappings: [AcademicAssessmentMapping],
        reports: [AcademicReportSnapshot] = [],
        workSessions: [StudySession] = [],
        now: Date = Date()
    ) -> ProgressEvidence {
        let scopedCards = cards.filter { card in
            guard let topicName else { return true }
            guard card.topicName.caseInsensitiveCompare(topicName) == .orderedSame else { return false }
            guard let subtopicName, !subtopicName.isEmpty else { return true }
            return card.subtopic.caseInsensitiveCompare(subtopicName) == .orderedSame
        }
        // Newly seeded novice cards should populate the review queue but must
        // not turn a real report grade into 0% before a first review. A card
        // explicitly marked proficient/mastered is valid imported evidence
        // even when an older store lacks its review-log counters.
        let reviewedCards = scopedCards.filter {
            $0.totalReviewCount > 0 || $0.proficiency != .novice
        }
        // Neglect fades recall. Imported cards with no review date stay at face value.
        let recallFreshness = reviewedCards.compactMap(\.lastReviewedDate).max().map {
            MasterySignals.freshness(lastReviewDate: $0, now: now)
        } ?? 1
        let recall = reviewedCards.isEmpty
            ? nil
            : ProficiencyTracker.masteryPercentage(for: reviewedCards) * recallFreshness
        let coverage = scopedCards.isEmpty ? 0 : Double(reviewedCards.count) / Double(scopedCards.count)
        let dueCount = scopedCards.filter(\.isDue).count

        // Duplicate ids must not trap; keep the first record of each id instead.
        let assessmentIndex = Dictionary(
            assessments.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let approvedMappings = mappings.filter {
            $0.status == .approved &&
            $0.subjectName.caseInsensitiveCompare(subjectName) == .orderedSame &&
            $0.courseLevel.caseInsensitiveCompare(courseLevel) == .orderedSame
        }
        let scopedAssessmentIDs: Set<UUID>
        if topicName == nil {
            scopedAssessmentIDs = Set(assessments.filter {
                $0.subjectName.caseInsensitiveCompare(subjectName) == .orderedSame &&
                $0.courseLevel.caseInsensitiveCompare(courseLevel) == .orderedSame
            }.map(\.id))
        } else {
            scopedAssessmentIDs = Set(approvedMappings.filter { mapping in
                mapping.topicName.caseInsensitiveCompare(topicName ?? "") == .orderedSame &&
                    mapping.subtopicName.caseInsensitiveCompare(subtopicName ?? "") == .orderedSame
            }.map(\.assessmentID))
        }

        let scopedAssessments = scopedAssessmentIDs.compactMap { assessmentIndex[$0] }.filter(\.isScored)
        let scopedReports = topicName == nil ? reports.filter {
            $0.subjectName.caseInsensitiveCompare(subjectName) == .orderedSame &&
                $0.courseLevel.caseInsensitiveCompare(courseLevel) == .orderedSame
        } : []
        let reportScores = scopedReports.compactMap(\.normalizedGrade)
        let evidence: Double?
        if scopedAssessments.isEmpty && reportScores.isEmpty {
            evidence = nil
        } else {
            let values = scopedAssessments.compactMap(\.normalizedScore) + reportScores
            evidence = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        let scopedWorkSessions = workSessions.filter { session in
            guard session.subjectName.caseInsensitiveCompare(subjectName) == .orderedSame else { return false }
            guard let topicName else { return true }
            guard session.selectedTopicNames.contains(where: {
                $0.caseInsensitiveCompare(topicName) == .orderedSame
            }) else { return false }
            guard let subtopicName, !subtopicName.isEmpty else { return true }
            let subtopics = StudyScope.parseList(session.subtopicsCovered ?? "")
            return subtopics.isEmpty || StudyScope.list(subtopics, containsSubtopic: subtopicName)
        }
        let sessionSignals = sessionSignals(
            for: scopedWorkSessions,
            topicName: topicName,
            subtopicName: subtopicName
        )
        // A few strong cards must not stand in for a whole unreviewed deck. With
        // a real grade, unreviewed cards shift weight toward that grade; without
        // one, they count against recall directly.
        let recallSignal: (value: Double?, weight: Double) = evidence == nil
            ? (recall.map { $0 * coverage }, 0.45)
            : (recall, 0.45 * coverage)
        // Time tops out at 0.35, so averaging it with real results would make
        // extra study lower mastery. It joins the average only when nothing
        // better exists; otherwise it closes part of the remaining gap below.
        let hasResults = recall != nil || evidence != nil
        let timeSignal = hasResults ? nil : sessionSignals.time
        let weightedSignals: [(value: Double?, weight: Double)] = [
            recallSignal,
            (evidence, 0.25),
            (sessionSignals.checkIn, 0.20),
            (timeSignal, 0.10)
        ]
        let available = weightedSignals.compactMap { signal -> (Double, Double)? in
            guard let value = signal.value else { return nil }
            return (value, signal.weight)
        }
        let availableWeight = available.reduce(0) { $0 + $1.1 }
        var blended: Double? = availableWeight > 0
            ? available.reduce(0) { $0 + $1.0 * $1.1 } / availableWeight
            : nil
        if recall == nil, evidence == nil, let value = blended {
            blended = min(value, 0.65)
        }
        if hasResults, let value = blended, let time = sessionSignals.time {
            blended = value + (1 - value) * 0.10 * (time / 0.35)
        }
        let lastDate = (scopedAssessments.compactMap(\.assessmentDate) + scopedReports.compactMap(\.reportDate)).max()

        return ProgressEvidence(
            recallMastery: recall,
            assessmentEvidence: evidence,
            workMastery: sessionSignals.combined,
            blendedMastery: blended,
            scoredAssessmentCount: scopedAssessments.count + reportScores.count,
            approvedMappingCount: topicName == nil ? approvedMappings.count : approvedMappings.filter {
                $0.topicName.caseInsensitiveCompare(topicName ?? "") == .orderedSame &&
                    $0.subtopicName.caseInsensitiveCompare(subtopicName ?? "") == .orderedSame
            }.count,
            completedWorkSessionCount: scopedWorkSessions.count,
            completedWorkMinutes: Int(scopedWorkSessions.reduce(0) { $0 + max(0, $1.duration) } / 60),
            dueCardCount: dueCount,
            lastAssessmentDate: lastDate
        )
    }

    private static func sessionSignals(
        for sessions: [StudySession],
        topicName: String?,
        subtopicName: String?
    ) -> (checkIn: Double?, time: Double?, combined: Double?) {
        guard !sessions.isEmpty else { return (nil, nil, nil) }
        let scopedEvidence = sessions.flatMap(\.subunitEvidence).filter { entry in
            if let topicName,
               entry.topicName.caseInsensitiveCompare(topicName) != .orderedSame {
                return false
            }
            if let subtopicName, !subtopicName.isEmpty,
               entry.subtopicName.caseInsensitiveCompare(subtopicName) != .orderedSame {
                return false
            }
            return true
        }
        let checkIn: Double?
        if scopedEvidence.isEmpty {
            checkIn = nil
        } else {
            checkIn = scopedEvidence.reduce(0) { $0 + $1.normalizedConfidence } / Double(scopedEvidence.count)
        }
        let evidenceMinutes = scopedEvidence.reduce(0) { $0 + max(0, $1.minutes) }
        let legacyMinutes = sessions
            .filter { $0.subunitEvidence.isEmpty }
            .reduce(0.0) { $0 + max(0, $1.duration) / 60 }
        let totalMinutes = evidenceMinutes + legacyMinutes
        let time = totalMinutes > 0 ? min(0.35, totalMinutes / 120 * 0.35) : nil
        let combined: Double?
        switch (checkIn, time) {
        case let (checkIn?, time?):
            combined = min(0.65, 0.67 * checkIn + 0.33 * time)
        case let (checkIn?, nil):
            combined = min(checkIn, 0.65)
        case let (nil, time?):
            combined = time
        case (nil, nil):
            combined = nil
        }
        return (checkIn, time, combined)
    }
}
