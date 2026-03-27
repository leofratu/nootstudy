import Foundation
import SwiftData
import UserNotifications

enum NotificationError: Error, LocalizedError {
    case permissionDenied
    case schedulingFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Notification permission was denied"
        case .schedulingFailed(let error):
            return "Failed to schedule notification: \(error.localizedDescription)"
        }
    }
}

struct NotificationConfig {
    var dailyReminderID: String { "daily-review-reminder" }
    var streakWarningID: String { "streak-warning" }
    var dueCardsReminderID: String { "due-cards-reminder" }
    
    static let `default` = NotificationConfig()
}

enum NotificationService {
    static func requestPermission(completion: ((Bool, Error?) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            completion?(granted, error)
        }
    }
    
    static func checkPermissionStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }
    
    static func scheduleDailyReminder(
        hour: Int,
        minute: Int,
        dueCount: Int,
        config: NotificationConfig = .default
    ) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [config.dailyReminderID])
        
        let content = UNMutableNotificationContent()
        content.title = "IB Vault — Time to Study!"
        content.body = dueCount > 0
            ? "You have \(dueCount) cards due today. Keep your streak alive!"
            : "Review your knowledge and stay ahead of the forgetting curve."
        content.sound = .default
        content.badge = dueCount as NSNumber
        
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: true
        )
        
        let request = UNNotificationRequest(
            identifier: config.dailyReminderID,
            content: content,
            trigger: trigger
        )
        
        center.add(request)
    }
    
    static func scheduleStreakWarning(config: NotificationConfig = .default) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [config.streakWarningID])
        
        let content = UNMutableNotificationContent()
        content.title = "Streak at Risk!"
        content.body = "Study before midnight to keep your streak alive."
        content.sound = .default
        
        var dateComponents = DateComponents()
        dateComponents.hour = 21
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: true
        )
        
        let request = UNNotificationRequest(
            identifier: config.streakWarningID,
            content: content,
            trigger: trigger
        )
        
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
    
    static func scheduleDueCardReminders(
        context: ModelContext,
        config: NotificationConfig = .default
    ) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [config.dueCardsReminderID])
        
        let now = Date()
        let predicate = #Predicate<StudyCard> { $0.nextReviewDate <= now }
        
        guard let dueCards = try? context.fetch(FetchDescriptor(predicate: predicate)),
              !dueCards.isEmpty else { return }
        
        let grouped = Dictionary(grouping: dueCards) { $0.subject?.name ?? "Unknown" }
        let summary = grouped.map { "\($0.value.count) \($0.key)" }.joined(separator: ", ")
        
        let content = UNMutableNotificationContent()
        content.title = "Cards Due for Review"
        content.body = "\(dueCards.count) cards need attention: \(summary)"
        content.sound = .default
        content.badge = dueCards.count as NSNumber
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 4 * 3600, repeats: false)
        let request = UNNotificationRequest(
            identifier: config.dueCardsReminderID,
            content: content,
            trigger: trigger
        )
        
        center.add(request)
    }
    
    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    static func cancelNotification(withIdentifier identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}