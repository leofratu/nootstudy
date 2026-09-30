# Biology curriculum continuation validation

Validation date: 24 September 2026.

Native evidence: https://github.com/leofratu/nootstudy/actions/runs/36007838225

Implementation commit before documentation: `574a61b76d149cee2b3876c0a0feaf1d45fae72b`.

The committed application, tests, Xcode project and audit script were compared byte-for-byte with the native-tested source artifact. Documentation and CI wiring are reported separately. The full test suite was run without excluding performance tests.

| Suite | Total | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: | ---: |
| Native functional and performance suite | 384 | 381 | 2 | 1 |

**All functional regressions passed, including the 13 continuation tests. The full native suite is not green.** The skipped test is the existing opt-in screenshot fixture, not a newly disabled regression. Failures recorded in this run:

- `PerformanceBenchmarks/benchmarkReviewQueue()`: Expectation failed: (ms → 305.116334) < (200 → 200.0): review queue should be <200ms, was 305.116334
- `ReviewQueueBulkTests/refresh2000CardsPerformance()`: Expectation failed: (ms → 183.42175) < (150 → 150.0): refresh 2000 cards should be <150ms, was 183.42175

These timing assertions also failed on unchanged main in the earlier baseline run. Their limits remain unchanged; no test was disabled, relaxed or marked as an expected failure. Runner variability and different execution order mean the measurements are not a controlled speedup claim.

Unchanged-main comparison: https://github.com/leofratu/nootstudy/actions/runs/35994816730
Isolated queue comparison, including unsuccessful experiments: https://github.com/leofratu/nootstudy/actions/runs/36005443286

The retained optimization avoids unnecessary fuzzy-signature construction and repeated scope normalization. Projected/registered-model fetch experiments were not included. Cold/warm reads, pending changes, cross-context membership, review history, SL/HL gates and mastery aliases have regression coverage.

The curriculum audit passes with 40 topic packages, 126 lesson sections, 194 questions and 123 explicit understanding references. All topic packages remain partial. Diagram coverage, some content areas, the practical programme and independent teacher review remain incomplete. Native renders do not certify VoiceOver or a complete manual keyboard/student journey.
