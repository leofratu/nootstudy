# IB Vault

IB Vault is a native macOS study app for IB students. It combines SwiftData persistence, SM-2 spaced retrieval, grade and mastery analytics, and ARIA, a Gemini-backed study assistant that can reason over the student's local study context.

The app is intentionally Mac-first: it builds as a sandboxed AppKit-backed SwiftUI application, uses the macOS Keychain for the Gemini API key, exposes native menu commands, and targets macOS 14 or later.

## Current Capabilities

- Spaced retrieval queue using SM-2 scheduling, overdue prioritization, per-subject filtering, and proficiency tracking.
- Native macOS navigation with sidebar tabs, top-menu commands, keyboard shortcuts, unified toolbar styling, and local notification support.
- ARIA assistant with streaming Gemini responses, bounded context construction, persistent memory, conversation compaction, and app-action planning for study sessions, grades, flashcards, and progress updates.
- IB study data for subjects, topics, cards, review sessions, grades, study sessions, study plans, achievements, activity history, and user profile/rank state.
- Local-first security posture: app data stays in SwiftData, API keys are stored in Keychain, and Gemini requests are made with `URLSession`.

## Repository Layout

```text
IBVault/
  IBVaultApp.swift              macOS app entrypoint, model container, menu commands
  ContentView.swift             root navigation and command routing
  Design/                       reusable styling and shared components
  Engine/                       SM-2, review ranking, queue management, proficiency logic
  Models/                       SwiftData models for study, profile, ARIA, and analytics data
  Services/                     Gemini, ARIA, Keychain, backup, cards, notifications, seeding
  Views/                        SwiftUI app surfaces
IBVaultTests/                   Swift Testing unit and regression tests
repo_plan/                      RPG planning graph, file index, run artifacts
project.yml                     XcodeGen source of truth for the project
IBVault.xcodeproj/              checked-in generated Xcode project
```

## Requirements

- macOS 14 or later
- Xcode 15 or later
- XcodeGen installed for project regeneration
- Gemini API key from Google AI Studio for ARIA

## Setup

1. Generate the Xcode project after changing `project.yml` or test/source membership:

   ```bash
   xcodegen generate
   ```

2. Open `IBVault.xcodeproj` in Xcode.

3. Select the `IBVault` scheme and run on `My Mac`.

4. Add the Gemini API key in the app settings. The key is saved to the macOS Keychain.

## Test And Verification

Run the macOS test suite from the repository root:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project IBVault.xcodeproj \
  -scheme IBVault \
  -destination 'platform=macOS'
```

Validate RPG JSON artifacts when changing `repo_plan/`:

```bash
python3 -m json.tool repo_plan/rpg.json >/dev/null
python3 -m json.tool repo_plan/file_index.json >/dev/null
python3 -m json.tool repo_plan/runs/<run-id>/run.json >/dev/null
```

The canonical RPG helper scripts named in the agent instructions are not currently present in this checkout, so JSON validation is the available local RPG check.

## Gemini And ARIA Notes

- `GeminiService` owns the Gemini transport, typed request/response encoding, model listing, non-streaming generation, streaming generation, retry handling, and API error mapping.
- `ARIAService` owns prompt/context construction, memory retrieval, app-action execution, streaming response handling, conversation history, and compaction.
- Keep request bodies bounded. Prefer adding focused context selectors over loading entire datasets into prompts.
- Do not log API keys, generated secrets, or raw private user study data.

## Development Rules

- Preserve native macOS behavior. Do not introduce iOS-only assumptions or web-only interaction patterns.
- Keep generated Xcode project changes consistent with `project.yml`; run `xcodegen generate` after adding source or test files.
- Prefer small, behavior-preserving service and engine changes with regression tests.
- Update `repo_plan/rpg.json`, `repo_plan/file_index.json`, and a new `repo_plan/runs/<timestamp>/run.json` for non-trivial work.
- Do not commit local materials, DerivedData, user schemes, or temporary profiling outputs.

## Release Shape

The app is a local-first macOS education tool. A production release should verify:

- Clean `xcodebuild test` on macOS.
- App sandbox entitlement and network-client entitlement remain present.
- Gemini key storage succeeds in Keychain, with the documented local fallback behavior tested when Keychain is unavailable.
- ARIA works with a real Gemini key and degrades clearly when the key is missing or invalid.
- Review queue, rank progression, and menu command routing remain covered by tests.
