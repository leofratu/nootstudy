# Biology curriculum and reliability audit

Reference date: 24 September 2026. App baseline: `c65af39d06b5e8bb69d5757d9097e2158933f547`.

## Reference and method

The current IB Biology page identifies first teaching in 2023 and first assessment in 2025. Its four themes and the 40-topic roadmap were checked against the IB-authored Biology guide, including the roadmap diagram and the level boundaries relevant to the new material.

- IB subject page: https://www.ibo.org/programmes/diploma-programme/curriculum/sciences/biology/
- IB-authored guide hosted by Anatolia: https://anatolia.edu.gr/images/highschool/IBDP/Biology%20Guide%202025.pdf
- Roadmap: PDF page 31, zero-based page 30.

The guide is not redistributed. Explanations, exercises, model answers and numerical datasets in this repository are original, AI-assisted material. They are not official IB questions or a teacher-certified course. An attempted automated download of the guide returned HTTP 403; the audit therefore does not claim an automatically extracted complete understanding-level reference index.

## Findings at the baseline

The code contained 22 grouped Biology headings, including additional components, rather than the official 40 numbered topics. Examples of mismatches included carbohydrates and proteins under Theme A, enzymes under Theme B, and photosynthesis and respiration combined with ecological energy flow. Classification/cladistics and gene-expression material were not consistently separated from SL content. Dedicated official topic codes were absent.

There were zero **bundled** Biology lessons and zero bundled Biology practice questions. This does not say that existing users had no content: custom cards and AI-generated study material may already exist in their databases. Those records must remain available.

Curriculum lookup normalized its cache key but not its subject-name switch. An unsuccessful mixed-case or padded lookup could consequently affect subsequent correctly spelled lookups. Synchronization removed out-of-catalog curriculum nodes without distinguishing recorded mastery from disposable scaffolding. Subtopic rows could show a completion check merely because a card or study session existed. Failed review attempts could contribute to the threshold for moving out of novice proficiency.

## Implemented source of truth

`Materials/Biology/A.json` through `D.json` hold all 40 numbered topics. `BiologyCatalog` decodes and validates them. `BiologyStudyService.curriculum` derives the existing application's curriculum from these same resources. The independent Python reference fixture is a test oracle, not a second production navigation list.

There are 34 SL-accessible topics and 40 HL-accessible topics including the core. The six wholly HL-only topics are A2.1, A2.3, A3.2, B3.3, C2.1 and D2.2. Mixed topics additionally gate individual sections and questions. D1.3 gene editing, D2.3 numerical water potential and D3.3 kidney/ADH material are examples of gated extensions.

Each topic has original teaching, common misconceptions, associated questions, prerequisites and explicit remaining limitations. Every lesson section has at least one associated practice question. MCQs have four distinct options and explanations. Written and data questions provide marking points and explanations rather than brittle exact-text grading.

## Measured content, not a completeness percentage

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
| Distinct explicit numbered-understanding references | Not mapped | 87 |
| Topics certified fully complete | Not established | 0 |

Every topic is explicitly reported as **partial**. Topic presence, resource counts and mapped references are not interchangeable with complete syllabus coverage. The whole-syllabus understanding denominator and completeness percentage remain `null`, not a fabricated 100%.

B4.2 has teaching linked to all 13 of its numbered understandings. C4.2 has teaching linked to all 22. Those references still do not establish completion of every required named example, practical task or assessment demand within the points.

## Student workflow

The Biology topic browser opens an offline study workspace with searchable canonical topics, level switching, lessons, flashcards, MCQs and written/data practice. Topic selection persists by subject and level. Mistakes persist locally and receive priority when free practice is reopened.

Students explicitly add questions or concept flashcards to the existing FSRS review library. Stable resource references make repeated imports idempotent. Imports do not reset a card's schedule or review history, and do not award mastery. Written answers are explicitly self-assessed. Reading and free practice do not change the graded review history.

Level eligibility is applied before canonicalization and at review entry points, including daily allowance filtering, explicit review candidates, the scheduler, and due-card counts. Existing custom and legacy cards are retained rather than guessed into new level classifications. A student can still find them in the card library.

## Persistence and migration

Recorded curriculum evidence survives catalog retirement and SL/HL switching. Duplicate scaffold rows are reconciled deterministically, preferring recorded evidence and its most recent update. A failed bundled-content load is surfaced and cannot be mistaken for an intentionally empty syllabus that should wipe records.

Old topic names are not automatically reassigned to numbered topics because several old headings combine multiple official topics. Existing card history is preserved, but a student's old ambiguous card may not automatically contribute to a newly named topic's mastery. Retained retired curriculum evidence is stored, not falsely redistributed among new syllabus points. Backup/export behaviour remains available.

## Validation

`BiologyCurriculumTests` covers roadmap integrity, resource presence, SL/HL boundaries, malformed and missing content, normalization, import idempotence, review persistence, MCQ compatibility, review gates, legacy-card preservation, recorded evidence and saved mistakes. Existing scheduler, proficiency and syllabus tests remain in the test suite.

The Python audit checks the independent topic roadmap, level boundaries where verified, missing resources, duplicate IDs and prompts, invalid references, prerequisite cycles, unsupported command terms and malformed questions. Swift decoding and catalog integrity were also executed independently on Linux. Swift syntax parsing passed for the changed source files. These checks do not substitute for native SwiftUI/SwiftData compilation and tests, whose actual results are attached to the pull request.

The first native CI attempt selected an Xcode 26.6 app without its SDK. CI now selects the installed Xcode 26.4 SDK and captures stderr. A separate unmodified-baseline run had failures in two conversation performance tests; no tests have been disabled to hide them.

## Remaining work and limitations

This change substantially improves coverage but does **not** satisfy complete independent revision of the entire syllabus. In particular, detailed HL respiration/photosynthesis mechanisms, human reproductive physiology, several genetics and inheritance extensions, required named case studies, diagrams/micrograph interpretation, practical investigations and broader exam-depth assessment need further material and teacher review. Each topic lists its own gaps in the app and JSON report.

A complete canonical list of all numbered understandings has not yet been independently extracted and mapped. The practical programme, scientific investigation and collaborative sciences project are not claimed covered by the 40-topic content pack. Scientific accuracy was reviewed during authoring, but independent teacher validation remains outstanding.

Noot Study is currently a native macOS app. Browser, mobile-web and iOS testing are not applicable to this target. Cross-device cloud synchronization was not added. Free-practice mistake bookmarks use local preferences; graded review data continues to use the existing persistent store.
