# IB Vault — Complete Overhaul Design

Date: 2026-07-26
Status: Approved for planning

## Goal

Rebuild IB Vault's interface, progression system, and onboarding so the app feels
like a premium native macOS tool, and so its gamification is earned rather than
granted. Add curriculum-level study resources, two heatmaps, and a study planner
that shows why its plan beats a naive one.

## Approved decisions

| Question | Decision |
|---|---|
| Aesthetic | Elevated native macOS — system materials and vibrancy, high craft |
| Gamification | Mastery spine, quiet at rest, cinematic at milestones |
| Ranks | Global rank plus per-subject tracks, three tiers per rank |
| Audience | Personal app, six fixed subjects |
| Onboarding | Cinematic setup ending in a rank reveal |
| Navigation | Five destinations, account pinned to sidebar footer |
| Existing data | Fresh start, no migration path |
| Plan comparison | Optimised plan shown side by side with a naive baseline |
| Resources | Three-tier links: verified deep, provider search, user-added |

## Current state and why it needs this

The app is a sandboxed AppKit-backed SwiftUI application on SwiftData, targeting
macOS 14+. It has SM-2 spaced repetition, a Gemini-backed assistant (ARIA), grade
tracking, and analytics. Four concrete defects motivate the overhaul.

**Progression is granted, not earned.** Three separate code paths mutate rank.
`addXP()` promotes on XP thresholds. `autoUpdateFromGrades()` jumps rank directly
from grade average and is called from four sites including ARIA. `applyPreset()`
awards XP and rank for merely *targeting* a high IB score. Worst, ARIA returns an
`xpEarned` integer in its action JSON which the app awards verbatim, so the
language model chooses the score.

**Achievements can never unlock.** All 14 definitions are seeded at launch, and
nothing sets `unlocked = true` except backup restore. The Profile permanently
renders `0/14` with 14 greyed badges.

**The weekly challenge is dead.** Three fields on `UserProfile`, initialised in
`init()`, never read or written anywhere.

**Onboarding collects nothing.** Three static marketing pages. `studentName`,
`ibYear`, `targetIBScore`, and `studyIntensity` all exist on the model and are
never asked for.

## Architecture

Three layers, built in that order.

1. **Design tokens and components** — pure SwiftUI, no domain knowledge.
2. **Progression engine** — pure Swift, no SwiftUI import, fully unit-testable.
3. **Screens** — consume both.

The engine never mutates rank as a side effect of a view action. Views record
work; the engine derives state from recorded work.

## Progression engine

### Two currencies

The system separates two things the app currently conflates.

- **Mastery** is what you know. It drives ranks. It is computed from review
  history and is never granted, gifted, or set by ARIA.
- **Momentum (XP)** is what you did. It drives streaks, the daily goal, weekly
  challenges, and streak freezes. It never affects rank.

### Mastery per subject

For each subject, four signals are computed from SwiftData:

- `coverage` — fraction of the subject's cards with `repetitions >= 2`.
- `retention` — fraction of reviews in the last 90 days graded `good` or better.
  Requires a minimum sample of 20 reviews; below that it contributes at a
  neutral 0.5 rather than swinging wildly on small numbers.
- `stability` — mean of `min(interval / 21, 1.0)` across cards with
  `repetitions >= 1`.
- `freshness` — decay from days since the subject's last review. 1.0 at 0–7
  days, tapering linearly to a floor of 0.75 at 60 days and beyond.

Composed as:

```
raw     = 0.40 * coverage + 0.35 * retention + 0.25 * stability
mastery = raw * freshness          // 0.0 ... 1.0
```

Mastery is recomputed on demand and cached on a `SubjectTrack` record for
display performance. The cache is never the source of truth.

### Global rank

The headline rank is the HL-weighted mean of the six subject masteries. HL
weights 1.5, SL weights 1.0, matching the 240 versus 150 teaching hours.

```
global = Σ(mastery_s × weight_s) / Σ(weight_s)
```

This makes the rank legible: it is your average mastery, weighted the way the IB
weights it.

### The ladder

