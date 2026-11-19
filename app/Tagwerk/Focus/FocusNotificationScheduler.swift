import Foundation
import UserNotifications

/// The part of the system notification center the timer needs; tests use an in-memory fake.
@MainActor
protocol FocusNotificationCenter: AnyObject {
    func add(identifier: String, title: String, body: String, fireDate: Date, userInfo: [String: String]) async
    func remove(identifiers: [String]) async
}

/// Plans exactly one notification, the end of the running phase, outside of the deadline scheduler: its identifier
/// prefix `focus.` is not touched by `NotificationScheduler` or `RoutineNotificationScheduler`, and it takes one slot of
/// the 64 the system allows. Quiet hours do not apply: the user started the timer on purpose.
@MainActor
final class FocusNotificationScheduler: FocusNotificationScheduling {
    static let identifier = "focus.phaseEnd"

    private let center: FocusNotificationCenter

    init(center: FocusNotificationCenter? = nil) {
        self.center = center ?? SystemFocusNotificationCenter()
    }

    func schedule(_ notice: FocusPhaseNotice) async {
        guard notice.fireDate > .now else {
            await cancel()
            return
        }
        let title: String
        switch notice.endingKind {
        case .work: title = String(localized: "Fokuszeit vorbei")
        case .shortBreak, .longBreak: title = String(localized: "Pause vorbei")
        case .finished: return
        }
        var userInfo: [String: String] = [:]
        if let key = notice.taskKey { userInfo["taskKey"] = key }
        await center.remove(identifiers: [Self.identifier])
        await center.add(identifier: Self.identifier, title: title, body: notice.taskTitle ?? "", fireDate: notice.fireDate, userInfo: userInfo)
    }

    func cancel() async {
        await center.remove(identifiers: [Self.identifier])
    }
}

/// `UNUserNotificationCenter` behind `FocusNotificationCenter`. Errors are ignored on purpose: without permission the
/// timer works, only the notification is missing; nothing about the task is logged.
@MainActor
final class SystemFocusNotificationCenter: FocusNotificationCenter {
    func add(identifier: String, title: String, body: String, fireDate: Date, userInfo: [String: String]) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active
        content.threadIdentifier = "focus"
        content.userInfo = userInfo
        let interval = max(1, fireDate.timeIntervalSinceNow)
        let request = UNNotificationRequest(identifier: identifier, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
    }

    func remove(identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
