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
        ("Life", "HL")
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

        #expect(biology.flatMap(\.topics).contains { $0.name == "A2.1 Origins of cells" })
        #expect(math.flatMap(\.topics).contains { $0.name == "1.10–1.16 Additional algebra" })
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
            "Life"
        ]
        for course in courses {
            let curriculum = SyllabusSeeder.curriculum(for: course)
            #expect(!curriculum.isEmpty, "\(course) should expose curriculum")
            #expect(curriculum.flatMap(\.topics).flatMap(\.subtopics).count >= 40, "\(course) should have deep subunit coverage")

            // Startups course must not overlap the Business Management syllabus:
            // it owns startup/VC-specific units, not corporate strategy units.
            if course == "Life" {
                let unitNames = curriculum.map(\.name)
                #expect(!unitNames.contains { $0.contains("Business Organisation") })
                #expect(unitNames.count == 4)
                #expect(unitNames.contains { $0.contains("Machine Learning") })
                #expect(unitNames.contains { $0.contains("Human Behavior") })
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

    @Test("Life covers AI, behavior and founder finance without duplicating IB Business")
    func startupsFinancialToolsAreStartupSpecific() {
        let curriculum = SyllabusSeeder.curriculum(for: "Life")
        let topicNames = curriculum.flatMap(\.topics).map(\.name)
        let subtopics = curriculum.flatMap(\.topics).flatMap(\.subtopics)

        #expect(topicNames.contains("Large Language Models"))
        #expect(topicNames.contains("LLM Systems in Production"))
        #expect(topicNames.contains("Steering Conversations"))
        #expect(topicNames.contains("Fundraising and Venture Capital"))
        #expect(subtopics.contains("Cap tables and option pools"))
        #expect(subtopics.count >= 100)

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

    @Test("Biology uses the 2025 topic codes, with protein synthesis under D1.2")
    func biologyUsesOfficialRoadmap() {
        let sl = SyllabusSeeder.curriculum(for: "Biology", level: "SL")
        let hl = SyllabusSeeder.curriculum(for: "Biology", level: "HL")
        let protein = sl.flatMap(\.topics).first { $0.name == "D1.2 Protein synthesis" }
        #expect(protein?.subtopics.count == 11)
        #expect(protein?.subtopics.first?.hasPrefix("D1.2.1 ") == true)
        #expect(protein?.subtopics.last?.hasPrefix("D1.2.11 ") == true)
        #expect(protein?.subtopics.contains { $0.contains("codon table") } == true)
        #expect(SyllabusSeeder.unitName(for: "Biology", level: "SL", topicName: "D1.2 Protein synthesis") == "Theme D — Continuity and Change")
        #expect(!sl.flatMap(\.topics).contains { $0.name == "A2.1 Origins of cells" })
        #expect(!sl.flatMap(\.topics).contains { $0.name == "D2.2 Gene expression" })
        #expect(hl.flatMap(\.topics).first { $0.name == "D1.2 Protein synthesis" }?.subtopics.count == 19)
        #expect(hl.filter { $0.name.hasPrefix("Theme ") }.flatMap(\.topics).count == 40)
    }

    @Test("Maths AA SL contains all 51 numbered sections and separates HL content")
    func mathsSLHasCompleteNumberedCoverage() {
        let curriculum = SyllabusSeeder.curriculum(for: "Mathematics AA", level: "SL")
        let mainUnits = curriculum.filter { $0.name.hasPrefix("Topic ") }
        #expect(mainUnits.map { $0.topics.count } == [9, 11, 8, 12, 11])
        let topics = mainUnits.flatMap(\.topics)
        #expect(topics.contains { $0.name == "1.9 Binomial theorem" })
        #expect(topics.contains { $0.name == "4.8 Binomial distribution" })
        #expect(topics.contains { $0.name == "4.7 Discrete random variables" })
        #expect(topics.contains { $0.name == "2.1 Straight lines" })
        let slContent = topics.flatMap(\.subtopics).joined(separator: " ").lowercased()
        #expect(!slContent.contains("compound angle"))
        #expect(!slContent.contains("polynomial division"))
        #expect(!slContent.contains("hypothesis testing"))
        #expect(!slContent.contains("poisson"))
    }

    @MainActor
    @Test("Correcting a curriculum preserves cards and retired nodes with recorded mastery")
    func catalogCorrectionPreservesUserEvidence() throws {
        let container = try ModelContainer(
            for: Subject.self, StudyCard.self, CurriculumNode.self, Grade.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        context.insert(subject)
        let card = StudyCard(topicName: "Genetics", subtopic: "Gene mutations", front: "Saved question", back: "Saved answer", subject: subject)
        context.insert(card)
        let retiredNode = CurriculumNode(
            subjectName: "Biology", level: "SL", unitName: "Theme D — Continuity and Change",
            topicName: "Genetics", subtopicName: "Gene mutations", catalogVersion: "legacy",
            sourceTitle: "Old catalog", sourceURLString: "https://www.ibo.org/"
        )
        retiredNode.recordedProficiency = .proficient
        retiredNode.masteryNote = "Teacher feedback"
        context.insert(retiredNode)
        try context.save()

        #expect(SyllabusSeeder.synchronizeCurriculum(context: context))
        #expect(SyllabusSeeder.synchronizeCurriculum(context: context))

        let savedCards = try context.fetch(FetchDescriptor<StudyCard>())
        #expect(savedCards.count == 1)
        #expect(savedCards.first?.id == card.id)
        let evidence = try context.fetch(FetchDescriptor<CurriculumNode>()).first { $0.id == retiredNode.id }
        #expect(evidence?.recordedProficiency == .proficient)
        #expect(evidence?.masteryNote == "Teacher feedback")
    }

    @Test("curriculum(for:) is memoized and stable across calls")
    func curriculumLookupIsStableAcrossCalls() {
        for subject in ["Advanced Mathematics", "Fundamentals of the Universe", "Life", "Biology", "Economics"] {
            let first = Self.structure(of: SyllabusSeeder.curriculum(for: subject))
            let second = Self.structure(of: SyllabusSeeder.curriculum(for: subject))
            #expect(first == second, "\(subject) curriculum must be identical across cached lookups")

            let firstFiltered = Self.structure(of: SyllabusSeeder.curriculum(for: subject, level: "HL"))
            let secondFiltered = Self.structure(of: SyllabusSeeder.curriculum(for: subject, level: "HL"))
            #expect(firstFiltered == secondFiltered, "\(subject) level-filtered curriculum must be identical across cached lookups")
        }
    }

    @MainActor
    @Test("seedIfNeeded creates all configured subjects and a curriculum node per subtopic")
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
        #expect(subjects.count == Self.allSubjectLevels.count)
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

    @Test("Retired topics move to the current curriculum and keep their schedule")
    func retiredTopicsMigrate() throws {
        let container = try ModelContainer(
            for: Subject.self, StudyCard.self, Grade.self, CurriculumNode.self, ReviewSession.self, StudyPlan.self, StudySession.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let biology = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        context.insert(biology)
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        func card(_ topic: String, _ subtopic: String) -> StudyCard {
            let card = StudyCard(topicName: topic, subtopic: subtopic, front: "\(topic) \(subtopic)", back: "A", subject: biology)
            card.nextReviewDate = due
            context.insert(card)
            return card
        }
        let mapped = card("Genetics", "Gene mutations")
        let blank = card("Sustainability", "")
        let custom = card("Inheritance", "My own notes")
        let current = card("A1.1 Water", "Water as a solvent and an aquatic habitat")
        let review = ReviewSession(cardID: mapped.id, subjectName: "Biology", topicName: "Genetics", qualityRating: 3, sessionDuration: 1)
        context.insert(review)
        let orphanReview = ReviewSession(cardID: UUID(), subjectName: "Biology", topicName: "Genetics", qualityRating: 3, sessionDuration: 1)
        context.insert(orphanReview)
        let plan = StudyPlan(subjectName: "Biology", topicName: "Genetics, A1.1 Water", subtopicName: "Gene mutations", scheduledDate: due)
        context.insert(plan)
        let session = StudySession(
            subjectName: "Biology", topicsCovered: "Inheritance", subtopicsCovered: "Sex-linked inheritance", startDate: due, endDate: due,
            cardsReviewed: 1, correctCount: 1, xpEarned: 1,
            subunitEvidence: [.init(topicName: "Inheritance", subtopicName: "Sex-linked inheritance", minutes: 5, confidenceRating: 4, cardsReviewed: 1, correctCount: 1)]
        )
        context.insert(session)
        // Same names in another subject are that subject's own business.
        let economics = Subject(name: "Economics", level: "HL", accentColorHex: "0000FF")
        context.insert(economics)
        let other = StudyCard(topicName: "Sustainability", front: "Other", back: "A", subject: economics)
        context.insert(other)
        try context.save()

        #expect(SyllabusSeeder.seedIfNeeded(context: context))

        #expect(mapped.topicName == "D1.3 Mutation and gene editing")
        #expect(mapped.subtopic == "Gene mutations, causes and consequences")
        #expect(mapped.nextReviewDate == due)
        #expect(blank.topicName == "D4.2 Stability and change" && blank.subtopic.isEmpty)
        #expect(custom.topicName == "D3.2 Inheritance" && custom.subtopic == "My own notes")
        #expect(current.topicName == "A1.1 Water")
        #expect(other.topicName == "Sustainability")
        #expect(review.topicName == mapped.topicName)
        #expect(orphanReview.topicName == "D3.2 Inheritance")
        #expect(plan.selectedTopicNames.contains("D1.3 Mutation and gene editing"))
        #expect(plan.selectedTopicNames.contains("A1.1 Water"))
        #expect(plan.subtopicName.isEmpty)
        #expect(plan.studyScope.matches(mapped))
        #expect(session.selectedTopicNames == ["D3.2 Inheritance"])
        #expect(session.subunitEvidence.first?.subtopicName == "Codominance, sex linkage and pedigree analysis")

        // Every target exists at this subject's level.
        for moved in [mapped, blank] {
            #expect(SyllabusSeeder.unitName(for: "Biology", level: "SL", topicName: moved.topicName) != nil)
        }

        // A second launch finds nothing to change.
        let settled = plan.topicName
        #expect(SyllabusSeeder.seedIfNeeded(context: context))
        #expect(plan.topicName == settled && mapped.topicName == "D1.3 Mutation and gene editing")
    }

    @Test("Scopes match a curriculum subtopic that contains commas")
    func scopeMatchesCommaSubtopics() {
        let name = "Polarity, hydrogen bonding, cohesion and adhesion"
        let scope = StudyScope(subjectName: "Biology", unitNames: [], topicNames: ["A1.1 Water"], subtopicNames: StudyScope.parseList(name))
        func card(_ subtopic: String) -> StudyCard { StudyCard(topicName: "A1.1 Water", subtopic: subtopic, front: "Q", back: "A") }
        #expect(scope.matches(card(name)))
        #expect(!scope.matches(card("Water as a solvent and an aquatic habitat")))
        #expect(!scope.matches(card("Polarity, unrelated")))
    }
}
