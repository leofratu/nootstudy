import Foundation
import SwiftData

@Model
nonisolated final class CurriculumNode {
    var id: UUID
    var subjectName: String
    var level: String
    var unitName: String
    var topicName: String
    var subtopicName: String
    var catalogVersion: String
    var sourceTitle: String
    var sourceURLString: String
    var updatedAt: Date
    var recordedMasteryRaw: String?
    var masteryUpdatedAt: Date?
    var masterySource: String?
    var masteryNote: String?

    var recordedProficiency: ProficiencyLevel? {
        get { recordedMasteryRaw.flatMap(ProficiencyLevel.init(rawValue:)) }
        set { recordedMasteryRaw = newValue?.rawValue }
    }

    /// Retired and other-level records containing evidence remain user data.
    var hasRecordedEvidence: Bool {
        recordedMasteryRaw != nil || masteryUpdatedAt != nil || masterySource != nil || masteryNote != nil
    }

    var stableKey: String {
        Self.stableKey(
            subjectName: subjectName,
            level: level,
            unitName: unitName,
            topicName: topicName,
            subtopicName: subtopicName
        )
    }

    init(
        subjectName: String,
        level: String,
        unitName: String,
        topicName: String,
        subtopicName: String,
        catalogVersion: String,
        sourceTitle: String,
        sourceURLString: String
    ) {
        self.id = UUID()
        self.subjectName = subjectName
        self.level = level
        self.unitName = unitName
        self.topicName = topicName
        self.subtopicName = subtopicName
        self.catalogVersion = catalogVersion
        self.sourceTitle = sourceTitle
        self.sourceURLString = sourceURLString
        self.updatedAt = Date()
        self.recordedMasteryRaw = nil
        self.masteryUpdatedAt = nil
        self.masterySource = nil
        self.masteryNote = nil
    }

    static func stableKey(
        subjectName: String,
        level: String,
        unitName: String,
        topicName: String,
        subtopicName: String
    ) -> String {
        [subjectName, level, unitName, topicName, subtopicName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "|")
    }
}

