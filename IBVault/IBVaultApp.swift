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
                .preferredColorScheme(.light)
        }
        .modelContainer(Self.makeModelContainer())
        #if os(macOS)
        .defaultSize(width: 1100, height: 750)
        .windowResizability(.automatic)
        .windowToolbarStyle(.unified)
        .commands {
            IBVaultCommands()
        }
        #endif
    }

    private static let schema = Schema([
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
            CurriculumNode.self,
            WeeklyChallenge.self,
            AcademicImport.self,
            AcademicAssessment.self,
            AcademicAssessmentMapping.self,
            AcademicReportSnapshot.self
    ])

    private static func makeModelContainer() -> ModelContainer {
        let fileManager = FileManager.default
        let legacyURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("default.store")
        let containerURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.nootstudy.ibvault.app/Data/Library/Application Support/default.store")

        // Older local builds opened the uncontainerized store. Prefer the
        // existing app-container store when it is present so upgrades retain
        // the user's cards and study history.
        let url: URL
        if fileManager.fileExists(atPath: containerURL.path) {
            url = containerURL
        } else {
            url = legacyURL
        }

        let configuration = ModelConfiguration(
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not open Noot Study data store: \(error)")
        }
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
    @Query private var cards: [StudyCard]
    @Query private var reviewSessions: [ReviewSession]
    @Query private var studySessions: [StudySession]
    @State private var hasAttemptedAutomaticBackup = false
    @State private var hasReconciledAchievements = false
    @State private var hasRecomputedProgression = false
    @State private var hasSynchronizedCurriculum = false
    @State private var hasMigratedFSRS = false
    @State private var hasNormalizedLegacySessions = false
    @State private var hasMergedHistoricalEvidence = false
    @State private var launchError: String?

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
                } else {
                    OnboardingView()
                }
            } else {
                OnboardingView()
                    .onAppear {
                        let profile = UserProfile()
                        context.insert(profile)
                    }
            }
        }
        // Deliberately outside the branches above: an upgrading user already
        // has a profile, so anything hung off the "no profile yet" path never
        // runs for them.
        .onAppear {
            preparePersistentStateIfNeeded()
        }
        .overlay(alignment: .topLeading) {
            CalendarSyncCoordinator()
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { launchError != nil },
                set: { if !$0 { launchError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { launchError = nil }
        } message: {
            Text(launchError ?? "")
        }
    }

    private func migrateFSRSIfNeeded() {
        guard !hasMigratedFSRS else { return }
        hasMigratedFSRS = true
        FSRSScheduler.migrate(cards: cards, reviewSessions: reviewSessions)
        do {
            try context.save()
        } catch {
            launchError = "Could not update review scheduling: \(error.localizedDescription)"
        }
    }

    private func normalizeLegacySessionsIfNeeded() {
        guard !hasNormalizedLegacySessions else { return }
        hasNormalizedLegacySessions = true
        var changed = false

        for session in studySessions where session.evidenceVersion == nil {
            let matchingReviews = reviewSessions.filter { review in
                review.subjectName.caseInsensitiveCompare(session.subjectName) == .orderedSame &&
                    review.timestamp >= session.startDate.addingTimeInterval(-60) &&
                    review.timestamp <= session.endDate.addingTimeInterval(300)
            }
            if session.cardsReviewed > matchingReviews.count {
                session.cardsReviewed = matchingReviews.count
                session.correctCount = matchingReviews.filter(\.wasCorrect).count
                session.reviewedCardIDs = matchingReviews.map(\.cardID)
                changed = true
            }
            for review in matchingReviews where review.studySessionID == nil {
                review.studySessionID = session.id
                changed = true
            }
            session.evidenceVersion = 0
            changed = true
        }

        if changed {
            do {
                try context.save()
            } catch {
                launchError = "Could not update legacy study history: \(error.localizedDescription)"
            }
        }
    }

    private func synchronizeCurriculumIfNeeded() {
        guard !hasSynchronizedCurriculum else { return }
        hasSynchronizedCurriculum = true
        if !SyllabusSeeder.seedIfNeeded(context: context) {
            launchError = "The curriculum update could not be saved. Your previous data remains available."
        }
    }

    private func reconcileAchievementsIfNeeded() {
        guard !hasReconciledAchievements else { return }
        hasReconciledAchievements = true
        Achievement.reconcile(context: context)
    }

    /// Progression otherwise only recomputes when a session completes, so an
    /// existing user would open the app at Electron III with their whole review
    /// history ignored until they happened to finish another session. Events are
    /// discarded here deliberately: launch is not a moment to fire a rank-up
    /// celebration for work done days ago.
    private func recomputeProgressionIfNeeded() {
        guard !hasRecomputedProgression else { return }
        hasRecomputedProgression = true
        ProgressionService.recompute(context: context)
    }

    private func preparePersistentStateIfNeeded() {
        guard triggerAutomaticBackupIfNeeded() else { return }
        mergeHistoricalEvidenceIfNeeded()
        synchronizeCurriculumIfNeeded()
        migrateFSRSIfNeeded()
        normalizeLegacySessionsIfNeeded()
        reconcileAchievementsIfNeeded()
        recomputeProgressionIfNeeded()
    }

    private func mergeHistoricalEvidenceIfNeeded() {
        guard !hasMergedHistoricalEvidence else { return }
        hasMergedHistoricalEvidence = true
        let backupRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IBVault Backups", isDirectory: true)
        let directory = ((try? FileManager.default.contentsOfDirectory(
            at: backupRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("backup_") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .first
        guard let directory,
              FileManager.default.fileExists(atPath: directory.appendingPathComponent("backup_meta.json").path),
              !UserDefaults.standard.bool(forKey: "IBVaultHistoricalEvidenceMerged.v1") else { return }
        do {
            try BackupService.mergeHistoricalEvidence(from: directory, context: context)
            UserDefaults.standard.set(true, forKey: "IBVaultHistoricalEvidenceMerged.v1")
        } catch {
            launchError = "Could not recover historical study evidence: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func triggerAutomaticBackupIfNeeded() -> Bool {
        guard !hasAttemptedAutomaticBackup else { return launchError == nil }
        hasAttemptedAutomaticBackup = true

        do {
            try BackupService.autoBackupIfNeeded(context: context)
            return true
        } catch {
            launchError = "Automatic backup failed: \(error.localizedDescription)"
            return false
        }
    }

}

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep AppKit chrome, menus, sheets, and SwiftUI semantic controls in
        // the same light appearance as the product palette.
        NSApp.appearance = NSAppearance(named: .aqua)

        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // A restored window frame can land off-screen or be taller than the
        // visible display, which makes the top (title bar, menus) unreachable.
        // Fit and center the window once the app is up.
        DispatchQueue.main.async {
            for window in NSApp.windows where window.canBecomeMain || window.isVisible {
                self.fitWindowToScreen(window)
            }
        }
    }

    private func fitWindowToScreen(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = window.frame

        // Never let a restored frame collapse the window into an unusable strip.
        let minWidth: CGFloat = 820
        let minHeight: CGFloat = 560
        if frame.width < minWidth { frame.size.width = minWidth }
        if frame.height < minHeight { frame.size.height = minHeight }

        if frame.height > visible.height - 20 {
            frame.size.height = visible.height - 20
        }
        if frame.width > visible.width {
            frame.size.width = visible.width
        }
        // If the top is off-screen (restored above the display) or the window
        // does not meaningfully intersect the visible area, center it.
        let intersects = frame.intersects(visible)
        let topOffScreen = frame.maxY > visible.maxY + 2
        if !intersects || topOffScreen {
            frame.origin.x = visible.midX - frame.width / 2
            frame.origin.y = visible.minY + max((visible.height - frame.height) / 2, 0)
            window.setFrame(frame, display: true)
        }
    }
    
    // Allow notifications to show even when the app is focused
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .badge, .sound])
    }
}
#endif