Ten ranks, each with three tiers (III → II → I), giving 30 steps. The existing
names are kept in spirit but reordered — the current ladder is scrambled
(Catalyst sits between Molecule and Cell; Nucleus follows Cell). The new ladder
is strictly increasing in physical scale:

Electron → Atom → Molecule → Crystal → Cell → Organism → Ecosystem → Planet →
Star → Supernova

Both the global rank and each of the six subject tracks use this same ladder, so
one badge vocabulary is learned once.

Thresholds are evenly spaced in steps of 0.03 rather than spanning the full
0.0–1.0 range: step ordinal is `min(29, floor(mastery / 0.03))`, so Electron III
starts at 0.00 and Supernova I is entered at 0.87. A full 1.0 composite is
effectively unreachable, since `freshness` alone caps a neglected subject at 0.75
and `stability` requires every card sitting at a 21-day interval. Topping out the
ladder must be hard but possible.

### Rank never regresses

Mastery decays through the `freshness` factor when a subject is neglected, but a
rank once reached is retained. This requires a stored high-water mark: both
`UserProfile` and each `SubjectTrack` persist the highest rank and tier ever
reached, and the displayed rank is the greater of the currently derived rank and
that mark. A track whose live mastery has fallen below its achieved rank displays
a **Fading** state with a review nudge. Taking ranks away punishes exactly the
students who most need encouragement near exams.

### XP and momentum

XP is computed by the engine from recorded work only. Sources are review quality
(the existing `SM2Engine.xpForReview`) and logged study minutes, scaled by the
profile's `studyIntensity.xpMultiplier`. XP feeds the daily goal ring, the streak,
the weekly challenge, and streak-freeze awards. It does not feed rank.

### Removals

These are deleted outright, not deprecated:

- `UserProfile.applyPreset()` — XP and rank for aspiration — and its call site at
  `SettingsView:125`. Setting the daily goal from study intensity survives as a
  separate, side-effect-free helper.
- `UserProfile.autoUpdateFromGrades()` and all four call sites
  (`SettingsView:618`, `SettingsView:865`, `ARIAService:787`, `ARIAService:2635`).
- ARIA's `xpEarned` grant at `ARIAService:1051`. The action schema keeps the
  field for backwards-compatible decoding but the value is ignored; XP for an
  ARIA-logged session is computed by the engine from the recorded minutes.

Grades remain a first-class input to the predictions feature. They stop being a
shortcut to rank.

### Achievements

An `AchievementEvaluator` runs after each session and on app foreground. Each
achievement is a rule over engine state, evaluated idempotently, so re-running
never double-unlocks. The set expands from 14 to roughly 30 across six
categories: streak, volume, mastery, subject, consistency, and special. Volume
and streak achievements become tiered (100 / 500 / 2000 cards; 7 / 30 / 100 days).

### Progression events

A single `ProgressionEvent` enum is emitted by the engine and consumed by the UI:

```
rankUp(from:to:) | tierUp(track:tier:) | achievementUnlocked(Achievement)
| streakMilestone(days:) | dailyGoalMet | weeklyChallengeComplete
```

Events queue in a `ProgressionEventCenter` observable and are presented in
priority order, so finishing a session that triggers three things shows one
coherent sequence rather than three competing overlays. This is the only place
that decides what a "big moment" looks like.

## Design system

`Design/DesignSystem.swift` and `Design/Components.swift` are replaced.

**Tokens.** Semantic colour roles resolved through `NSColor` so light mode, dark
mode, and increased-contrast work without a parallel palette: `surface`,
`surfaceRaised`, `surfaceSunken`, `separator`, `accent`, plus the six subject
accents already defined per `Subject.accentColorHex`. The current file mixes
hardcoded hex with system colours, which is why dark mode looks inconsistent.

**Elevation.** A four-step scale replaces `glassCard()`, which today applies one
identical fill and shadow everywhere and is the main reason the app reads flat.
Levels: flush, raised, floating, modal — differing in material, border, and
shadow rather than only in shadow radius.

**Type.** A named scale with rounded numerics for statistics, monospaced digits
for counters that animate, and a consistent tracking rule for the uppercase
labels used on stat cards.

