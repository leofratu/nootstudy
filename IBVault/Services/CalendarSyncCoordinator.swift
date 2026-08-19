import SwiftData
import SwiftUI

struct CalendarSyncCoordinator: View {
    @Query(sort: \StudyPlan.scheduledDate, order: .forward) private var plans: [StudyPlan]
    @AppStorage(CalendarSyncPreferences.isEnabledKey) private var isEnabled = false
    @AppStorage(CalendarSyncPreferences.calendarIdentifierKey) private var calendarIdentifier = ""

    private var syncFingerprint: String {
        let planValues = plans.map {
            [
                $0.id.uuidString,
                $0.subjectName,
                $0.topicName,
                $0.subtopicName,
                String($0.scheduledDate.timeIntervalSinceReferenceDate),
                String($0.scheduledEndDate.timeIntervalSinceReferenceDate),
                String($0.isCompleted)
            ].joined(separator: "|")
        }
        return ([String(isEnabled), calendarIdentifier] + planValues).joined(separator: "::")
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task(id: syncFingerprint) {
                await synchronize()
            }
            .onReceive(NotificationCenter.default.publisher(for: .calendarSyncRequested)) { _ in
                Task { await synchronize() }
            }
    }

    private func synchronize() async {
        guard isEnabled, !calendarIdentifier.isEmpty else { return }
        do {
            try await CalendarSyncService.shared.sync(plans: plans)
        } catch {
            CalendarSyncPreferences.recordFailure(error)
        }
    }
}
