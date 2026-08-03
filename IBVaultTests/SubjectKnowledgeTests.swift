import Testing
import Foundation
@testable import IBVault

@Suite("Subject Knowledge Catalog")
struct SubjectKnowledgeTests {

    /// Phrases that are legitimately cross-cutting study skills or syllabus
    /// summaries rather than the name of one curriculum topic, so the soft
    /// curriculum-correspondence check below skips them.
    private static let generalClaimPhrases: Set<String> = [
        "Sketching and transforming functions",
        "Connecting ideas with clear paragraph structure"
    ]

    @Test("Every seeded subject has curated knowledge")
    func everyCurriculumSubjectHasKnowledge() {
        for subject in ["Biology", "Mathematics AA", "Economics", "Business Management", "English B", "Russian A Literature",
                        "Advanced Mathematics", "Fundamentals of the Universe", "Startups & Venture Capital"] {
            let knowledge = SubjectKnowledge.knowledge(for: subject)
            #expect(knowledge != nil, "\(subject) should have domain knowledge")
            #expect(knowledge?.keyConcepts.isEmpty == false)
            #expect(knowledge?.highYieldTopics.isEmpty == false)
            #expect(knowledge?.commonMisconceptions.isEmpty == false)
            #expect(knowledge?.examTechnique.isEmpty == false)
            #expect(knowledge?.commandTerms.isEmpty == false)
        }
    }

    @Test("Knowledge catalog covers exactly the nine seeded subjects")
    func catalogMatchesSeededSubjects() {
        let seeded = Set([
            "Biology", "Mathematics AA", "Economics", "Business Management",
            "English B", "Russian A Literature", "Advanced Mathematics",
            "Fundamentals of the Universe", "Startups & Venture Capital"
        ])
        let catalog = Set(SubjectKnowledge.all.map(\.subjectName))
        #expect(catalog == seeded, "knowledge catalog must track the seeded subject set")
    }

    @Test("Prompt block is non-empty and names the subject")
    func promptBlockIsNonEmpty() {
        let block = SubjectKnowledge.knowledge(for: "Biology")?.promptBlock ?? ""
        #expect(block.contains("Biology domain knowledge:"))
        #expect(block.contains("High-yield topics:"))
        #expect(block.contains("Command terms:"))
    }

    @Test("Matching is case-insensitive")
    func matchingIsCaseInsensitive() {
        #expect(SubjectKnowledge.knowledge(for: "biology") != nil)
        #expect(SubjectKnowledge.knowledge(for: "ECONOMICS") != nil)
        #expect(SubjectKnowledge.knowledge(for: "Philosophy") == nil)
    }

    @Test("High-yield topics reference real curriculum content or a general claim")
    func highYieldTopicsCorrespondToCurriculum() {
        for knowledge in SubjectKnowledge.all {
            let curriculumTokens = Self.curriculumTokens(for: knowledge.subjectName)
            for topic in knowledge.highYieldTopics where !Self.generalClaimPhrases.contains(topic) {
                let shared = Self.significantTokens(of: topic).intersection(curriculumTokens)
                #expect(shared.count >= 2,
                        "\(knowledge.subjectName) high-yield topic '\(topic)' does not reference curriculum content (shared tokens: \(shared))")
            }
        }
    }

    @Test("Key concepts reference real curriculum content")
    func keyConceptsCorrespondToCurriculum() {
        for knowledge in SubjectKnowledge.all {
            let curriculumTokens = Self.curriculumTokens(for: knowledge.subjectName)
            for concept in knowledge.keyConcepts {
                let shared = Self.significantTokens(of: concept).intersection(curriculumTokens)
                #expect(shared.count >= 2,
                        "\(knowledge.subjectName) key concept '\(concept)' does not reference curriculum content (shared tokens: \(shared))")
            }
        }
    }

    /// Union of significant tokens over every topic and subtopic name of a
    /// subject's curriculum, used for the soft correspondence check.
    private static func curriculumTokens(for subjectName: String) -> Set<String> {
        var tokens = Set<String>()
        for unit in SyllabusSeeder.curriculum(for: subjectName) {
            for topic in unit.topics {
                tokens.formUnion(significantTokens(of: topic.name))
                for subtopic in topic.subtopics {
                    tokens.formUnion(significantTokens(of: subtopic))
                }
            }
        }
        return tokens
    }

    private static func significantTokens(of phrase: String) -> Set<String> {
        let stopWords: Set<String> = [
            "a", "an", "the", "and", "of", "in", "on", "for", "to", "vs", "or",
            "from", "with", "by", "as", "is", "that", "are", "their", "them",
            "when", "why", "how", "what", "across", "over", "between", "into",
            "not", "e", "mc", "each", "you", "it", "be"
        ]
        let words = phrase.lowercased().split { !$0.isLetter && $0 != "'" && $0 != "’" }
        return Set(words.map(String.init).filter { !stopWords.contains($0) })
    }
}
