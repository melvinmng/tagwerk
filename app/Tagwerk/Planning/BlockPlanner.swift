import Foundation
import RemindersKit
import TagwerkCore

/// Writes time blocks for tasks into the plan calendar and keeps day assignments in step.
@MainActor
final class BlockPlanner {
    /// How far ahead "future blocks" of a task are searched.
    static let lookahead: TimeInterval = 120 * 86_400

    private let store: CalendarStore
    private let planStore: PlanStore
    let links: EventLinkStore
    private let settings: AppSettings
    private let calendar: Calendar

    init(store: CalendarStore, planStore: PlanStore, links: EventLinkStore, settings: AppSettings, calendar: Calendar) {
        self.store = store
        self.planStore = planStore
        self.links = links
        self.settings = settings
        self.calendar = calendar
    }

    var canWriteBlocks: Bool { store.planCalendar(id: settings.planCalendarID) != nil }

    /// Block title: GitHub issues as "#<number> <title>".
    static func blockTitle(for task: TaskItem) -> String {
        if task.id.source == .github, let number = task.url?.lastPathComponent, Int(number) != nil {
            return "#\(number) \(task.title)"
        }
        return task.title
    }

    /// Creates a block and sets the task's planned day to the block's day (design §11.3).
    @discardableResult
    func createBlock(for task: TaskItem, start: Date, minutes: Int) throws -> CalendarEvent {
        guard let calendarID = store.planCalendar(id: settings.planCalendarID)?.id else {
            throw TaskWriteError.failed(String(localized: "Kein Plan-Kalender"))
        }
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        let block = try store.createBlock(BlockDraft(title: Self.blockTitle(for: task), start: start, end: end, taskID: task.id),
                                          in: calendarID)
        planStore.assign(task.id, to: PlanDay(date: start, calendar: calendar))
        return block
    }

    /// Blocks of `taskID` in the plan calendar that start at or after `date`.
    func futureBlocks(for taskID: TaskID, after date: Date) -> [CalendarEvent] {
        guard let calendarID = settings.planCalendarID else { return [] }
        return store.events(in: DateInterval(start: date, duration: Self.lookahead), calendarIDs: [calendarID])
            .filter { $0.start >= date && $0.url.flatMap(TaskLinkURL.parse) == taskID }
            .sorted { $0.start < $1.start }
    }

    /// Blocks of `taskID` in the plan calendar that overlap `interval`, oldest first (effort measuring, plan P3).
    func blocks(for taskID: TaskID, in interval: DateInterval) -> [CalendarEvent] {
        guard let calendarID = settings.planCalendarID else { return [] }
        return store.events(in: interval, calendarIDs: [calendarID])
            .filter { $0.url.flatMap(TaskLinkURL.parse) == taskID }
            .sorted { $0.start < $1.start }
    }

    /// All blocks in the plan calendar from `date` on, grouped by their task.
    func blocksByTask(after date: Date) -> [TaskID: [CalendarEvent]] {
        guard let calendarID = settings.planCalendarID else { return [:] }
        let events = store.events(in: DateInterval(start: date, duration: Self.lookahead), calendarIDs: [calendarID])
        return Dictionary(grouping: events.compactMap { event in event.url.flatMap(TaskLinkURL.parse).map { ($0, event) } },
                          by: \.0).mapValues { $0.map(\.1) }
    }

    func moveBlock(_ block: CalendarEvent, to start: Date) throws {
        let duration = block.end.timeIntervalSince(block.start)
        _ = try store.moveBlock(id: block.id, to: start, end: start.addingTimeInterval(duration), expectedVersion: block.version)
    }

    /// Moves every future block of the task to `day`, keeping time of day and duration.
    func moveFutureBlocks(of taskID: TaskID, to day: PlanDay, after date: Date) throws {
        for block in futureBlocks(for: taskID, after: date) {
            let time = calendar.dateComponents([.hour, .minute], from: block.start)
            let start = calendar.date(byAdding: time, to: day.startDate(in: calendar)) ?? block.start
            try moveBlock(block, to: start)
        }
    }

    func deleteFutureBlocks(of taskID: TaskID, after date: Date) throws {
        for block in futureBlocks(for: taskID, after: date) {
            try store.deleteBlock(id: block.id, expectedVersion: block.version)
        }
    }
}
