import Testing
@testable import IBVault

@Suite("IBVault App Command Tests")
struct IBVaultAppCommandTests {
    @Test("Navigation commands map to expected tabs")
    func navigationCommandsMapToTabs() {
        #expect(IBVaultAppCommand.showDashboard.targetTab == .dashboard)
        #expect(IBVaultAppCommand.showReview.targetTab == .review)
        #expect(IBVaultAppCommand.showSettings.targetTab == .settings)
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
