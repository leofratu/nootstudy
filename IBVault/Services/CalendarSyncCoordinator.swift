import SwiftData
import SwiftUI

struct CalendarSyncCoordinator: View {
    @Query(sort: \StudyPlan.scheduledDate, order: .forward) private var plans: [StudyPlan]
    @AppStorage(CalendarSyncPreferences.isEnabledKey) private var isEnabled = false
    @AppStorage(CalendarSyncPreferences.calendarIdentifierKey) private var calendarIdentifier = ""
    @AppStorage(CalendarSyncPreferences.needsAttentionKey) private var needsAttention = false
    @AppStorage(CalendarSyncPreferences.lastErrorKey) private var lastError = ""

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
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 0)
                .accessibilityHidden(true)
            if needsAttention, isEnabled {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(IBColors.warning)
                    Text("Calendar sync stopped. \(lastError)")
                        .font(.callout)
                        .lineLimit(2)
                    Spacer()
                    Button("Open Settings") {
                        NotificationCenter.default.post(
                            name: .ibVaultAppCommand,
                            object: IBVaultAppCommand.showSettings.notificationPayload
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
            .task(id: syncFingerprint) {
                await synchronize()
            }
            .onReceive(NotificationCenter.default.publisher(for: .calendarSyncRequested)) { _ in
                Task { await synchronize() }
            }
    }

    private func synchronize() async {
        // An enabled sync with no calendar is reported by the service, not skipped.
        guard isEnabled else { return }
        do {
            try await CalendarSyncService.shared.sync(plans: plans)
        } catch {
            CalendarSyncPreferences.recordFailure(error)
        }
    }
}
