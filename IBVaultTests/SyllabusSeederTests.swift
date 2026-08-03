import Testing
import Foundation
import SwiftData
@testable import IBVault

@Suite("Syllabus Seeder Tests")
struct SyllabusSeederTests {

    private static let allSubjectLevels: [(name: String, level: String)] = [
        ("English B", "HL"),
        ("Russian A Literature", "SL"),
        ("Biology", "SL"),
        ("Mathematics AA", "SL"),
        ("Economics", "HL"),
        ("Business Management", "HL"),
        ("Advanced Mathematics", "HL"),
        ("Fundamentals of the Universe", "SL"),
        ("Startups & Venture Capital", "HL")
    ]

    @Test("SL curricula exclude higher-level extension topics")
    func slExcludesHigherLevelExtensions() {
        let biology = SyllabusSeeder.curriculum(for: "Biology", level: "SL")
        let math = SyllabusSeeder.curriculum(for: "Mathematics AA", level: "SL")
        let english = SyllabusSeeder.curriculum(for: "English B", level: "SL")

        #expect(!biology.contains { $0.name == "Higher Level Extension" })
        #expect(!math.contains { $0.name == "Higher Level Extension" })
        #expect(!english.flatMap(\.topics).contains { $0.name == "Higher Level Extension" })
    }

    @Test("HL curricula expose clean higher-level subunits")
    func hlIncludesHigherLevelExtensions() {
        let biology = SyllabusSeeder.curriculum(for: "Biology", level: "HL")
        let math = SyllabusSeeder.curriculum(for: "Mathematics AA", level: "HL")
        let russian = SyllabusSeeder.curriculum(for: "Russian A Literature", level: "HL")

        #expect(biology.contains { $0.name == "Higher Level Extension" })
        #expect(math.contains { $0.name == "Higher Level Extension" })
        #expect(russian.flatMap(\.topics).contains { $0.name == "Higher Level Essay" })
        #expect(!biology.flatMap(\.topics).flatMap(\.subtopics).contains { $0.hasPrefix("HL:") })
    }

    @Test("Every configured subject exposes real subunit coverage")
    func everyConfiguredSubjectHasSubunits() {
        let subjects = [
            ("English B", "HL"),
            ("Russian A Literature", "SL"),
            ("Biology", "SL"),
            ("Mathematics AA", "SL"),
            ("Economics", "HL"),
            ("Business Management", "HL")
        ]

        for (subject, level) in subjects {
            let curriculum = SyllabusSeeder.curriculum(for: subject, level: level)
            #expect(!curriculum.isEmpty)
            #expect(curriculum.flatMap(\.topics).flatMap(\.subtopics).count >= 20)
        }
    }

    @Test("Personal-development courses ship with real curricula")
    func personalDevelopmentCoursesHaveCurricula() {
        let courses = [
            "Advanced Mathematics",
            "Fundamentals of the Universe",
            "Startups & Venture Capital"
        ]
        for course in courses {
            let curriculum = SyllabusSeeder.curriculum(for: course)
            #expect(!curriculum.isEmpty, "\(course) should expose curriculum")
            #expect(curriculum.flatMap(\.topics).flatMap(\.subtopics).count >= 40, "\(course) should have deep subunit coverage")

            // Startups course must not overlap the Business Management syllabus:
            // it owns startup/VC-specific units, not corporate strategy units.
            if course == "Startups & Venture Capital" {
                let unitNames = curriculum.map(\.name)
                #expect(!unitNames.contains { $0.contains("Business Organisation") })
                #expect(unitNames.contains { $0.contains("Fundraising") })
                #expect(unitNames.contains { $0.contains("Financial Tools") })
            }
        }
    }

    @Test("Every course satisfies structural content invariants, full and level-filtered")
    func structuralInvariantsHoldForFullAndFilteredCurricula() {
        for (subject, level) in Self.allSubjectLevels {
            for curriculum in [SyllabusSeeder.curriculum(for: subject), SyllabusSeeder.curriculum(for: subject, level: level)] {
                #expect(!curriculum.isEmpty, "\(subject) must expose a non-empty curriculum")

                let unitNames = curriculum.map(\.name)
                #expect(Set(unitNames).count == unitNames.count, "\(subject) has duplicate unit names")

                for unit in curriculum {
                    let topicNames = unit.topics.map(\.name)
                    #expect(Set(topicNames).count == topicNames.count, "\(subject)/\(unit.name) has duplicate topic names")

                    for topic in unit.topics {
                        #expect(!topic.subtopics.isEmpty, "\(subject)/\(unit.name)/\(topic.name) has no subtopics")
                        let cleaned = topic.subtopics.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        #expect(cleaned.allSatisfy { !$0.isEmpty }, "\(subject)/\(unit.name)/\(topic.name) has an empty subtopic")
                        #expect(Set(cleaned).count == cleaned.count, "\(subject)/\(unit.name)/\(topic.name) has duplicate subtopics")
                    }
                }
            }
        }
    }

