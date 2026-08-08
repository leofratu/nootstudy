import Foundation

nonisolated enum ProgressEvidenceService: Sendable {
    static func score(
        subjectName: String,
        courseLevel: String,
        topicName: String? = nil,
        subtopicName: String? = nil,
        cards: [StudyCard],
        assessments: [AcademicAssessment],
        mappings: [AcademicAssessmentMapping],
        reports: [AcademicReportSnapshot] = [],
        workSessions: [StudySession] = []
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
        let recall = reviewedCards.isEmpty ? nil : ProficiencyTracker.masteryPercentage(for: reviewedCards)
        let dueCount = scopedCards.filter(\.isDue).count

        let assessmentIndex = Dictionary(uniqueKeysWithValues: assessments.map { ($0.id, $0) })
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
            return subtopics.isEmpty || subtopics.contains {
                $0.caseInsensitiveCompare(subtopicName) == .orderedSame
            }
        }
        let sessionSignals = sessionSignals(
            for: scopedWorkSessions,
            topicName: topicName,
            subtopicName: subtopicName
        )
        let weightedSignals: [(value: Double?, weight: Double)] = [
            (recall, 0.45),
            (evidence, 0.25),
            (sessionSignals.checkIn, 0.20),
            (sessionSignals.time, 0.10)
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
