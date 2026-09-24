from pathlib import Path
import json
import subprocess

# Existing titles participate in persisted curriculum-node keys. Keep those
# stable while expanding their teaching; resource keys remain unchanged too.
path = Path('IBVault/Materials/Biology/C.json')
original = json.loads(subprocess.check_output(['git', 'show', 'HEAD:IBVault/Materials/Biology/C.json'], text=True))
old_titles = {(t['code'], s['key']): s['title'] for t in original for s in t['sections']}
topics = json.loads(path.read_text())
for topic in topics:
    for section in topic['sections']:
        if (topic['code'], section['key']) in old_titles:
            section['title'] = old_titles[(topic['code'], section['key'])]
path.write_text(json.dumps(topics, ensure_ascii=False, indent=2) + '\n')

path = Path('IBVault/Services/BiologyCatalog.swift')
text = path.read_text()
old = '''    let syllabusPoints: [String]?
    let hlOnly: Bool?
    var id: String { key }
}'''
new = '''    let syllabusPoints: [String]?
    let hlOnly: Bool?
    var id: String { key }
    /// The existing syllabus filter and recorded curriculum nodes use this
    /// prefix. Keep a single definition for navigation and newly imported cards.
    var curriculumTitle: String { hlOnly == true ? "HL: \\(title)" : title }
}'''
assert old in text
path.write_text(text.replace(old, new))

path = Path('IBVault/Services/BiologyStudyService.swift')
text = path.read_text().replace('''subtopics: topic.sections.map { section in
                        section.hlOnly == true ? "HL: \\(section.title)" : section.title
                    },''', '''subtopics: topic.sections.map(\\.curriculumTitle),''')
text = text.replace('topicName: topic.name, subtopic: section.title, front: front, back: back,',
                    'topicName: topic.name, subtopic: section.curriculumTitle, front: front, back: back,')
marker = '    static func explanation(for card: StudyCard) -> String? {'
new = '''    /// Resolve owned-card evidence by its stable reference, not the visible
    /// subtopic label saved by an earlier revision of the content pack.
    static func sectionKey(for card: StudyCard, in topic: BiologyTopic) -> String? {
        guard card.generationSource == BiologyCatalog.sourceID,
              let reference = card.syllabusReference else { return nil }
        let prefix = topic.code + "#"
        guard reference.hasPrefix(prefix) else { return nil }
        let key = String(reference.dropFirst(prefix.count))
        if key.hasPrefix("lesson:") {
            let sectionKey = String(key.dropFirst("lesson:".count))
            return topic.sections.contains { $0.key == sectionKey } ? sectionKey : nil
        }
        return topic.questions.first { $0.key == key }?.sectionKey
    }

''' + marker
assert marker in text
path.write_text(text.replace(marker, new))

path = Path('IBVault/Models/CurriculumNode.swift')
text = path.read_text()
start = text.index('        guard !subtopics.isEmpty else { return 0 }')
end = text.index('        return score / Double(subtopics.count)', start)
text = text[:start] + '''        guard !subtopics.isEmpty else { return 0 }
        let biology = normalized(subject.name).caseInsensitiveCompare("Biology") == .orderedSame
            ? BiologyCatalog.topic(named: topicName, at: subject.courseLevel) : nil
        let topicCards = subject.cards.filter {
            $0.topicName == topicName && BiologyStudyService.isEligible($0)
        }
        let score = subtopics.reduce(0.0) { partial, subtopic in
            let section = biology?.sections(at: subject.courseLevel).first {
                $0.title == subtopic || $0.curriculumTitle == subtopic
            }
            let names = section.map { Set([$0.title, $0.curriculumTitle]) } ?? [subtopic]
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
            let recorded = matches.filter { $0.recordedProficiency != nil }.max {
                ($0.masteryUpdatedAt ?? $0.updatedAt) < ($1.masteryUpdatedAt ?? $1.updatedAt)
            }
            return partial + effectiveMastery(cards: cards, node: recorded ?? matches.first)
        }
''' + text[end:]
path.write_text(text)