    @Test("Startups course uses startup-specific financial tools, not corporate ratio analysis")
    func startupsFinancialToolsAreStartupSpecific() {
        let curriculum = SyllabusSeeder.curriculum(for: "Startups & Venture Capital")
        let topicNames = curriculum.flatMap(\.topics).map(\.name)

        #expect(topicNames.contains("The Cap Table"))
        #expect(topicNames.contains("Runway and Cash Management"))
        #expect(topicNames.contains("Financial Modelling for Startups"))
        #expect(topicNames.contains("The Term Sheet"))

        // Must not inherit Business Management's corporate toolkit by name.
        #expect(!topicNames.contains { $0.localizedCaseInsensitiveContains("marketing mix") })
        #expect(!topicNames.contains { $0.localizedCaseInsensitiveContains("ratio") })
        #expect(!topicNames.contains { $0.localizedCaseInsensitiveContains("break-even") })

        // No exact topic-name reuse of any Business Management topic.
        let businessTopics = Set(SyllabusSeeder.curriculum(for: "Business Management").flatMap(\.topics).map(\.name))
        let overlap = topicNames.filter { businessTopics.contains($0) }
        #expect(overlap.isEmpty, "Startups must not reuse Business Management topic names: \(overlap)")
    }

    @Test("English B labels papers by their real IB role: Paper 1 writes, Paper 2 listens/reads")
    func englishBPaperLabelsMatchIBAssessmentModel() {
        let curriculum = SyllabusSeeder.curriculum(for: "English B", level: "HL")
        let topics = curriculum.flatMap(\.topics)

        let productive = topics.first { $0.name == "Productive Skills (Paper 1)" }
        let receptive = topics.first { $0.name == "Receptive Skills (Paper 2)" }
        #expect(productive != nil, "English B must label writing as Paper 1")
        #expect(receptive != nil, "English B must label reading/listening as Paper 2")
        #expect(productive?.subtopics.contains { $0.localizedCaseInsensitiveContains("text types") } == true)
        #expect(receptive?.subtopics.contains { $0.localizedCaseInsensitiveContains("listening") } == true)
    }

    @Test("Biology physiology coverage includes homeostasis")
    func biologyCoversHomeostasis() {
        let curriculum = SyllabusSeeder.curriculum(for: "Biology", level: "SL")
        let subtopics = curriculum.flatMap(\.topics).flatMap(\.subtopics)
        #expect(subtopics.contains { $0.localizedCaseInsensitiveContains("homeostasis") })
    }

    @Test("curriculum(for:) is memoized and stable across calls")
    func curriculumLookupIsStableAcrossCalls() {
        for subject in ["Advanced Mathematics", "Fundamentals of the Universe", "Startups & Venture Capital", "Biology", "Economics"] {
            let first = Self.structure(of: SyllabusSeeder.curriculum(for: subject))
            let second = Self.structure(of: SyllabusSeeder.curriculum(for: subject))
            #expect(first == second, "\(subject) curriculum must be identical across cached lookups")

            let firstFiltered = Self.structure(of: SyllabusSeeder.curriculum(for: subject, level: "HL"))
            let secondFiltered = Self.structure(of: SyllabusSeeder.curriculum(for: subject, level: "HL"))
            #expect(firstFiltered == secondFiltered, "\(subject) level-filtered curriculum must be identical across cached lookups")
        }
    }

    @MainActor
    @Test("seedIfNeeded creates all nine subjects and a curriculum node per subtopic")
    func seedIfNeededCreatesSubjectsAndNodes() throws {
        let container = try ModelContainer(
            for: Subject.self,
            StudyCard.self,
            CurriculumNode.self,
            Grade.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        SyllabusSeeder.seedIfNeeded(context: context)

        let subjects = try context.fetch(FetchDescriptor<Subject>())
        #expect(subjects.count == 9)
        #expect(Set(subjects.map(\.name)) == Set(Self.allSubjectLevels.map(\.name)))

        let nodes = try context.fetch(FetchDescriptor<CurriculumNode>())
        var expectedKeys = Set<String>()
        for (name, level) in Self.allSubjectLevels {
            for unit in SyllabusSeeder.curriculum(for: name, level: level) {
                for topic in unit.topics {
                    for subtopic in topic.subtopics {
                        expectedKeys.insert(CurriculumNode.stableKey(
                            subjectName: name,
                            level: level,
                            unitName: unit.name,
                            topicName: topic.name,
                            subtopicName: subtopic
                        ))
                    }
                }
            }
        }
        #expect(nodes.count == expectedKeys.count, "seeded node count must match the curriculum")
        #expect(Set(nodes.map(\.stableKey)) == expectedKeys, "seeded nodes must mirror the curriculum exactly")
    }

    private static func structure(of curriculum: [CurriculumUnit]) -> [String] {
        curriculum.flatMap { unit in
            [unit.name] + unit.topics.flatMap { topic in [topic.name] + topic.subtopics }
        }
    }
}
