# Noot Study 2.0

**A native macOS workspace for flashcards, quizzes, practice exams, spaced review, and IB progress.**

Noot Study is a SwiftUI study app that keeps your library in SwiftData and connects it to the AI provider you choose through ARIA. Saved-card practice and scheduled review work without an AI connection.

[Release 2.0](https://github.com/leofratu/nootstudy/releases/tag/v2.0.0) · [Release notes](docs/releases/v2.0.0.md) · [Quick start](#quick-start) · [Build locally](#build-locally) · [Integrations](#integrations)

![The Noot Study Library, with curriculum filters and direct practice actions. The identity area is blurred.](docs/screenshots/library.jpg)

*Screenshots use synthetic study material. Identity areas are blurred before capture; no personal study records, grades, credentials, or chat history are included.*

## What's new in 2.0

| Area | Highlights |
| --- | --- |
| Workspace | Redesigned paper-and-ink interface, grouped sidebar, clearer review status, and direct practice actions. |
| Library | Search cards and tests by subject, unit, topic, subtopic, and content, then launch practice directly from a result. |
| Card Studio | Combine topics and card formats, reuse saved cards first, and edit generated drafts before saving. |
| Multiple choice | Shuffled choices, explicit answer checking, correction feedback, and end-of-set scoring. |
| Daily review | One app-wide allowance with a ceiling of 40 distinct cards and support for lower personal targets. |
| Exam practice | Save tests with curriculum metadata, reopen answers, and keep marking feedback in the Library. |
| Continuity | Reused or hidden duplicate cards preserve their original IDs, scheduling, and review history. |

## Quick start

1. [Build and run locally](#build-locally) with Xcode on a Mac running **macOS 14 or later**.
2. Open Noot Study and choose your subjects. Existing installations keep their saved library and preferences.
3. Use **Library** to practise saved material or **Card Studio** to prepare a new set.
4. Configure an AI provider under **Settings → AI & Memory** for generation, tutoring, or marking.

The 2.0 release publishes source, tags, and release notes. Builds and validation run locally; no app bundle, installer, ZIP, or DMG is attached.

## Study workflows

### Library and practice

Library search covers questions, answers, subjects, unit names, topics, subtopics, curriculum references, and saved test feedback.

- Filter by subject and unit, then select one or more topics.
- Start a multiple-choice quiz from filtered cards.
- Open a single result with **Answer question** or **Revise card**.
- Use **Show repeated cards** to inspect originals hidden by duplicate filtering.

Free Library practice does not change FSRS scheduling or consume the scheduled-review allowance. Use **Review** when you want recall ratings to update the learning schedule.

![A native multiple-choice quiz with shuffled options and a Check answer control.](docs/screenshots/multiple-choice.jpg)

Multiple-choice attempts lock the submitted answer, identify the correct choice, show the saved answer for correction, and finish with a score. **Practise again** resets the attempt and reshuffles the options.

Basic cards use answer reveal. Cloze cards conceal their deletion until reveal. The same recall component is used in free practice, scheduled review, and study-session cards.

### Card Studio

![Card Studio with several topics selected and controls for format, count, difficulty, and reuse.](docs/screenshots/card-studio.jpg)

Choose topics or subtopics across units and combine **Basic**, **Cloze**, and **Multiple Choice** formats. A batch contains **1–50 cards total**, distributed across the selected topic and format combinations.

**Reuse saved cards first** is enabled by default. If enough matching cards already exist, the set opens without a generation request. Otherwise, only the missing count is requested. Reused cards keep their IDs, scheduling, and review history.

New drafts can be edited before saving. Invalid multiple-choice options, malformed cloze blanks, and detected duplicates are rejected, while successful drafts remain available if another topic fails.

### Daily review

The review queue, subject screens, dashboard, reminders, and ARIA review actions share one daily allowance. It counts distinct cards reviewed since local midnight, respects your goal and study intensity, and never offers more than the **40-card ceiling**.

Once the allowance is used, Noot Study shows **Done for today** and separates the remaining backlog from today's work. Repeated copies are filtered from the queue without deleting their records.

### Practice exams and marking

In **Exam marker**, choose a subject, add the question and your answer, set the available marks, and optionally provide a mark scheme. **Unit & topics** can attach curriculum scope.

Feedback includes criterion scores, evidence from the answer, corrections, a stronger example answer, and suggested practice. Scores are checked against the available marks. Without a supplied mark scheme, feedback is labelled a **practice estimate** rather than an official IB grade.

Tests can be saved before or after marking and reopened under **Library → Tests** with their answers and feedback intact.

## ARIA and AI providers

ARIA uses saved study context for explanations, revision, plans, grades, and progress. Explicit requests can create or edit supported app records. Destructive changes require an explicit request.

For revision and generation, ARIA can receive existing questions and answers with their IDs. This lets it reuse an existing learning point instead of creating a paraphrased duplicate when the meaning matches. Related questions that test different calculations, contrasts, or applications remain distinct.

| Provider | Setup |
| --- | --- |
| Local Codex | Use an installed, signed-in Codex CLI. Noot Study can detect the executable or use a path you provide. |
| Google Gemini | Add a Gemini API key and select a model. |
| Junali | Add the provider key and configure its compatible endpoint and model. |

Model, reasoning effort, answer detail, and supported web-search controls are explicit in settings. The default Local Codex model ID is **gpt-5.6-sol**, with medium reasoning when no preference has been saved. Availability depends on the provider account.

Study data remains local unless an AI feature is used. Selected context is then sent to the configured provider. API keys are stored in macOS Keychain, while Local Codex uses the existing CLI sign-in.

The desktop build is **not App Sandbox enabled** because Local Codex launches a local CLI process.

## Subjects, sessions, and progress

Noot Study includes IB curriculum browsing, scoped study sessions, FSRS scheduling, proficiency tracking, grades, mastery views, achievements, and progress summaries. Sessions combine source material, retrieval practice, corrective feedback, notes, and exam transfer.

Practice feedback and academic evidence are kept separate: saved AI marking is not automatically converted into a school grade. Work completed elsewhere can be recorded as an external activity and merged into study history without double counting.

## Integrations

The [MCP connector](integrations/nootstudy-mcp/README.md) connects external tools to Noot Study's local integration bridge.

- **Local bridge:** enable it in **Settings → Integrations**. It binds to loopback, requires the app's bearer token, and exposes versioned APIs for supported study records. It is off by default.
- **MCP:** read study data and write back supported cards, reviews, sessions, plans, memories, or activities.
- **NotebookLM exchange:** export a study pack and import generated summaries or cards through the app's file workflow.

SwiftData remains the app's source of truth. Enabling an external connector does not turn the library into a cloud-sync service.

## Data and upgrades

The app keeps the bundle identifier **com.nootstudy.ibvault.app**. Upgrades prefer the existing application-container store and preserve legacy cards and history. Replacing the app bundle does not intentionally remove the study store.

Before moving to another Mac, use **Settings → Data & Backup**. Backups contain personal study data and should be kept private. If a store cannot be opened, the app preserves the original and its sidecars in a recovery folder before attempting a fresh store.

The repository and documentation exclude personal databases, backups, reports, credentials, and private course materials.

## Build locally

Development and release builds require a Mac. Version 2.0 uses **Xcode 26**, Swift 6, and XcodeGen. Swift package versions are pinned in **project.yml**.

~~~bash
git clone https://github.com/leofratu/nootstudy.git
cd nootstudy
git checkout v2.0.0
brew install xcodegen
xcodegen generate
open IBVault.xcodeproj
~~~

Select **IBVault** and run on **My Mac**. The project and module retain their historical **IBVault** name; the installed product is **Noot Study.app**.

Compile the Release configuration locally:

~~~bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild build \
  -project IBVault.xcodeproj -scheme IBVault \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath /tmp/nootstudy-build -jobs 2
~~~

The app is written to **/tmp/nootstudy-build/Build/Products/Release/Noot Study.app**. Version-tag pushes do not trigger a hosted release build; the existing hosted workflow is available only by manual dispatch.

### Run tests

~~~bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project IBVault.xcodeproj -scheme IBVault \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/nootstudy-tests \
  -jobs 2 -parallel-testing-enabled NO
~~~

Both targets treat Swift warnings as errors. Regression coverage includes generation formats, reuse, test persistence, duplicate detection, local-midnight review limits, ARIA actions, scheduling, backups, and app commands. Provider responses use fixtures and test seams, so passing tests is not a live-provider quality claim.

<details>
<summary><strong>Documentation screenshot harness</strong></summary>

Documentation previews use an opt-in test harness with an in-memory demo library. Capture the preview windows with a separate screenshot tool; Noot Study does not capture the screen or request screen-recording permission.

~~~bash
TEST_RUNNER_NOOTSTUDY_SCREENSHOT_DIR=/tmp/nootstudy-screenshots \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -project IBVault.xcodeproj -scheme IBVault \
  -destination 'platform=macOS' -jobs 2 -parallel-testing-enabled NO \
  -only-testing:IBVaultTests/ReleaseScreenshotTests
~~~

The harness writes the current window title to **/tmp/nootstudy-screenshots/current-preview.txt**. After saving each screenshot, create its completion marker (**library.png.captured**, **card-studio.png.captured**, or **multiple-choice.png.captured**) in that directory to advance. Each preview waits up to three minutes.

</details>

### Repository map

~~~text
IBVault/
  ContentView.swift       Workspace navigation
  Design/                 Shared typography, colour, and controls
  Engine/                 Scheduling, limits, mastery, progression
  Models/                 SwiftData study and profile records
  Services/               AI, library reuse, tests, backups, integrations
  Views/                  Native SwiftUI screens
IBVaultTests/              Regressions and opt-in screenshots
docs/                      Screenshots and release notes
integrations/              MCP connector
project.yml                XcodeGen source of truth
IBVault.xcodeproj/         Generated, checked-in Xcode project
~~~

Keep source membership and **project.yml** in sync with **xcodegen generate**. Do not commit study stores, material folders, credentials, DerivedData, or raw screenshots containing personal information.
