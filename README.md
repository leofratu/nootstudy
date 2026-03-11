# IB Vault — Science-Backed IB Study Companion

A production-quality iOS app built with **Swift 5.9+** and **SwiftUI**, implementing spaced repetition, an AI study companion (ARIA), gamification, and IB syllabus management.

## 🏗️ Architecture

**MVVM** with a service layer. All data persisted via **SwiftData** (iOS 17+).

```
IBVault/
├── IBVaultApp.swift              # @main entry, SwiftData ModelContainer
├── ContentView.swift             # Custom tab bar navigation
├── Design/
│   ├── DesignSystem.swift        # Colors, typography, spacing, haptics
│   └── Components.swift          # Reusable UI: GlassCard, PulseOrb, etc.
├── Models/                       # 8 SwiftData @Model classes
│   ├── Subject.swift             # IB subject with card relationships
│   ├── StudyCard.swift           # SM-2 fields, proficiency tracking
│   ├── ReviewSession.swift       # Individual review outcomes
│   ├── Grade.swift               # IB 1-7 grades per component
│   ├── UserProfile.swift         # XP, streak, rank, settings
│   ├── Achievement.swift         # 14 achievement definitions
│   ├── ARIAMemory.swift          # ARIA memory + ChatMessage
│   └── StudyActivity.swift       # Daily activity for heatmap
├── Engine/
│   ├── SM2Engine.swift           # SM-2 spaced repetition algorithm
│   ├── ReviewQueueManager.swift  # Due card queue management
│   └── ProficiencyTracker.swift  # Novice → Mastered tracking
├── Services/
│   ├── GeminiService.swift       # Gemini 2.0 Flash API (streaming)
│   ├── ARIAService.swift         # Context builder, memory compaction
│   ├── KeychainService.swift     # Secure API key storage
│   ├── NotificationService.swift # Local notifications
│   └── SyllabusSeeder.swift      # Pre-seeded IB syllabus data
└── Views/                        # 10 SwiftUI view files
    ├── Onboarding/               # 3-screen onboarding flow
    ├── Dashboard/                # Home with streak, XP, queue
    ├── Subjects/                 # Grid + detail views
    ├── Review/                   # Card flip review session
    ├── Analytics/                # Heatmap, retention curves
    ├── ARIA/                     # Chat + memory manager
    ├── Profile/                  # Rank, XP, achievements
    └── Settings/                 # API key, notifications, goals
```

## 🔑 Setting Up the Gemini API Key

1. Get an API key from [Google AI Studio](https://aistudio.google.com/apikey)
2. Open the app → **Profile** → **Settings** (gear icon)
3. Under **ARIA Configuration**, paste your key and tap **Save to Keychain**
4. The key is stored securely via iOS Keychain — never leaves the device except in API calls

## 🧠 Core Features

### Spaced Retrieval Engine (SM-2)
- Cards scheduled using the SM-2 algorithm with ease factor adaptation
- Quality ratings: Again (0) / Hard (2) / Good (3) / Easy (5)
- Proficiency levels: Novice → Developing → Proficient → Mastered
- Daily review queue sorted with overdue cards first

### ARIA AI Companion
- Powered by **Gemini 2.0 Flash** via native URLSession
- Streaming responses with typewriter effect via SSE
- Context-aware: reads all app data (grades, due cards, streak, weak topics)
- Memory system with semantic categories and automatic compaction
- Generates study plans, quizzes, gap analyses, and custom flashcards

### Gamification
- XP system with rank progression: Electron → Atom → Molecule → Cell → Organism → Ecosystem → Universe
- Daily study streak with freeze mechanic (earn 1 freeze per 7-day streak)
- 14 achievements across categories (streak, recall, mastery, milestones, special)

### Pre-loaded IB Subjects
- English B HL, Russian A Literature SL, Biology SL
- Mathematics AA SL, Economics HL, Business Management HL
- Each with official syllabus topics as study cards

## 🎨 Design System
- **Dark mode first** with deep navy (#0A0F1E) background
- Electric blue (#4A9EFF) accent with glassmorphism cards
- Physics-based SwiftUI animations and haptic feedback
- Each subject has a unique accent color

## 📋 Technical Requirements
- **iOS 17+** (SwiftData requirement)
- **iPhone-first** (iPad adaptive)
- **No third-party dependencies** — Gemini via native URLSession
- Swift 5.9+, Xcode 15+

## 🚀 Getting Started

1. Open the `IBVault` folder contents in Xcode (create a new iOS App project and add all files)
2. Set deployment target to **iOS 17.0**
3. Build and run on simulator or device
4. Complete onboarding → 6 subjects auto-populated
5. Enter Gemini API key in Settings for ARIA functionality
