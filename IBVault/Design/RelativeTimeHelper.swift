import Foundation

enum RelativeTimeHelper {
    /// Returns "now" / "just now" for very recent dates (<60s), otherwise a localized relative string.
    static func string(for date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 && interval >= 0 {
            return "now"
        }
        if interval < 120 && interval >= 0 {
            return "1 min ago"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = IBLocalClock.locale
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
