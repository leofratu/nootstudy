import Foundation
import UserNotifications

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
}
