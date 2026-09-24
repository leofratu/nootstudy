# Biology curriculum and reliability audit

Reference date: 24 September 2026. App baseline: `c65af39d06b5e8bb69d5757d9097e2158933f547`. Native-tested implementation: `33f4874c10fcf3144cb15046d94e217a2e6b969f`.

## Reference and method

The current IB Biology page identifies first teaching in 2023 and first assessment in 2025. Its four themes and 40-topic roadmap were checked against the IB-authored Biology guide, including the roadmap diagram and level boundaries relevant to the new material.

- IB subject page: https://www.ibo.org/programmes/diploma-programme/curriculum/sciences/biology/
- IB-authored guide hosted by Anatolia: https://anatolia.edu.gr/images/highschool/IBDP/Biology%20Guide%202025.pdf
- Roadmap: PDF page 31, zero-based page 30.

The guide is not redistributed. The explanations, exercises, model answers and numerical datasets are original, AI-assisted material, not official IB questions or a teacher-certified course. An attempted automated guide download returned HTTP 403. No automatically extracted complete understanding-level reference index is claimed.

## Baseline findings

The code contained 22 grouped Biology headings, including additional components, rather than the official 40 numbered topics. Carbohydrates and proteins appeared under Theme A, enzymes under Theme B, and photosynthesis and respiration were combined with ecological energy flow. Classification/cladistics and gene-expression content were not consistently separated from SL material.

There were zero **bundled** Biology lessons and zero bundled Biology practice questions. Existing users may have custom or AI-generated cards; those records are preserved.

Curriculum lookup normalized its cache key but not its subject-name switch. An unsuccessful mixed-case or padded lookup could consequently affect later correctly spelled lookups. Synchronization removed out-of-catalog nodes without distinguishing recorded mastery from disposable scaffolding. Subtopic rows could show completion merely because a card or session existed. Failed review attempts could contribute to moving out of novice proficiency.

## Shared catalog and coverage

`Materials/Biology/A.json` through `D.json` hold all 40 numbered topics. `BiologyCatalog` decodes and validates them, and `BiologyStudyService.curriculum` derives the existing application's curriculum from the same resources. The independent Python reference fixture is a test oracle, not a second production navigation list.

There are 34 SL-accessible topics and 40 HL-accessible topics including the core. The wholly HL-only topics are A2.1, A2.3, A3.2, B3.3, C2.1 and D2.2. Mixed topics also gate individual sections and questions, including D1.3 gene editing, D2.3 numerical water potential and D3.3 kidney/ADH content.

Run `python3 scripts/audit_biology.py --output docs/biology-coverage.json` to reproduce the report.

| Metric | Baseline | This revision |
| --- | ---: | ---: |
| Grouped legacy headings / canonical topic packages | 22 grouped headings | 40 canonical packages |
| Bundled lesson sections | 0 | 103 |
| Derived concept flashcards | 0 | 103 |
| MCQs | 0 | 42 |
| Written questions | 0 | 57 |
| Data/application/experimental questions | 0 | 46 |
| Total practice questions | 0 | 145 |
| SL-accessible lesson sections | 0 | 88 |
| SL-accessible questions | 0 | 124 |
| Distinct explicit understanding references | Not mapped | 87 |
| Topics certified fully complete | Not established | 0 |

Every topic is explicitly **partial**. Topic presence, question counts and references do not certify complete teaching. The whole-syllabus understanding denominator and completeness percentage remain `null`.

B4.2 has teaching linked to all 13 numbered understandings and C4.2 to all 22. This still does not certify completion of every required named example, practical task or assessment demand within those points. Every lesson has associated practice and each topic exposes its remaining gaps.

## Student workflow and persistence

The Biology browser opens an offline workspace with canonical topic search, level switching, lessons, flashcards, MCQs and written/data practice. Topic selection persists by subject and level. Locally saved mistakes receive priority when free practice reopens.

