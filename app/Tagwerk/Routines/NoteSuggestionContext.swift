import AIKit
import Foundation
import TagwerkCore

/// What goes to ChatGPT besides the note (phase 7 design §9.2): the open tasks and the events of today and the next six
/// days, so a card can move something on one of those days. Never task notes, comments, goals, Health data, gratitude,
/// habits or earlier notes.
struct NoteSuggestionContext: Equatable {
    static let windowDays = 7
    static let maximumTasks = 60
    static let maximumEvents = 100

    /// Tasks and events as compact JSON.
    var json: String
    /// `TaskID.key` of every task sent.
    var taskIDs: Set<String>
    var eventIDs: Set<String>
    /// Events that are time blocks written by Tagwerk (deviation A7); only these may be changed by a card.
    var blockEventIDs: Set<String>

    /// Open tasks planned, due or blocked within the window, plus overdue ones; events of the window. With more than
    /// `maximumTasks` tasks the oldest are cut, with more than `maximumEvents` events the latest.
    @MainActor
    static func make(taskList: TaskListModel, planning: PlanningModel, events: (DateInterval) -> [CalendarEvent],
                     planCalendarID: String?, now: Date) -> NoteSuggestionContext {
        let calendar = planning.calendar
        let today = PlanDay(date: now, calendar: calendar)
        let last = today.adding(days: windowDays - 1, calendar: calendar)
        let interval = DateInterval(start: today.startDate(in: calendar), end: last.adding(days: 1, calendar: calendar).startDate(in: calendar))

        var blocked = Set<TaskID>()
        for offset in 0..<windowDays { blocked.formUnion(planning.taskIDsWithBlocks(on: today.adding(days: offset, calendar: calendar))) }

        // The day a task is about: its planned day, else its due day.
        func keyDay(_ task: TaskItem) -> PlanDay? { planning.planStore.assignment(for: task.id) ?? task.due.map(PlanDay.init) }
        let relevant = taskList.items.filter { task in
            guard !task.isCompleted else { return false }
            if blocked.contains(task.id) { return true }
            let days = [planning.planStore.assignment(for: task.id), task.due.map(PlanDay.init)].compactMap { $0 }
            return days.contains { $0 <= last }
        }
        .sorted { lhs, rhs in
            let (left, right) = (keyDay(lhs) ?? today, keyDay(rhs) ?? today)
            return left == right ? lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending : left < right
        }
        let tasks = Array(relevant.suffix(maximumTasks))

        let sortedEvents = events(interval).sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        let shownEvents = Array(sortedEvents.prefix(maximumEvents))
        let blockIDs = Set(shownEvents.filter { planning.canEditAsBlock($0) && planCalendarID != nil }.map(\.id))

        let taskRows: [[String: Any]] = tasks.map { task in
            var row = AppTools.summary(task)
            if let planned = planning.planStore.assignment(for: task.id) { row["planned"] = AIPlanner.dayString(planned) }
            return row
        }
        let eventRows: [[String: Any]] = shownEvents.map { event in
            var row: [String: Any] = ["id": event.id, "title": event.title, "start": localText(event.start, calendar, allDay: event.isAllDay),
                                      "end": localText(event.end, calendar, allDay: event.isAllDay)]
            if event.isAllDay { row["all_day"] = true }
            if blockIDs.contains(event.id) { row["time_block"] = true }
            return row
        }
        let object: [String: Any] = ["tasks": taskRows, "events": eventRows]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return NoteSuggestionContext(json: String(decoding: data, as: UTF8.self), taskIDs: Set(tasks.map(\.id.key)),
                                     eventIDs: Set(shownEvents.map(\.id)), blockEventIDs: blockIDs)
    }

    /// "2026-11-24T18:00" in the calendar's time zone, or the day alone for all-day events.
    private static func localText(_ date: Date, _ calendar: Calendar, allDay: Bool) -> String {
        let day = AIPlanner.dayString(PlanDay(date: date, calendar: calendar))
        if allDay { return day }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return day + "T" + AIPlanner.time((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }
}

/// Which function calls of the answer may become cards (design §9.3).
enum NoteSuggestionRules {
    static let allowedTools: Set<String> = ["create_task", "reschedule_task", "assign_to_day", "create_time_block", "update_event"]
    static let maximumCards = 5

    /// Calls with a known function and with identifiers that were part of the context; at most five. Calls that reach
    /// outside the context are dropped silently. `update_event` is limited to Tagwerk's time blocks, and `create_task`
    /// never creates a GitHub issue: the repository and the people cannot be checked without the target list.
    static func accepted(_ calls: [ToolCall], context: NoteSuggestionContext) -> [ToolCall] {
        let valid = calls.filter { call in
            guard allowedTools.contains(call.name),
                  let arguments = try? JSONSerialization.jsonObject(with: call.arguments) as? [String: Any] else { return false }
            switch call.name {
            case "create_task":
                return (arguments["source"] as? String) != "github"
            case "update_event":
                return (arguments["event_id"] as? String).map(context.blockEventIDs.contains) ?? false
            default:
                return (arguments["id"] as? String).map(context.taskIDs.contains) ?? false
            }
        }
        return Array(valid.prefix(maximumCards))
    }
}
