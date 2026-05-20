import Testing
@testable import IBVault

@Suite("IBVault App Command Tests")
struct IBVaultAppCommandTests {
    @Test("Navigation commands map to expected tabs")
    func navigationCommandsMapToTabs() {
        let expectedTabs: [IBVaultAppCommand: NavigationTab] = [
            .showDashboard: .dashboard,
            .showSubjects: .subjects,
            .showStudySessions: .studySessions,
            .showReview: .review,
            .showARIA: .aria,
            .showAnalytics: .analytics,
            .showRecommendations: .recommendations,
            .showPredictions: .predictions,
            .showProfile: .profile,
            .showSettings: .settings
        ]

        for (command, tab) in expectedTabs {
            #expect(command.targetTab == tab)
        }

        #expect(IBVaultAppCommand.refreshReviewQueue.targetTab == nil)
    }

    @Test("Notification payload round trips through raw command value")
    func notificationPayloadRoundTrip() {
        let payload = IBVaultAppCommand.showAnalytics.notificationPayload

        #expect(IBVaultAppCommand.fromNotificationPayload(payload) == .showAnalytics)
        #expect(IBVaultAppCommand.fromNotificationPayload("unknown") == nil)
        #expect(IBVaultAppCommand.fromNotificationPayload(nil) == nil)
    }
}
