import EventKit
import Foundation

struct CalendarSyncOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let accountName: String

    var displayName: String {
        accountName.isEmpty ? title : "\(title) - \(accountName)"
    }
}

enum CalendarSyncPreferences {
    static let isEnabledKey = "calendarSyncEnabled"
    static let calendarIdentifierKey = "calendarSyncCalendarIdentifier"
    static let eventIdentifiersKey = "calendarSyncEventIdentifiers"
    static let lastSyncDateKey = "calendarSyncLastDate"
    static let lastErrorKey = "calendarSyncLastError"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: isEnabledKey)
    }

    static var calendarIdentifier: String {
        UserDefaults.standard.string(forKey: calendarIdentifierKey) ?? ""
    }

    static var eventIdentifiers: [String: String] {
        get {
            UserDefaults.standard.dictionary(forKey: eventIdentifiersKey) as? [String: String] ?? [:]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: eventIdentifiersKey)
        }
    }

    static func recordSuccess(at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: lastSyncDateKey)
        UserDefaults.standard.removeObject(forKey: lastErrorKey)
    }

    static func recordFailure(_ error: any Error) {
        UserDefaults.standard.set(error.localizedDescription, forKey: lastErrorKey)
    }
}

enum CalendarSyncError: LocalizedError {
    case accessDenied
    case calendarUnavailable

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access is off. Allow Noot Study in System Settings > Privacy & Security > Calendars."
        case .calendarUnavailable:
            return "The selected calendar is no longer available or cannot be edited."
        }
    }
}

extension Notification.Name {
    static let calendarSyncRequested = Notification.Name("CalendarSyncRequested")
}

@MainActor
final class CalendarSyncService {
    static let shared = CalendarSyncService()

    private let eventStore = EKEventStore()

    private init() {}

    func requestAccess() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess { return }

        if status == .notDetermined || status == .writeOnly {
            guard try await eventStore.requestFullAccessToEvents() else {
                throw CalendarSyncError.accessDenied
            }
            return
        }

        throw CalendarSyncError.accessDenied
    }

    func writableCalendars() async throws -> [CalendarSyncOption] {
        try await requestAccess()
        return eventStore.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map {
                CalendarSyncOption(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    accountName: $0.source.title
                )
            }
            .sorted {
                if $0.accountName == $1.accountName { return $0.title < $1.title }
                return $0.accountName < $1.accountName
            }
    }

    func sync(plans: [StudyPlan]) async throws {
        guard CalendarSyncPreferences.isEnabled else { return }
        try await requestAccess()

        guard let calendar = eventStore.calendar(
            withIdentifier: CalendarSyncPreferences.calendarIdentifier
        ), calendar.allowsContentModifications else {
            throw CalendarSyncError.calendarUnavailable
        }

        var mappings = CalendarSyncPreferences.eventIdentifiers
        let currentPlanIDs = Set(plans.map { $0.id.uuidString })

        for stalePlanID in mappings.keys.filter({ !currentPlanIDs.contains($0) }) {
            if let eventIdentifier = mappings[stalePlanID],
               let event = eventStore.event(withIdentifier: eventIdentifier) {
                try eventStore.remove(event, span: .thisEvent, commit: false)
            }
            mappings.removeValue(forKey: stalePlanID)
        }

        for plan in plans {
            let planID = plan.id.uuidString
            let event = existingEvent(for: plan, identifier: mappings[planID], in: calendar)
                ?? EKEvent(eventStore: eventStore)

            configure(event, from: plan, calendar: calendar)
            try eventStore.save(event, span: .thisEvent, commit: false)
            mappings[planID] = event.eventIdentifier
        }

        try eventStore.commit()
        CalendarSyncPreferences.eventIdentifiers = mappings
        CalendarSyncPreferences.recordSuccess()
    }

    private func existingEvent(
        for plan: StudyPlan,
        identifier: String?,
        in calendar: EKCalendar
    ) -> EKEvent? {
        if let identifier, let event = eventStore.event(withIdentifier: identifier) {
            return event
        }

        let searchStart = plan.scheduledDate.addingTimeInterval(-86_400)
        let searchEnd = plan.scheduledEndDate.addingTimeInterval(86_400)
        let predicate = eventStore.predicateForEvents(
            withStart: searchStart,
            end: searchEnd,
            calendars: [calendar]
        )
        let marker = eventMarker(for: plan.id)
        return eventStore.events(matching: predicate).first { $0.notes?.contains(marker) == true }
    }

    private func configure(_ event: EKEvent, from plan: StudyPlan, calendar: EKCalendar) {
        event.calendar = calendar
        event.title = plan.isFollowUpReview
            ? "Noot Review: \(plan.subjectName)"
            : "Noot Study: \(plan.subjectName)"
        event.startDate = plan.scheduledDate
        event.endDate = max(plan.scheduledEndDate, plan.scheduledDate.addingTimeInterval(60))
        event.notes = eventNotes(for: plan)
        event.availability = .busy
    }

    private func eventNotes(for plan: StudyPlan) -> String {
        var lines = [eventMarker(for: plan.id)]
        if !plan.selectedTopicNames.isEmpty {
            lines.append("Topics: \(plan.selectedTopicNames.joined(separator: ", "))")
        }
        if !plan.selectedSubtopicNames.isEmpty {
            lines.append("Subtopics: \(plan.selectedSubtopicNames.joined(separator: ", "))")
        }
        lines.append("Status: \(plan.isCompleted ? "Completed" : "Planned")")
        lines.append("Created by Noot Study")
        return lines.joined(separator: "\n")
    }

    private func eventMarker(for planID: UUID) -> String {
        "NootStudy-ID: \(planID.uuidString)"
    }
}
