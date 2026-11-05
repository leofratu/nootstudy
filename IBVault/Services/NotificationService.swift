import Foundation
import SwiftData
import UserNotifications

enum NotificationError: Error, LocalizedError {
    case permissionDenied
    case schedulingFailed(any Error)
    
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
    /// macOS owns the durable authorization decision. Query first so repeat
    /// launches never attempt to present a permission prompt after the learner
    /// has allowed, denied, or otherwise resolved it.
    static func requestPermission(completion: (@Sendable (Bool, (any Error)?) -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else {
                completion?(settings.authorizationStatus == .authorized, nil)
                return
            }

            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                completion?(granted, error)
            }
        }
    }
    
    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            requestPermission { granted, _ in continuation.resume(returning: granted) }
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
        content.title = "Time to study"
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
    
    static let streakWarningEnabledKey = "streakWarningEnabled"

    /// The next 9 PM with a streak at risk: today if nothing is logged yet,
    /// otherwise tomorrow. Nil with no streak to lose.
    nonisolated static func nextStreakWarning(
        streak: Int,
        lastStudyDate: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        guard streak > 0, let lastStudyDate else { return nil }
        let today = calendar.startOfDay(for: now)
        guard let tonight = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: today) else { return nil }
        if !calendar.isDate(lastStudyDate, inSameDayAs: now), now < tonight { return tonight }
        return calendar.date(byAdding: .day, value: 1, to: tonight)
    }

    /// One-shot rather than repeating, so a day already studied stays quiet.
    /// Called on launch and on every rating, which moves it past today.
    static func refreshStreakWarning(for profile: UserProfile, config: NotificationConfig = .default) {
        guard !AppEnvironment.isRunningTests else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [config.streakWarningID])
        guard UserDefaults.standard.bool(forKey: streakWarningEnabledKey),
              let fireDate = nextStreakWarning(streak: profile.activeStreak(), lastStudyDate: profile.lastStudyDate) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Streak at Risk!"
        content.body = "Study before midnight to keep your streak alive."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
            repeats: false
        )
        center.add(UNNotificationRequest(identifier: config.streakWarningID, content: content, trigger: trigger))
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
    
    /// Touches the shared `ModelContext`, so it is main-actor isolated. Callers
    /// (ReviewSessionView) run on the main actor; the fetch and badge count are
    /// only safe against the app-wide context from there.
    @MainActor
    static func scheduleDueCardReminders(
        context: ModelContext,
        config: NotificationConfig = .default
    ) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [config.dueCardsReminderID])
        
        guard let day = try? ReviewDailyLimitPolicy.day(in: context) else { return }
        let dueCards = day.limited(day.backlog)

        guard !dueCards.isEmpty else {
            return
        }
        
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
