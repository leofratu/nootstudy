import Foundation
import SwiftData
import UserNotifications
import SwiftData

struct NotificationService {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    static func scheduleDailyReminder(hour: Int, minute: Int, dueCount: Int) {
        let center = UNUserNotificationCenter.current()

        // Remove existing daily reminders
        center.removePendingNotificationRequests(withIdentifiers: ["daily-review-reminder"])

        let content = UNMutableNotificationContent()
        content.title = "IB Vault — Time to Study! 📚"
        content.body = dueCount > 0
            ? "You have \(dueCount) cards due today. Keep your streak alive!"
            : "Review your knowledge and stay ahead of the forgetting curve."
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "daily-review-reminder", content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                print("Failed to schedule daily reminder: \(error)")
            }
        }
    }

    static func scheduleStreakWarning() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["streak-warning"])

        let content = UNMutableNotificationContent()
        content.title = "Streak at Risk! 🔥"
        content.body = "Study before midnight to keep your streak alive."
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = 21
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "streak-warning", content: content, trigger: trigger)

        center.add(request)
    }

    static func sendMilestoneNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "milestone-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// Schedule a notification for due cards grouped by subject
    static func scheduleDueCardReminders(context: ModelContext) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["due-cards-reminder"])

        let now = Date()
        let pred = #Predicate<StudyCard> { $0.nextReviewDate <= now }
        guard let dueCards = try? context.fetch(FetchDescriptor(predicate: pred)),
              !dueCards.isEmpty else { return }

        // Group by subject
        let grouped = Dictionary(grouping: dueCards) { $0.subject?.name ?? "Unknown" }
        let summary = grouped.map { "\($0.value.count) \($0.key)" }.joined(separator: ", ")

        let content = UNMutableNotificationContent()
        content.title = "📚 Cards Due for Review"
        content.body = "\(dueCards.count) cards need attention: \(summary)"
        content.sound = .default

        // Notify in 4 hours
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 4 * 3600, repeats: false)
        let request = UNNotificationRequest(identifier: "due-cards-reminder", content: content, trigger: trigger)
        center.add(request)
    }
}