nonisolated enum CurriculumProgressService: Sendable {
    static func node(
        in nodes: [CurriculumNode],
        subjectName: String,
        level: String,
        topicName: String,
        subtopicName: String
    ) -> CurriculumNode? {
        nodes.first {
            Self.normalized($0.subjectName).caseInsensitiveCompare(Self.normalized(subjectName)) == .orderedSame &&
                Self.normalized($0.level).caseInsensitiveCompare(Self.normalized(level)) == .orderedSame &&
                Self.normalized($0.topicName).caseInsensitiveCompare(Self.normalized(topicName)) == .orderedSame &&
                Self.normalized($0.subtopicName).caseInsensitiveCompare(Self.normalized(subtopicName)) == .orderedSame
        }
    }

    /// Mirrors the normalization `CurriculumNode.stableKey` applies so a node
    /// written through `setMastery` is found again on a later lookup.
    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func effectiveMastery(cards: [StudyCard], node: CurriculumNode?) -> Double {
        if let recorded = node?.recordedProficiency {
            return ProficiencyTracker.masteryValue(for: recorded)
        }
        return ProficiencyTracker.masteryPercentage(for: cards)
    }

    static func topicMastery(
        subject: Subject,
        topicName: String,
        subtopics: [String],
        nodes: [CurriculumNode]
    ) -> Double {
        guard !subtopics.isEmpty else { return 0 }
        let biology = normalized(subject.name).caseInsensitiveCompare("Biology") == .orderedSame
            ? BiologyCatalog.topic(named: topicName, at: subject.courseLevel) : nil
        let topicCards = subject.cards.filter {
            $0.topicName == topicName && BiologyStudyService.isEligible($0)
        }
        let score = subtopics.reduce(0.0) { partial, subtopic in
            let section = biology?.sections(at: subject.courseLevel).first {
                $0.title == subtopic || $0.curriculumTitle == subtopic
            }
            let names = section.map { [$0.curriculumTitle, $0.title] } ?? [subtopic]
            let cards = topicCards.filter { card in
                if let biology, let section, card.generationSource == BiologyCatalog.sourceID {
                    return BiologyStudyService.sectionKey(for: card, in: biology) == section.key
                }
                return names.contains(card.subtopic)
            }
            // Recognize old plain labels and the canonical HL-prefixed label.
            // An empty scaffold must not obscure a separately recorded result.
            let matches = names.compactMap { name in
                node(in: nodes, subjectName: subject.name, level: subject.level,
                     topicName: topicName, subtopicName: name)
            }
            let recorded = matches.filter { $0.recordedProficiency != nil }.max { lhs, rhs in
                let left = lhs.masteryUpdatedAt ?? lhs.updatedAt
                let right = rhs.masteryUpdatedAt ?? rhs.updatedAt
                if left != right { return left < right }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return partial + effectiveMastery(cards: cards, node: recorded ?? matches.first)
        }
        return score / Double(subtopics.count)
    }

    /// Whole-subject mastery that prefers recorded curriculum-node proficiency
    /// and falls back to card-derived mastery for subunits without a recorded
    /// level. This supports explicit ARIA/manual tracking; subject-facing UI
    /// uses `ProgressEvidenceService` for evidence-calibrated mastery.
    static func subjectMastery(subject: Subject, nodes: [CurriculumNode]) -> Double {
        let curriculum = SyllabusSeeder.curriculum(for: subject.name, level: subject.level)
        let topics = curriculum.flatMap(\.topics)
        let subunitCount = topics.reduce(0) { $0 + $1.subtopics.count }
        guard subunitCount > 0 else {
            return ProficiencyTracker.masteryPercentage(for: subject)
        }
        let score = topics.reduce(0.0) { partial, topic in
            partial + topicMastery(
                subject: subject,
                topicName: topic.name,
                subtopics: topic.subtopics,
                nodes: nodes
            ) * Double(topic.subtopics.count)
        }
        return score / Double(subunitCount)
    }

    static func matchingWorkSessions(
        in sessions: [StudySession],
        subjectName: String,
        topicName: String,
        subtopicName: String
    ) -> [StudySession] {
        sessions.filter { session in
            guard session.subjectName.caseInsensitiveCompare(subjectName) == .orderedSame else {
                return false
            }
            let topicMatches = session.selectedTopicNames.contains {
                $0.caseInsensitiveCompare(topicName) == .orderedSame
            }
            guard topicMatches else { return false }

            let sessionSubtopics = StudyScope.parseList(session.subtopicsCovered ?? "")
            return sessionSubtopics.isEmpty || sessionSubtopics.contains {
                $0.caseInsensitiveCompare(subtopicName) == .orderedSame
            }
        }
    }

    @MainActor
    @discardableResult
    static func setMastery(
        _ proficiency: ProficiencyLevel,
        subject: Subject,
        unitName: String,
        topicName: String,
        subtopicName: String,
        source: String,
        note: String? = nil,
        context: ModelContext
    ) throws -> CurriculumNode {
        let existing = (try? context.fetch(FetchDescriptor<CurriculumNode>())) ?? []
        let target = node(
            in: existing,
            subjectName: subject.name,
            level: subject.level,
            topicName: topicName,
            subtopicName: subtopicName
        ) ?? {
            let metadata = SyllabusSeeder.metadata(for: subject.name)
            let created = CurriculumNode(
                subjectName: subject.name,
                level: subject.level,
                unitName: unitName,
                topicName: topicName,
                subtopicName: subtopicName,
                catalogVersion: metadata.catalogVersion,
                sourceTitle: metadata.sourceTitle,
                sourceURLString: metadata.sourceURL.absoluteString
            )
            context.insert(created)
            return created
        }()

        target.recordedProficiency = proficiency
        target.masteryUpdatedAt = Date()
        target.masterySource = source
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        target.masteryNote = trimmedNote.isEmpty ? nil : trimmedNote
        target.updatedAt = Date()
        try context.save()
        return target
    }

    @MainActor
    static func clearMastery(
        subject: Subject,
        topicName: String,
        subtopicName: String,
        context: ModelContext
    ) throws {
        let existing = (try? context.fetch(FetchDescriptor<CurriculumNode>())) ?? []
        guard let target = node(
            in: existing,
            subjectName: subject.name,
            level: subject.level,
            topicName: topicName,
            subtopicName: subtopicName
        ) else { return }

        target.recordedProficiency = nil
        target.masteryUpdatedAt = nil
        target.masterySource = nil
        target.masteryNote = nil
        target.updatedAt = Date()
        try context.save()
    }
}
