import SwiftUI
import SwiftData

@main
struct IBVaultApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [
            Subject.self,
            StudyCard.self,
            ReviewSession.self,
            Grade.self,
            UserProfile.self,
            Achievement.self,
            ARIAMemory.self,
            ARIAChatSession.self,
            ChatMessage.self,
            StudyActivity.self,
            StudySession.self,
            StudyPlan.self
        ])
        #if os(macOS)
        .defaultSize(width: 1100, height: 750)
        .windowToolbarStyle(.unified)
        #endif
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    var body: some View {
        Group {
            if let profile = profiles.first {
                if profile.onboardingCompleted {
                    ContentView()
                } else {
                    OnboardingView()
                }
            } else {
                OnboardingView()
                    .onAppear {
                        let profile = UserProfile()
                        context.insert(profile)
                        seedAchievements()
                    }
            }
        }
    }

    private func seedAchievements() {
        for def in Achievement.definitions {
            let achievement = Achievement(id: def.id, title: def.title, desc: def.desc, icon: def.icon, category: def.category)
            context.insert(achievement)
        }
        try? context.save()
    }
}