**Motion.** Springs on state change, a matched-geometry transition into review
sessions, number rolls on XP and mastery, and a reduced-motion path that honours
`accessibilityReduceMotion` by swapping every spring for a cross-fade.

## Navigation

Ten sidebar destinations collapse to five, with Profile and Settings pinned to a
footer row at the sidebar bottom.

| Destination | Contains |
|---|---|
| Today | Greeting, daily goal ring, streak, due queue, weekly challenge, ARIA nudge |
| Subjects | Six subjects → unit → topic → subtopic, with resources at every level |
| Review | Session launcher, recall modes, study guide |
| ARIA | Chat and memory |
| Progress | Ranks, both heatmaps, analytics, predictions, recommendations, achievements |

Screens that are currently buried as links inside the Dashboard body — the
effectiveness view, ADHD tracker, and materials library — move into their proper
destinations: effectiveness into Progress, the ADHD tracker into Today, materials
into Subjects.

## Curriculum resources

`SyllabusSeeder` already defines a three-level tree — 24 units, 110 topics, and
roughly 600 subtopics across six subjects — and `StudyCard` carries `topicName`
and `subtopic`, so every card already knows its position.

A `ResourceCatalog` maps `(subject, unit, topic, subtopic)` to resources from
per-subject providers: BioNinja for Biology, EconNinja for Economics, Revision
Village for Mathematics AA, and equivalents for the language and business
subjects. Resources appear as a strip on every node in the drill-down and as a
tab inside review sessions.

Links come in three tiers, because hand-authoring ~600 verified deep links is not
achievable without inventing URLs that cannot be checked:

1. **Verified deep link** — used where a provider exposes a stable, checkable URL
   pattern. Populated per unit where that holds.
2. **Provider search link** — constructed from the subtopic text against the
   provider's site search. Always resolves; never 404s.
3. **User resource** — a `CustomResource` SwiftData model attached to any node,
   added by the user or proposed by ARIA on request.

Resolution falls through the tiers in order, so a node always has something.

## Heatmaps

Two, answering different questions.

**Activity heatmap** — the GitHub-style 52×7 grid that already exists in
`Views/Analytics/HeatmapView.swift`. Redesigned and promoted into Progress with
month gutters, hover tooltips showing cards and minutes, a streak overlay, and a
year selector. Answers *did I show up*.

**Mastery heatmap** — new. A grid of the curriculum itself: subjects down the
side, units across, each cell coloured by that unit's mastery, expandable to
topic and then subtopic level. Answers *where am I weak*, which the app currently
cannot show at all. Cell colour uses a sequential scale per subject accent, with
a distinct hatch pattern for units containing no reviewed cards so "unstudied"
never reads as "weak".

## Study plan optimiser

The planner generates an optimised schedule and presents it beside a naive
baseline so the benefit is quantified rather than asserted.

**Naive baseline** — what a student actually does: equal minutes per subject,
ordered by timetable, ignoring forgetting curves and exam proximity.

**Optimised plan** — allocates minutes by expected mastery gain per minute,
weighting overdue cards, weak units drawn from the mastery heatmap, HL over SL,
and days remaining to each subject's `examDate`.

**Comparison view** — both plans as parallel timelines, with three deltas called
out: minutes required, units covered, and projected retention at exam date. The
projection uses the same SM-2 interval maths the scheduler already relies on, so
the number is derived from the app's real model rather than a marketing figure.

## Onboarding

Six paced steps replacing the three static pages, collecting the personalisation
fields that already exist on `UserProfile` and are never asked for:

1. Welcome — what the app does, one screen.
2. Name → `studentName`.
3. DP1 or DP2 → `ibYear`.
4. Target IB score → `targetIBScore`. Records the goal only; grants nothing.
5. Study intensity → `studyIntensity`, which sets `dailyGoal` from
   `dailyCardSuggestion`.
6. Reminder time → `notificationHour` / `notificationMinute`.

Then an optional, skippable ARIA key step, a calibration screen, and an animated
reveal of the starting rank and six subject tracks.

