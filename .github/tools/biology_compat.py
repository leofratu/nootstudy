from pathlib import Path


def edit(path, old, new, count=1):
    p = Path(path)
    text = p.read_text()
    assert text.count(old) == count, (path, text.count(old), old[:80])
    p.write_text(text.replace(old, new))


edit('IBVault/Services/BiologyCatalog.swift', '    static func themeName(_ code: String) -> String {', '''    /// Resolve exact official codes/titles and narrowly equivalent old labels.
    /// Broad retired groups such as Genetics are deliberately not mapped to one
    /// new topic: doing so could assign mastery to material never assessed.
    static func topic(named name: String, at level: IBCourseLevel) -> BiologyTopic? {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let aliases = ["cells and cell structure": "a2.2"]
        let resolved = aliases[query] ?? query
        return topics(at: level).first {
            $0.code.lowercased() == resolved || $0.title.lowercased() == resolved || $0.name.lowercased() == resolved
        }
    }

    static func topic(reference: String) -> BiologyTopic? {
        let code = reference.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
        let prefix = code.split(separator: ".").prefix(2).joined(separator: ".")
        return topics.first { $0.code.caseInsensitiveCompare(prefix) == .orderedSame }
    }

    static func themeName(_ code: String) -> String {''')
edit('IBVault/Services/StudyLibraryService.swift', '        return SyllabusSeeder.unitName(for: subject.name, level: subject.level, topicName: card.topicName) ?? ""', '''        if subject.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "biology" {
            let topic = card.syllabusReference.flatMap { BiologyCatalog.topic(reference: $0) }
                ?? BiologyCatalog.topic(named: card.topicName, at: subject.courseLevel)
            if let topic { return "\\(topic.theme). \\(BiologyCatalog.themeName(topic.theme))" }
        }
        return SyllabusSeeder.unitName(for: subject.name, level: subject.level, topicName: card.topicName) ?? ""''')
edit('IBVault/Services/ARIAService.swift', '''        let valid = SyllabusSeeder.curriculum(for: subjectName, level: subjectLevel).flatMap { $0.topics.map(\\.name) }
        return canonicalCurriculumMatches(requested, validValues: valid)''', '''        let valid = SyllabusSeeder.curriculum(for: subjectName, level: subjectLevel).flatMap { $0.topics.map(\\.name) }
        let resolved = subjectName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "biology"
            ? requested.map { BiologyCatalog.topic(named: $0, at: IBCourseLevel(subjectLevel))?.name ?? $0 }
            : requested
        return canonicalCurriculumMatches(resolved, validValues: valid)''')
edit('IBVault/Engine/SubjectKnowledge.swift', '"Genetics and inheritance, including linkage and pedigree analysis"', '"D3.2 Inheritance: alleles, genotype, phenotype and inheritance probability"')
edit('IBVault/Engine/SubjectKnowledge.swift', '"Ecology: ecosystems, energy flow and sustainability"', '"C4.1 Populations and communities; C4.2 Transfers of energy and matter"')
edit('IBVault/Engine/SubjectKnowledge.swift', '"Mendelian and linked inheritance"', '"D3.2 Inheritance: alleles, genotype and phenotype"')
edit('IBVault/Engine/SubjectKnowledge.swift', '"ATP is stored in cells — it is produced on demand and used immediately"', '"ATP is a long-term energy store — cells maintain a small, continually regenerated ATP pool; lipids and carbohydrates provide longer-term stores"')
edit('IBVault/Engine/SubjectKnowledge.swift', '"For extended-response questions, plan the chain of reasoning before writing"', '"For extended-response questions, plan the chain of reasoning before writing",\n            "Use current numbered topic names and the learner\'s SL/HL level. The bundled Biology pack is partial; inspect each topic\'s remaining coverage before claiming a requirement is taught."')
# Preserve the assertions and all scenarios, while exercising the actual current
# curriculum. Separate tests retain legacy cards and ambiguous-group safeguards.
p = Path('IBVaultTests/ARIAActionToolTests.swift')
text = p.read_text()
for old, new in [('Cells and Cell Structure', 'A2.2 Cell structure'),
                 ('Prokaryotic cell structure', 'Comparing cellular organization'),
                 ('Eukaryotic cell ultrastructure', 'Magnification and resolution'),
                 ('prokaryotic cell structure', 'cellular organization'),
                 ('prokaryote and eukaryote structure', 'cellular organization and microscopy'),
                 ('Cell theory', 'Comparing cellular organization'),
                 ('Genetics', 'D3.2 Inheritance')]:
    assert old in text, old
    text = text.replace(old, new)
p.write_text(text)
p = Path('IBVaultTests/BiologyCurriculumTests.swift')
text = p.read_text()
marker = '    @Test func realResourcesExistAtEveryTopicAndLesson() throws {'
assert marker in text
text = text.replace(marker, '''    @Test func exactAndLegacyTopicResolutionDoesNotGuessAmbiguousGroups() throws {
        #expect(BiologyCatalog.topic(named: "cells and cell structure", at: .sl)?.code == "A2.2")
        #expect(BiologyCatalog.topic(named: " b4.2 ", at: .sl)?.title == "Ecological niches")
        #expect(BiologyCatalog.topic(named: "Viruses", at: .sl) == nil)
        #expect(BiologyCatalog.topic(named: "Genetics", at: .hl) == nil)
        #expect(BiologyCatalog.topic(reference: "B2.2.3")?.code == "B2.2")
        #expect(BiologyCatalog.topic(reference: "invented#key") == nil)
    }

''' + marker)
p.write_text(text)
