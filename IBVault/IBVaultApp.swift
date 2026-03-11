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
            ChatMessage.self,
            StudyActivity.self
        ])
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
        .preferredColorScheme(.light)
    }

    private func seedAchievements() {
        for def in Achievement.definitions {
            let achievement = Achievement(id: def.id, title: def.title, desc: def.desc, icon: def.icon, category: def.category)
            context.insert(achievement)
        }
        try? context.save()
    }
}
