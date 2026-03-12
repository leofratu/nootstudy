import SwiftUI
import SwiftData
import UserNotifications

@main
struct IBVaultApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

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
    @State private var hasAttemptedAutomaticBackup = false

    var body: some View {
        Group {
            if let profile = profiles.first {
                if profile.onboardingCompleted {
                    ContentView()
                        .onAppear {
                            NotificationService.requestPermission()
                            triggerAutomaticBackupIfNeeded()
                        }
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

    private func triggerAutomaticBackupIfNeeded() {
        guard !hasAttemptedAutomaticBackup else { return }
        hasAttemptedAutomaticBackup = true

        do {
            try BackupService.autoBackupIfNeeded(context: context)
        } catch {
            assertionFailure("Automatic backup failed: \(error.localizedDescription)")
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

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        
        center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }
    
    // Allow notifications to show even when the app is focused
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .badge, .sound])
    }
}
#endif
