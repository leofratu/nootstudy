# IBVault App Target

This directory contains the native macOS application code for IB Vault. The app is a SwiftUI + SwiftData application with a thin engine/service layer and no third-party runtime dependencies.

## App Entry Points

- `IBVaultApp.swift`: `@main` app, SwiftData model container, native macOS window settings, and top-menu commands.
- `ContentView.swift`: root sidebar navigation, menu command routing, onboarding handoff, and shared data bootstrap.
- `Views/`: feature surfaces for dashboard, subjects, study sessions, review, analytics, ARIA, profile, and settings.

## Data Model

SwiftData models live in `Models/`:

- `Subject`, `StudyCard`, and `ReviewSession` drive retrieval practice.
- `Grade`, `StudySession`, and `StudyPlan` model planning and academic progress.
- `UserProfile`, `Achievement`, and `StudyActivity` support rank, streak, goal, and activity history.
- `ARIAMemory`, `ARIAChatSession`, and `ChatMessage` store assistant memory and chat history.

Keep model changes migration-aware. Avoid renaming persisted properties casually.

## Engine Layer

- `FSRSScheduler.swift`: FSRS spaced-repetition scheduling, migration, and review outcome mutation.
- `ReviewScheduler.swift`: due-card priority scoring and queue analysis.
- `ReviewQueueManager.swift`: cached due queue snapshots and scope-aware filtering.
- `ProficiencyTracker.swift`: mastery/proficiency classification.

Engine code should stay deterministic and easy to test. Prefer pure helpers for ranking and scheduling policy changes.

## Services

- `GeminiService.swift`: typed Gemini request/response encoding, model listing, streaming generation, retries, and error mapping.
- `ARIAService.swift`: prompt assembly, context selection, stream handling, memory compaction, and app-action execution.
- `CardGeneratorService.swift`: source-grounded flashcard creation through Gemini with useful-answer validation and offline fallback cards.
- `KeychainService.swift`: macOS Keychain API-key storage with explicit fallback reporting.
- `BackupService.swift`, `NotificationService.swift`, and `SyllabusSeeder.swift`: local app support services.

Service code should bound fetches and prompt context size. Do not log API keys or full private study transcripts.

## macOS Behavior

The app is Mac-native by design:

- Target platform is macOS only.
- Window uses content minimum sizing, unified toolbar style, and native sidebar navigation.
- Top menu commands live in `IBVaultCommands`.
- Settings are exposed through the standard macOS app settings command.
- Clipboard and haptic behavior use AppKit APIs where needed.

## Adding Files

When adding Swift files:

1. Add the file under the correct source or test folder.
2. Run `xcodegen generate` from the repository root.
3. Verify `IBVault.xcodeproj/project.pbxproj` includes the new file.
4. Run the relevant tests.

## Test Coverage

The current test target covers:

- FSRS scheduling and legacy-card migration.
- Proficiency tracking.
- Review queue filtering and fallback behavior.
- Daily review-limit policy and evidence-informed study-plan sequencing.
- Life curriculum migration, four-unit coverage, and trusted learning-resource selection.
- Review ranking policy.
- Rank progression.
- ADHD medication helper logic.
- macOS app command routing.
- Gemini request body wire format.

Run the full suite:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project IBVault.xcodeproj \
  -scheme IBVault \
  -destination 'platform=macOS'
```

## Development Checklist

- Keep UI work separate from engine/service changes.
- Add focused tests for service, scheduling, ranking, or persistence behavior changes.
- Regenerate the Xcode project after file membership changes.
- Keep ARIA prompts and context selectors bounded for CPU, RAM, and token cost.
- Preserve local-first behavior: SwiftData for app data, Keychain for secrets, no hidden network calls outside Gemini/user-requested features.
