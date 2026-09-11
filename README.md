# Noot Study

Noot Study is a native macOS study workspace for IB students. It combines durable SwiftData persistence, FSRS spaced retrieval, grade and mastery analytics, focused study sessions, and ARIA, an AI study assistant that reasons over the learner's local context.

The app is intentionally Mac-first: it builds as a sandboxed AppKit-backed SwiftUI application, uses the macOS Keychain for the Gemini API key, exposes native menu commands, and targets macOS 14 or later.

## Current Capabilities

- Spaced retrieval queue using FSRS scheduling, a 30-card daily cap, overdue prioritization, per-subject filtering, and proficiency tracking.
- Native macOS navigation with sidebar tabs, top-menu commands, keyboard shortcuts, unified toolbar styling, and local notification support.
- ARIA assistant with streaming provider responses, bounded context construction, durable memory, conversation compaction, and app-action planning for study sessions, grades, flashcards, and progress updates.
- ARIA tool catalog that makes every saved data point malleable on explicit request: flashcards (generate/create/edit/delete), grades and predicted grades (import/add/edit/delete), mastery (set/clear on curriculum subunits or individual cards), unit taught state, subjects (create/update/delete), the user profile (target score, daily goal, intensity, notifications, name), durable memories (save/edit/delete), and study/review sessions and plans (create/reschedule/complete/cancel/delete). Destructive tools require the learner's explicit in-message confirmation.
- IB study data for subjects, topics, cards, review sessions, grades, study sessions, study plans, achievements, activity history, and user profile/rank state.
- Nine study tracks: the six IB subjects plus Advanced Mathematics, Fundamentals of the Universe, and Life. Life contains four deep units covering startup fundamentals, machine learning and LLMs, human behavior and influence, and building, selling, and funding a company.
- Evidence-informed study sessions introduce material through trusted resources before closed-note retrieval, corrective feedback, and transfer practice, with a 45-minute focus and 15-minute recovery rhythm for long blocks.
- Local-first security posture: study data stays in SwiftData, API keys are stored in Keychain, and provider requests use `URLSession`. Backups are explicit user exports, not a cloud sync service.
- Upgrade-safe persistence: the app prefers the existing `com.nootstudy.ibvault.app` store, preserves legacy flashcards, and can merge historical grades, reports, mastery evidence, and study history without replacing current cards.
- Reliable desktop workflow: study planner sheets share one presentation route, so opening a session, guide, or review does not strand the sidebar or other navigation controls.
- Card studio: flashcards can be generated as basic, cloze, or multiple-choice cards with selectable tone, cognitive skills, and difficulty, including a mode that tells the model to lean on the app's internal curriculum and duplicate-detection tools.
- Local model-context integrations: a loopback integration bridge (Settings → Integrations) exposes the learner's data over authenticated HTTP, `nootstudy-mcp` connects Codex, ChatGPT, and other MCP clients for two-way sync, and NotebookLM exchanges study packs through export/import because NotebookLM has no public API.
- Recorded-elsewhere recovery: work pushed by external tools or entered by hand lands in an external-activity queue that can be merged into study history idempotently.

## Repository Layout

```text
IBVault/
  IBVaultApp.swift              macOS app entrypoint, model container, menu commands
  ContentView.swift             root navigation and command routing
  Design/                       reusable styling and shared components
  Engine/                       FSRS, review ranking, queue management, proficiency logic
  Models/                       SwiftData models for study, profile, ARIA, and analytics data
  Services/                     Gemini, ARIA, Keychain, backup, cards, notifications, seeding
  Views/                        SwiftUI app surfaces
IBVaultTests/                   Swift Testing unit and regression tests
integrations/nootstudy-mcp/     MCP connector for Codex, ChatGPT, and other MCP clients
project.yml                     XcodeGen source of truth for the project
IBVault.xcodeproj/              checked-in generated Xcode project
```

## Integrations

Noot Study can exchange data with external AI tools while keeping the SwiftData store as the single source of truth.

- **Integration bridge** — Settings → Integrations starts a loopback-only HTTP server (`127.0.0.1`) that speaks a versioned JSON API (cards, reviews, sessions, grades, plans, memories, external activity, snapshots, NotebookLM packs). It is off by default and requires a bearer token generated and stored by the app. Recent requests are visible in the same settings screen.
- **MCP connector** — [`integrations/nootstudy-mcp`](integrations/nootstudy-mcp/README.md) is an MCP server with 20 read/write tools. Use stdio for Codex CLI and Claude, or the streamable HTTP transport with its own bearer token for ChatGPT connectors behind a tunnel. Both directions are covered: read snapshots and write back cards, reviews, sessions, plans, memories, and merged external activity.
- **NotebookLM** — no public API exists, so the app exports a NotebookLM-ready study pack (structured markdown plus card corpus) and imports generated summaries as ARIA memories and draft flashcards.
- **Unrecorded work** — work done outside the app can be pushed through the bridge or added by hand, then merged into study history without double counting.

## Requirements

- macOS 14 or later
- Xcode 15 or later
- XcodeGen installed for project regeneration
- A provider API key for ARIA (optional; the core study workflow works without one)

## Setup

1. Generate the Xcode project after changing `project.yml` or test/source membership:

   ```bash
   xcodegen generate
   ```

2. Open `IBVault.xcodeproj` in Xcode.

3. Select the `IBVault` scheme and run on `My Mac`.

4. Add an AI provider key in the app settings if you want ARIA-assisted planning and explanations. The key is saved to the macOS Keychain.

## Data And Backups

Noot Study stores its primary data locally in SwiftData. Removing the application bundle does not intentionally remove the user's study store. Use the in-app backup controls before moving machines or testing a new build. Backup files can contain private study data and should not be committed, uploaded, or shared.

When upgrading an older installation, the app keeps existing cards and merges historical evidence by record ID. If a store cannot be opened, keep the original store and its `-wal`/`-shm` sidecars together before attempting recovery.

## Test And Verification

Run the macOS test suite from the repository root:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project IBVault.xcodeproj \
  -scheme IBVault \
  -destination 'platform=macOS'
```

Both targets build with `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`, so tests and app
code must compile warning-free.

## Gemini And ARIA Notes

- `AIProviderService` and the provider adapters own transport, typed request/response encoding, model listing, generation, retry handling, and API error mapping.
- `ARIAService` owns prompt/context construction, memory retrieval, app-action execution, streaming response handling, conversation history, and compaction.
- Keep request bodies bounded. Prefer adding focused context selectors over loading entire datasets into prompts.
- Do not log API keys, generated secrets, or raw private user study data.

## Development Rules

- Preserve native macOS behavior. Do not introduce iOS-only assumptions or web-only interaction patterns.
- Keep generated Xcode project changes consistent with `project.yml`; run `xcodegen generate` after adding source or test files.
- Prefer small, behavior-preserving service and engine changes with regression tests.
- Do not commit local materials, DerivedData, user schemes, or temporary profiling outputs.

## Release Shape

The app is a local-first macOS education tool. A production release should verify:

- Clean `xcodebuild test` on macOS.
- App sandbox entitlement and network-client entitlement remain present.
- Gemini key storage succeeds in Keychain, with the documented local fallback behavior tested when Keychain is unavailable.
- ARIA works with a real Gemini key and degrades clearly when the key is missing or invalid.
- Review queue, rank progression, and menu command routing remain covered by tests.

## Releases

Releases are tagged from `main` after the macOS test suite passes. Release notes should describe user-visible changes and must never include local stores, backups, report exports, API keys, or machine-specific planning artifacts.
