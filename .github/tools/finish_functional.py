from pathlib import Path
import shutil
import subprocess
import sys

helpers = Path(__file__).resolve().parent
subprocess.run([sys.executable, str(helpers / 'expand_bioenergetics.py')], check=True)
subprocess.run([sys.executable, str(helpers / 'finalize_curriculum.py')], check=True)

# Prefer the smaller signature optimization. SwiftData remains responsible for
# ordinary fresh fetching; the experimental projection/registration path is not
# part of this deliverable.
for name in ['BiologyContinuationTests.swift', 'BiologyMasteryMappingTests.swift']:
    shutil.copyfile(helpers / name, Path('IBVaultTests') / name)
p = Path('IBVaultTests/BiologyContinuationTests.swift')
s = p.read_text()
s = s.replace('#expect(!ReviewDailyLimitPolicy.currentCards(in: reader).contains', '#expect(!(try ReviewDailyLimitPolicy.currentCards(in: reader)).contains')
s = s.replace('#expect(cold.map(\\.id) == warm.map(\\.id))', '#expect(Set(cold.map(\\.id)) == Set(warm.map(\\.id)))')
s = s.replace('        card.front = "Changed prompt"\n', '''        card.front = "Changed prompt"
        try writer.save()
        let editedActual = try ReviewDailyLimitPolicy.currentCards(in: reader).map(\\.front)
        let editedNormal = try reader.fetch(FetchDescriptor<StudyCard>()).map(\\.front)
        #expect(editedActual == editedNormal)
''')
for context in ['reader', 'context']:
    s = s.replace(f'ReviewDailyLimitPolicy.currentCards(in: {context})',
                  f'ReviewDailyLimitPolicy.day(in: {context}).library.cards')
p.write_text(s)

p = Path('IBVault/Models/CurriculumNode.swift')
s = p.read_text().replace('section.map { Set([$0.title, $0.curriculumTitle]) } ?? [subtopic]',
                         'section.map { [$0.curriculumTitle, $0.title] } ?? [subtopic]')
s = s.replace('''            let recorded = matches.filter { $0.recordedProficiency != nil }.max {
                ($0.masteryUpdatedAt ?? $0.updatedAt) < ($1.masteryUpdatedAt ?? $1.updatedAt)
            }''', '''            let recorded = matches.filter { $0.recordedProficiency != nil }.max { lhs, rhs in
                let left = lhs.masteryUpdatedAt ?? lhs.updatedAt
                let right = rhs.masteryUpdatedAt ?? rhs.updatedAt
                if left != right { return left < right }
                return lhs.id.uuidString < rhs.id.uuidString
            }''')
p.write_text(s)

p = Path('docs/biology-audit.md')
s = p.read_text()
s = s.replace('Native-tested implementation: `33f4874c10fcf3144cb15046d94e217a2e6b969f`.',
              'Initial native-tested implementation: `33f4874c10fcf3144cb15046d94e217a2e6b969f`. The continuation evidence below identifies later tested changes.')
for old, new in [('| 0 | 103 |', '| 0 | 126 |'), ('| 0 | 42 |', '| 0 | 55 |'),
                 ('| 0 | 57 |', '| 0 | 74 |'), ('| 0 | 46 |', '| 0 | 65 |'),
                 ('| 0 | 145 |', '| 0 | 194 |'), ('| 0 | 88 |', '| 0 | 93 |'),
                 ('| 0 | 124 |', '| 0 | 137 |'), ('| Not mapped | 87 |', '| Not mapped | 123 |')]:
    s = s.replace(old, new)
s = s.replace('B4.2 has teaching linked to all 13 numbered understandings and C4.2 to all 22.',
              'B4.2 has teaching linked to all 13 numbered understandings, C4.2 to all 22, C1.2 to all 17 and C1.3 to all 19.')
s = s.replace('## Completed validation', '## Initial completed validation')
s = s.replace('Dedicated HL respiration/photosynthesis, human reproductive physiology, further inheritance material, named case studies, diagrams/micrographs, practical investigations and broader exam-depth assessment remain.',
              'Human reproductive physiology, further inheritance material, named case studies, diagrams/micrographs, practical investigations and broader exam-depth assessment remain. The new respiration/photosynthesis lessons now teach the HL mechanisms, but still need diagrams, more unfamiliar datasets, practical execution and independent teacher review.')
addition = '''## Continuation: bioenergetics and stable evidence

The current guide's printed pages 67–71 (PDF pages 73–77) were checked directly: C1.2 has core understandings 1–6 and additional HL understandings 7–17; C1.3 has core 1–8 and additional HL 9–19. These independent boundaries are now enforced by the audit and native tests.

C1.2 now has 12 lesson sections and 25 questions, including ATP turnover, respirometry, redox carriers, glycolysis, fermentation, the link reaction, Krebs-cycle accounting, electron transport, oxygen's terminal-acceptor role, chemiosmosis and fuel comparisons. C1.3 now has 15 sections and 30 questions, including Rf, absorption/action spectra, controlled and FACE experiments, photosystems, photolysis, cyclic/non-cyclic flow, chloroplast compartments and Calvin-cycle carbon/ATP/NADPH accounting. Every section has at least two linked questions. All numerical practice datasets are explicitly synthetic; these are original questions, not past-paper reproductions.

The continuation adds 23 sections and 49 questions to the earlier pack. It does not change the honest partial-coverage classification or invent a whole-syllabus denominator. Chromatography and respirometry remain accessible to SL; detailed yeast fermentation and HL bioenergetics are correctly gated. In particular, the existing yeast question keeps its `C1.2#w1` identity but is no longer exposed at SL.

Existing section titles and resource IDs are retained where possible. HL-prefixed curriculum labels and old plain imported-card labels now resolve to the same section. Owned-card mastery follows the stable question/lesson reference rather than an outdated display label, so moving a question to its correct section preserves its review history without crediting the wrong core lesson. Empty curriculum scaffolding cannot obscure a recorded assessment under the equivalent older label.

Duplicate signatures avoid constructing fuzzy-match sets for short answers that cannot use fuzzy matching. Structured scope keys avoid repeated UUID formatting. Scope-label normalization is memoized only within one library calculation, so subsequent edits are immediately visible. The more complex projected/registered-model fetching experiments were not included. Existing timing assertions are unchanged and remain a separate, explicitly reported limitation when a native run exceeds them.

Thirteen added regressions exercise understanding ranges, search/import gates, four-option MCQs, retained review metadata, cold/warm/pending/cross-context queue behaviour, duplicate boundaries and history preference, and old/new HL mastery mappings. Native continuation results are recorded separately in `biology-continuation-validation.md`; the initial historical run above must not be mistaken for a test of the expanded content.

'''
s = s.replace('## Remaining limitations', addition + '## Remaining limitations')
p.write_text(s)
subprocess.run([sys.executable, 'scripts/audit_biology.py', '--output', 'docs/biology-coverage.json'], check=True)
