import Foundation
import TagwerkCore
import UserNotifications

/// Permission to show notifications, reduced to what Tagwerk distinguishes.
enum NotificationAuthorization: Equatable, Sendable {
    case notDetermined, denied, authorized
}

/// A pending request as Tagwerk sees it; `fireDate` is `nil` when the trigger will not fire again.
struct PendingNotification: Equatable, Sendable {
    let id: String
    let fireDate: Date?
}

/// The parts of `UNUserNotificationCenter` Tagwerk uses; tests replace it with an in-memory fake.
@MainActor
protocol NotificationCenterClient: AnyObject {
    func authorization() async -> NotificationAuthorization
    func requestAuthorization() async throws -> Bool
    func pendingRequests() async -> [PendingNotification]
    func add(_ notification: PlannedNotification) async throws
    /// A reminder that repeats every day (or every week on `weekday`) at the same clock time (phase 7 routines).
    func addRepeating(_ notification: RoutineNotification) async throws
    /// A routine reminder for one day: year, month, day, hour and minute without a time zone, not repeating.
    func addDated(_ notification: DatedRoutineNotification) async throws
    func removePending(_ identifiers: [String]) async
}

/// Keys of the `userInfo` dictionary of a Tagwerk notification.
enum NotificationPayload {
    static let taskKey = "taskKey"
    static let eventID = "eventID"
    static let day = "day"
    /// Path of an `AppRoute`; a routine notification carries this instead of a task or event.
    static let route = "route"

    static func userInfo(for target: PlannedNotification.Target) -> [String: String] {
        switch target {
        case .task(let id):
            [taskKey: id.key]
        case .event(let id, let day):
            [eventID: id, Self.day: String(format: "%04d-%02d-%02d", day.year, day.month, day.day)]
        }
    }

    static func target(from userInfo: [String: String]) -> PlannedNotification.Target? {
        if let key = userInfo[taskKey], let id = TaskID(key: key) { return .task(id) }
        guard let eventID = userInfo[eventID], let text = userInfo[day] else { return nil }
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return .event(id: eventID, day: PlanDay(year: parts[0], month: parts[1], day: parts[2]))
    }
}

/// `UNUserNotificationCenter` behind `NotificationCenterClient`. Callbacks map system objects to Sendable
/// values before they leave the callback, so nothing non-Sendable crosses isolation boundaries.
@MainActor
final class SystemNotificationCenter: NotificationCenterClient {
    private var center: UNUserNotificationCenter { .current() }

    func authorization() async -> NotificationAuthorization {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                let result: NotificationAuthorization = switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral: .authorized
                case .denied: .denied
                default: .notDetermined
                }
                continuation.resume(returning: result)
            }
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func pendingRequests() async -> [PendingNotification] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map { request in
                    PendingNotification(id: request.identifier,
                                        fireDate: (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate())
                })
            }
        }
    }

    func add(_ notification: PlannedNotification) async throws {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.interruptionLevel = .active
        content.threadIdentifier = notification.source?.rawValue ?? "deadline"
        content.userInfo = NotificationPayload.userInfo(for: notification.target)
        // Absolute moment with its time zone, so a trip does not shift a timed deadline until the next reschedule.
        // A fixed offset keeps the repeated hour at the end of summer time unambiguous.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: TimeZone.current.secondsFromGMT(for: notification.fireDate)) ?? .current
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: notification.fireDate)
        parts.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    func addRepeating(_ notification: RoutineNotification) async throws {
        // Hour and minute only, no time zone: the reminder follows the clock of the place the phone is in.
        // With a weekday the reminder repeats weekly on that day, else daily.
        let components = DateComponents(hour: notification.hour, minute: notification.minute, weekday: notification.weekday)
        try await addRoutineRequest(id: notification.id, title: notification.title, body: notification.body, route: notification.route,
                                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
    }

    func addDated(_ notification: DatedRoutineNotification) async throws {
        // Date and clock time without a time zone, once: the reminder follows the clock of the place the phone is in.
        let components = DateComponents(year: notification.year, month: notification.month, day: notification.day,
                                        hour: notification.hour, minute: notification.minute)
        try await addRoutineRequest(id: notification.id, title: notification.title, body: notification.body, route: notification.route,
                                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }

    private func addRoutineRequest(id: String, title: String, body: String, route: AppRoute, trigger: UNCalendarNotificationTrigger) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active
        content.threadIdentifier = "routine"
        content.userInfo = [NotificationPayload.route: route.rawValue]
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    func removePending(_ identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
