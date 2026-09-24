import Foundation
import SwiftData

nonisolated enum BiologyStudyService {
    static var curriculum: [CurriculumUnit] {
        BiologyCatalog.themes.compactMap { theme in
            let topics = BiologyCatalog.topics.filter { $0.theme == theme }.map { topic in
                CurriculumTopic(
                    name: topic.name,
                    subtopics: topic.sections.map { section in
                        section.hlOnly == true ? "HL: \(section.title)" : section.title
                    },
                    levels: topic.hlOnly ? [.hl] : Set(IBCourseLevel.allCases)
                )
            }
            guard !topics.isEmpty else { return nil }
            return CurriculumUnit(name: "\(theme). \(BiologyCatalog.themeName(theme))", topics: topics)
        }
    }

    /// Do not guess a level for legacy or user-authored cards. Owned resources
    /// have stable references and explicit level metadata, so those can be gated.
    static func isEligible(_ card: StudyCard) -> Bool {
        guard card.generationSource == BiologyCatalog.sourceID else { return true }
        guard let subject = card.subject,
              subject.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "biology",
              let reference = card.syllabusReference else { return false }
        let parts = reference.split(separator: "#", maxSplits: 1).map(String.init)
        guard parts.count == 2, let topic = BiologyCatalog.topics.first(where: { $0.code == parts[0] }) else { return false }
        let level = subject.courseLevel
        if parts[1].hasPrefix("lesson:") {
            let key = String(parts[1].dropFirst("lesson:".count))
            return topic.sections(at: level).contains { $0.key == key }
        }
        return topic.questions(at: level).contains { $0.key == parts[1] }
    }

    static func explanation(for card: StudyCard) -> String? {
        guard card.generationSource == BiologyCatalog.sourceID, let reference = card.syllabusReference else { return nil }
        return BiologyCatalog.question(reference: reference)?.question.explanation
    }

    /// Add only resources the student explicitly selects. Import is idempotent
    /// and never resets an existing card's review history or schedule.
    @MainActor
    @discardableResult
    static func addToReview(topic: BiologyTopic, subject: Subject, context: ModelContext,
                            flashcards: Bool = false, questionKeys: Set<String>? = nil) throws -> Int {
        guard subject.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "biology" else {
            throw BiologyCatalog.CatalogError.invalid("Biology material cannot be imported into another subject.")
        }
        let subjectID = subject.id
        let source = BiologyCatalog.sourceID
        let existing = try context.fetch(FetchDescriptor<StudyCard>(predicate: #Predicate {
            $0.generationSource == source && $0.subject?.id == subjectID
        }))
        var references = Set(existing.compactMap(\.syllabusReference))
        var inserted: [StudyCard] = []
        let sections = topic.sections(at: subject.courseLevel)
        func insert(key: String, section: BiologySection, front: String, back: String,
                    style: CardStyle, choices: [String], skill: CardCognitiveSkill) {
            let reference = BiologyCatalog.resourceID(topic: topic.code, key: key)
            guard references.insert(reference).inserted else { return }
            let card = StudyCard(
                topicName: topic.name, subtopic: section.title, front: front, back: back,
                subject: subject, isCustom: false, isAIGenerated: true,
                generationSource: source, hint: section.pitfall, cognitiveSkill: skill,
                cardStyle: style, choices: choices, sourceTitle: BiologyCatalog.sourceName,
                sourceURLString: BiologyCatalog.sourceURL, syllabusReference: reference,
                adaptationReason: "Original AI-assisted overview; not teacher-certified complete syllabus coverage.",
                generationPromptVersion: 1
            )
            context.insert(card)
            inserted.append(card)
        }
        if flashcards {
            for section in sections {
                insert(key: "lesson:\(section.key)", section: section,
                       front: "Explain: \(section.title)", back: "\(section.body)\n\nCommon misconception: \(section.pitfall)",
                       style: .basic, choices: [], skill: .explain)
            }
        } else {
            for question in topic.questions(at: subject.courseLevel) {
                guard questionKeys?.contains(question.key) ?? true,
                      let section = sections.first(where: { $0.key == question.sectionKey }) else { continue }
                let skill: CardCognitiveSkill = question.kind == .data ? .analyze : question.kind == .mcq ? .recall : .explain
                insert(key: question.key, section: section, front: question.prompt,
                       back: question.formattedAnswer, style: question.kind == .mcq ? .multipleChoice : .basic,
                       choices: question.options, skill: skill)
            }
        }
        guard !inserted.isEmpty else { return 0 }
        do {
            try context.save()
            return inserted.count
        } catch {
            // Do not roll back unrelated edits in the shared context.
            for card in inserted { context.delete(card) }
            throw error
        }
    }
}
