import Foundation
import TagwerkCore
import WidgetKit

/// One moment of the widget timeline: the time it shows and the snapshot it was built from.
struct SnapshotTimelineEntry: TimelineEntry {
    let date: Date
    /// `nil` when the file is missing, unreadable or of an unknown version.
    let snapshot: WidgetSnapshot?
}

/// Gregorian calendar with Monday first in the device time zone, like the app's planning calendar.
extension Calendar {
    static var widget: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.locale = .current
        calendar.timeZone = .current
        return calendar
    }
}

/// Reads only the snapshot file of the App Group container: no SwiftData, EventKit, Health, network or AI
/// (phase 4 design §2). Synchronous file reads keep the provider free of actor isolation.
struct SnapshotProvider: TimelineProvider {
    static var directory: URL? {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: WidgetSnapshot.appGroupInfoKey) as? String,
              identifier.hasPrefix("group."),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else { return nil }
        return container.appending(path: "Library/Application Support", directoryHint: .isDirectory)
    }

    func placeholder(in context: Context) -> SnapshotTimelineEntry {
        SnapshotTimelineEntry(date: .now, snapshot: .sample(now: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotTimelineEntry) -> Void) {
        let snapshot = context.isPreview ? WidgetSnapshot.sample(now: .now) : WidgetSnapshot.load(from: Self.directory)
        completion(SnapshotTimelineEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotTimelineEntry>) -> Void) {
        let now = Date.now
        let snapshot = WidgetSnapshot.load(from: Self.directory)
        // Without a file the widget asks to open the app and looks again in an hour.
        guard let snapshot else {
            completion(Timeline(entries: [SnapshotTimelineEntry(date: now, snapshot: nil)], policy: .after(now.addingTimeInterval(3600))))
            return
        }
        let entries = snapshot.timelineDates(from: now, calendar: .widget).map { SnapshotTimelineEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

extension WidgetSnapshot {
    /// Neutral sample content for the widget gallery and placeholders.
    static func sample(now: Date) -> WidgetSnapshot {
        let calendar = Calendar.widget
        let start = calendar.date(bySettingHour: 10, minute: 30, second: 0, of: now) ?? now
        let entries = [
            SnapshotEntry(id: "1", title: "Issue #12 Login", start: start, end: start.addingTimeInterval(5400), kind: .block,
                          colorHex: nil, isAllDay: false),
            SnapshotEntry(id: "2", title: String(localized: "Lernzettel"), start: start.addingTimeInterval(9000), end: start.addingTimeInterval(12600),
                          kind: .block, colorHex: nil, isAllDay: false),
            SnapshotEntry(id: "3", title: String(localized: "Vorlesung"), start: start.addingTimeInterval(16200), end: start.addingTimeInterval(21600),
                          kind: .event, colorHex: "#34C759", isAllDay: false),
        ]
        let intake = SnapshotIntake(kcal: 1240, hasEstimate: true, goalKcal: 2300, waterMilliliters: 1200, goalWaterMilliliters: 2000)
        return WidgetSnapshot(createdAt: now, days: [
            SnapshotDay(day: PlanDay(date: now, calendar: calendar), entries: entries, deadlineCount: 1, intake: intake),
        ])
    }
}
