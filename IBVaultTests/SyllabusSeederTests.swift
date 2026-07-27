import Testing
@testable import IBVault

@Suite("Syllabus Seeder Tests")
struct SyllabusSeederTests {
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
}
