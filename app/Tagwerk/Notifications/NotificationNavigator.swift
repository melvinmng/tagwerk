import Foundation
import Observation
import TagwerkCore
import UserNotifications

/// Where a tap on a notification leads.
enum NotificationRoute: Equatable {
    /// The task list with the task scrolled into view and marked.
    case task(TaskID)
    /// The task no longer exists: only the task list.
    case tasksTab
    /// The day view of a deadline event.
    case day(PlanDay)
}

/// Remembers the target of a tapped notification until the app can show it (a cold start loads tasks first).
@MainActor
@Observable
final class NotificationNavigator {
    private var pendingTarget: PlannedNotification.Target?
    /// Counts received taps, so views react to every tap, also to a second one for the same target.
    private(set) var receivedCount = 0

    var hasPendingTarget: Bool { pendingTarget != nil }

    func receive(_ userInfo: [String: String]) {
        pendingTarget = NotificationPayload.target(from: userInfo)
        receivedCount += 1
    }

    /// The route for the pending target once the data is there; `nil` while the task's source is still loading.
    /// Makes a hidden task visible by switching the list filter to "Alle".
    func takeRoute(taskList: TaskListModel) -> NotificationRoute? {
        guard let target = pendingTarget else { return nil }
        switch target {
        case .event(_, let day):
            pendingTarget = nil
            return .day(day)
        case .task(let id):
            let exists = taskList.items.contains { $0.id == id }
            let sourceSettled = taskList.sourceStates[id.source] != nil && !taskList.loadingSources.contains(id.source)
            guard exists || sourceSettled else { return nil }
            pendingTarget = nil
            guard exists else { return .tasksTab }
            if !taskList.filter.sources.contains(id.source) { taskList.filter = .all }
            return .task(id)
        }
    }
}

/// Delegate of the system notification center. iOS may call it off the main thread, so the methods are
/// nonisolated and pass only strings to the main actor.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let navigator: NotificationNavigator

    init(navigator: NotificationNavigator) {
        self.navigator = navigator
    }

    /// Shows the banner also while Tagwerk is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        var strings: [String: String] = [:]
        for (key, value) in response.notification.request.content.userInfo {
            if let key = key as? String, let value = value as? String { strings[key] = value }
        }
        let navigator = self.navigator
        Task { @MainActor in navigator.receive(strings) }
        completionHandler()
    }
}