Explicitly adding resources to the existing FSRS library is idempotent. Stable references preserve review history and schedules. Creating cards, reading lessons and ungraded practice do not award mastery. Written answers use marking points and explicit self-assessment rather than exact-string grading.

Level eligibility is applied before duplicate canonicalization and at review entry points, including daily allowances, explicit candidates, scheduling and due counts. Legacy/custom cards remain available rather than being assigned a guessed classification.

Recorded curriculum evidence survives catalog retirement and SL/HL switching. Duplicate rows are reconciled deterministically using recorded evidence and its most recent update. Invalid bundled content is surfaced instead of being interpreted as an empty syllabus that should remove records.

Ambiguous old topic names are not silently reassigned: several combine multiple official topics. Existing history is retained but may not automatically contribute to a newly named topic. Narrowly equivalent labels, such as Cells and Cell Structure, can resolve to their canonical topic. Existing explicit syllabus references support legacy library lookup. AI topic commands accept official names/codes, and their end-to-end fixtures now use the actual current curriculum without weakening the original assertions.

## Completed validation

Evidence: https://github.com/leofratu/nootstudy/actions/runs/35994816730

The implementation and unchanged baseline were tested with the same Xcode 26.4.1 SDK and command settings on macOS runners. Different runner instances and ordinary timing variability prevent interpreting the table as a controlled performance improvement experiment.

| Native run | Tests | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: | ---: |
| Unchanged baseline | 354 | 350 | 3 | 1 |
| Biology implementation | 371 | 368 | 2 | 1 |

**All 17 new Biology tests passed. All functional tests passed after compatibility fixes.** Two pre-existing performance thresholds still failed. No tests were disabled and no thresholds were relaxed.

| Timing assertion | Limit | Baseline | Implementation |
| --- | ---: | ---: | ---: |
| Review queue benchmark, 2,000 cards | 200 ms | 349.6 ms, fail | 273.5 ms, fail |
| Bulk queue refresh, 2,000 cards | 150 ms | 251.4 ms, fail | 205.9 ms, fail |
| Evidence scoring, 20 subjects | 600 ms | 802.6 ms, fail | 446.9 ms, pass |

Native compilation passed. Earlier runs exposed an installed Xcode app without its SDK and a Swift compiler crash on a bound-method `Binding` setter; selecting the installed 26.4 SDK and using an explicit setter closure resolved those issues.

The new tests cover roadmap/resource integrity, SL/HL boundaries, missing/malformed content, normalized lookup, import idempotence and saved history, MCQ compatibility, review gating, legacy preservation, duplicate evidence, bookmarks and safe topic resolution. Existing AI action scenarios, scheduler, proficiency and syllabus tests remain active.

The Python audit passed. It validates topic titles/codes, checked understanding boundaries, missing resources, duplicate IDs/prompts, invalid references, prerequisite cycles, commands and question structure. Independent Swift/Foundation catalog loading, Swift syntax parsing and `git diff --check` also passed. These are complementary checks, not substitutes for native compilation.

## Remaining limitations

This is a substantial expansion, not a complete independent IB revision course. Dedicated HL respiration/photosynthesis, human reproductive physiology, further inheritance material, named case studies, diagrams/micrographs, practical investigations and broader exam-depth assessment remain. Independent teacher validation is outstanding. The scientific investigation, collaborative sciences project and full practical programme are not claimed covered by the 40-topic pack.

A complete independent list of every numbered understanding has not yet been mapped. Resource counts cannot establish that missing denominator.

The two timing-test failures above remain visible in CI and need performance work. Their reproduction on unchanged main is documented rather than used to hide them.

Noot Study is currently a native macOS app. Browser/mobile-web/iOS test claims are not applicable to this target. Cross-device cloud synchronization was not added. Free-practice bookmarks use local preferences; graded review data continues to use the existing persistent store. A separate visual PR contains responsive layout work and native screenshot evidence; no complete manual mouse/keyboard student-journey or VoiceOver certification is claimed by these unit tests.
