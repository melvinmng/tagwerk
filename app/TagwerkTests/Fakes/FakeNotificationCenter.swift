import Foundation
import TagwerkCore
@testable import Tagwerk

/// In-memory notification center; never touches the system center.
@MainActor
final class FakeNotificationCenter: NotificationCenterClient {
    var status: NotificationAuthorization = .authorized
    var grantsOnRequest = true
    private(set) var authorizationRequests = 0
    /// Pending requests by identifier.
    private(set) var pending: [String: PendingNotification] = [:]
    private(set) var added: [PlannedNotification] = []
    /// Simulates a slow system call, so overlapping runs can be tested.
    var addDelay: Duration?

    func authorization() async -> NotificationAuthorization { status }

    func requestAuthorization() async throws -> Bool {
        authorizationRequests += 1
        status = grantsOnRequest ? .authorized : .denied
        return grantsOnRequest
    }

    func pendingRequests() async -> [PendingNotification] { Array(pending.values) }

    func add(_ notification: PlannedNotification) async throws {
        if let addDelay { try? await Task.sleep(for: addDelay) }
        added.append(notification)
        pending[notification.id] = PendingNotification(id: notification.id, fireDate: notification.fireDate)
    }

    func removePending(_ identifiers: [String]) async {
        for id in identifiers { pending[id] = nil }
    }

    /// Adds a request directly, e.g. one from an earlier run or from another component.
    func seed(_ id: String, fireDate: Date?) {
        pending[id] = PendingNotification(id: id, fireDate: fireDate)
    }

    var pendingIDs: Set<String> { Set(pending.keys) }
}