**Calibration grants no mastery.** Mastery is earned from review history and a
fresh install has none, so every track legitimately starts at Electron III. What
calibration does instead is ask which units your class has already *taught*,
per subject. That flag drives three things: the mastery heatmap distinguishes
"taught but weak" from "not yet covered" rather than showing a uniformly red
grid, the planner stops scheduling material you have not been taught, and the
rank reveal can honestly say how much of your syllabus is in play. The reveal is
a floor, not a gift — it shows the ladder you are about to climb.

Every user therefore meets the progression system in the first minute.

Onboarding is re-runnable from Settings without wiping study data.

## Data model changes

Fresh start — no migration path, no legacy fields.

**New**

- `SubjectTrack` — per-subject cached mastery, achieved rank and tier (the
  high-water mark), fading flag, last computed date.
- `UnitState` — one record per `(subject, unit)` across the 24 units, carrying
  the `isTaught` flag set during onboarding calibration and editable afterwards
  from the subject drill-down. Read by the mastery heatmap and the planner.
- `CustomResource` — user or ARIA resource attached to a curriculum node.
- `WeeklyChallenge` — promoted out of the three dead `UserProfile` fields into a
  real model with a rule, target, progress, and week identifier.

**Changed**

- `UserProfile` — drops `applyPreset()`, `autoUpdateFromGrades()`, and the three
  `weeklyChallenge*` fields. `rankRaw` is replaced by an achieved rank and tier
  high-water mark; the live rank is derived from mastery each time and the
  displayed rank is the greater of the two.
- `Achievement` — gains a rule identifier and tier so the evaluator can drive it.

**Unchanged**

`StudyCard`, `Subject`, `Grade`, `ReviewSession`, `StudySession`, `StudyActivity`,
`StudyPlan`, and `ARIAMemory` keep their shape. The overhaul does not disturb the
SM-2 scheduling data.

`BackupService` is updated in step; its codable mirrors reference several of the
changed fields.

## Testing

The engine, optimiser, and catalogue are pure Swift with no SwiftUI import, so
they test in the existing Swift Testing suite:

- Mastery composition, each signal independently, and the neutral-0.5 behaviour
  below the 20-review sample floor.
- Freshness decay at 0, 7, 30, and 60+ day boundaries.
- Rank and tier thresholds across all 30 steps, including boundaries.
- HL/SL weighting of the global composite.
- Rank never regresses when mastery falls; the fading flag does set.
- Supernova I is entered at exactly 0.87 and not at 0.869.
- Untaught units are excluded from planner scheduling and render distinctly in
  the mastery heatmap.
- Achievement rules, including idempotency on repeated evaluation.
- Optimiser allocation beats the naive baseline on projected retention for a
  fixed synthetic corpus.
- Resource resolution returns a non-empty result for all 110 topics.

UI work is verified by building and running the app, not by snapshot tests.

## Milestones

Foundation first. Each milestone compiles and passes tests on its own.

1. **Design system** — tokens, elevation, type, motion, component library.
2. **Progression engine** — mastery, ranks, XP, achievements, events, plus the
   three removals. Pure Swift, fully tested.
3. **Onboarding** — six steps, calibration, rank reveal.
4. **Destinations** — the five screens rebuilt, including both heatmaps, the
   resource drill-down, and the plan comparison.
5. **Ceremony and polish** — rank-up takeover, toasts, session summary, motion
   pass, reduced-motion path.

## Out of scope

- Subject catalogue and picker. The six subjects stay fixed.
- Data migration. Fresh start was chosen.
- iOS or iPadOS. macOS 14+ only.
- Seasonal or competitive ladders, prestige, skill trees, cosmetic unlocks.
- Snapshot or UI-automation testing.

## Risks

- **Milestone 4 is large.** The five destinations plus three new features is the
  bulk of the work and may warrant splitting during planning.
- **Mastery thresholds need tuning against real data.** Even 30 steps can feel
  slow if the composite sits low. The evenly-spaced thresholds are a starting
  point to be calibrated once there is review history.
- **Verified deep-link coverage is unknown until providers are checked.** The
  search-link fallback bounds the downside to "lands on a search page".
