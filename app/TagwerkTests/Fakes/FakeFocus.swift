import Foundation
import TagwerkCore
@testable import Tagwerk

/// A clock the tests move by hand.
@MainActor
final class FocusTestClock {
    var now: Date

    init(_ start: Date = testNow()) { now = start }

    func advance(minutes: Double) { now = now.addingTimeInterval(minutes * 60) }
}

/// Records what the timer asks of the Live Activity.
@MainActor
final class FakeFocusActivity: FocusActivityControlling {
    /// An activity that exists before the app starts (survived a restart).
    var existing = false
    private(set) var started: [FocusActivityContent] = []
    private(set) var updated: [FocusActivityContent] = []
    private(set) var endCount = 0
    private(set) var adoptCount = 0

    var isActive: Bool { existing || (!started.isEmpty && endCount == 0) }
    var latest: FocusActivityContent? { updated.last ?? started.last }

    func adopt() -> Bool {
        guard existing else { return false }
        adoptCount += 1
        return true
    }

    func start(_ content: FocusActivityContent) async {
        started.append(content)
        existing = true
        endCount = 0
    }

    func update(_ content: FocusActivityContent) async { updated.append(content) }

    func end() async {
        endCount += 1
        existing = false
    }
}

/// Keeps the single pending notice of the timer.
@MainActor
final class FakeFocusNotifications: FocusNotificationScheduling {
    private(set) var pending: FocusPhaseNotice?
    private(set) var scheduleCount = 0

    func schedule(_ notice: FocusPhaseNotice) async {
        pending = notice
        scheduleCount += 1
    }

    func cancel() async { pending = nil }
}

@MainActor
final class FakeFocusNotificationCenter: FocusNotificationCenter {
    struct Request: Equatable {
        let identifier: String
        let title: String
        let body: String
        let fireDate: Date
        let userInfo: [String: String]
    }

    private(set) var requests: [String: Request] = [:]

    func add(identifier: String, title: String, body: String, fireDate: Date, userInfo: [String: String]) async {
        requests[identifier] = Request(identifier: identifier, title: title, body: body, fireDate: fireDate, userInfo: userInfo)
    }

    func remove(identifiers: [String]) async {
        for identifier in identifiers { requests[identifier] = nil }
    }
}
