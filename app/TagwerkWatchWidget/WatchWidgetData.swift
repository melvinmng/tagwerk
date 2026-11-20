import Foundation
import TagwerkCore
import WidgetKit

/// What the complications read: the snapshot file of the phone plus the actions that wait on the watch (the queue file
/// and the inbox of the buttons), already carried out. No SwiftData, no network, no WatchConnectivity.
enum WatchWidgetData {
    struct Content {
        /// The snapshot as the phone sent it; `nil` before the first one.
        var original: WatchSnapshot?
        /// With the local actions applied.
        var current: WatchSnapshot?
    }

    static func load() -> Content {
        let directory = WatchStorage.groupDirectory
        guard let original = WatchSnapshot.load(from: directory) else { return Content(original: nil, current: nil) }
        let actions = WatchActionQueue.load(from: directory).entries.map(\.action) + WatchActionInbox.pending(in: directory)
        return Content(original: original, current: original.applying(actions))
    }

    /// Neutral content for the gallery and placeholders.
    static func sample(now: Date) -> WatchSnapshot {
        let calendar = Calendar.watch
        let start = calendar.date(bySettingHour: 10, minute: 30, second: 0, of: now) ?? now
        let entry = SnapshotEntry(id: "1", title: String(localized: "Vorlesung"), start: start, end: start.addingTimeInterval(5400),
                                  kind: .event, colorHex: nil, isAllDay: false)
        return WatchSnapshot(createdAt: now, day: PlanDay(date: now, calendar: calendar), entries: [entry], tasks: [], habits: [],
                             habitCounter: HabitCounter(done: 3, total: 5),
                             water: WatchWater(milliliters: 1200, goalMilliliters: 2000, showsInComplication: true), appliedActionIDs: [])
    }
}
