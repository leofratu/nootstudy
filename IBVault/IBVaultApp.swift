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
            StudyPlan.self,
            SubjectTrack.self,
            UnitState.self,
            WeeklyChallenge.self
        ], isAutosaveEnabled: true, isUndoEnabled: false)
        #if os(macOS)
        .defaultSize(width: 1100, height: 750)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            IBVaultCommands()
        }
        #endif
    }
}

#if os(macOS)
enum IBVaultAppCommand: String, CaseIterable, Sendable {
    case showDashboard
    case showSubjects
    case showStudySessions
    case showReview
    case showARIA
    case showAnalytics
    case showRecommendations
    case showPredictions
    case showProfile
    case showSettings
    case refreshReviewQueue

    var targetTab: NavigationTab? {
        switch self {
        case .showDashboard: return .dashboard
        case .showSubjects: return .subjects
        case .showStudySessions: return .studySessions
        case .showReview: return .review
        case .showARIA: return .aria
        case .showAnalytics: return .analytics
        case .showRecommendations: return .recommendations
        case .showPredictions: return .predictions
        case .showProfile: return .profile
        case .showSettings: return .settings
        case .refreshReviewQueue: return nil
        }
    }

    var notificationPayload: String { rawValue }

    static func fromNotificationPayload(_ payload: Any?) -> IBVaultAppCommand? {
        guard let rawValue = payload as? String else { return nil }
        return IBVaultAppCommand(rawValue: rawValue)
    }
}

extension Notification.Name {
    static let ibVaultAppCommand = Notification.Name("IBVaultAppCommand")
}

struct IBVaultCommands: Commands {
    var body: some Commands {
        CommandMenu("Study") {
            Button("Dashboard") { post(.showDashboard) }
                .keyboardShortcut("1", modifiers: [.command])
            Button("Subjects") { post(.showSubjects) }
                .keyboardShortcut("2", modifiers: [.command])
            Button("Study Sessions") { post(.showStudySessions) }
                .keyboardShortcut("3", modifiers: [.command])
            Button("Review Queue") { post(.showReview) }
                .keyboardShortcut("4", modifiers: [.command])

            Divider()

            Button("Refresh Review Queue") { post(.refreshReviewQueue) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        CommandMenu("Assistant") {
            Button("ARIA") { post(.showARIA) }
                .keyboardShortcut("5", modifiers: [.command])
        }

        CommandMenu("Insights") {
            Button("Analytics") { post(.showAnalytics) }
                .keyboardShortcut("6", modifiers: [.command])
            Button("Recommendations") { post(.showRecommendations) }
                .keyboardShortcut("7", modifiers: [.command])
            Button("Predictions") { post(.showPredictions) }
                .keyboardShortcut("8", modifiers: [.command])
        }

        CommandMenu("Account") {
            Button("Profile") { post(.showProfile) }
                .keyboardShortcut("9", modifiers: [.command])
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings...") { post(.showSettings) }
                .keyboardShortcut(",", modifiers: [.command])
        }
    }

    private func post(_ command: IBVaultAppCommand) {
        NotificationCenter.default.post(
            name: .ibVaultAppCommand,
            object: command.notificationPayload
        )
    }
}
#endif


struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @State private var hasAttemptedAutomaticBackup = false

    private var orderedProfiles: [UserProfile] {
        profiles.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private var primaryProfile: UserProfile? {
        orderedProfiles.first(where: { $0.onboardingCompleted }) ?? orderedProfiles.first
    }

    var body: some View {
        Group {
            if let profile = primaryProfile {
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
