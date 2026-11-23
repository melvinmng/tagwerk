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
    private let router: AppRouter
    /// "Heute nicht" on the Bible Study reminder: runs without the app opening and finishes before the system may suspend it.
    private let skipBibleStudy: @MainActor () async -> Void

    init(navigator: NotificationNavigator, router: AppRouter, skipBibleStudy: @escaping @MainActor () async -> Void = {}) {
        self.navigator = navigator
        self.router = router
        self.skipBibleStudy = skipBibleStudy
    }

    /// A tap on the notification or on one of its actions. "Heute nicht" only drops the reminder of today; every other answer,
    /// "Starten" included, goes the way of a tap (the notification carries the link to the start sheet).
    @MainActor
    func handle(_ strings: [String: String], action: String) async {
        if action == BibleStudyReminders.skipAction {
            await skipBibleStudy()
            return
        }
        handle(strings)
    }

    /// A routine reminder carries the path of a link and goes to the router; everything else to the navigator.
    @MainActor
    func handle(_ strings: [String: String]) {
        Self.dispatch(strings, navigator: navigator, router: router)
    }

    @MainActor
    private static func dispatch(_ strings: [String: String], navigator: NotificationNavigator, router: AppRouter) {
        if let path = strings[NotificationPayload.route] {
            if let route = AppRoute(rawValue: path) { router.open(route) }
            return
        }
        navigator.receive(strings)
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
        let action = response.actionIdentifier
        if action == BibleStudyReminders.skipAction {
            // The app runs in the background for this action; the system must not suspend it before the day is skipped.
            nonisolated(unsafe) let finish = completionHandler
            let skip = skipBibleStudy
            Task { @MainActor in
                await skip()
                finish()
            }
            return
        }
        let navigator = self.navigator, router = self.router
        Task { @MainActor in Self.dispatch(strings, navigator: navigator, router: router) }
        completionHandler()
    }
}
