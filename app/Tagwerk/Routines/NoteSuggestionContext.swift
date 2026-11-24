import AIKit
import Foundation
import GitHubKit
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
@MainActor
enum NoteSuggestionRules {
    static let allowedTools: Set<String> = ["create_task", "reschedule_task", "assign_to_day", "create_time_block", "update_event"]
    static let maximumCards = 5

    /// Calls with a known function and with identifiers that were part of the context; at most five. Calls that reach
    /// outside the context are dropped silently. `update_event` is limited to Tagwerk's time blocks. `create_task` for
    /// GitHub is kept only with `gitHub` (signed in and a catalog stored): the target of such an issue is resolved on the
    /// device by `issueDraft`, never taken from the model.
    static func accepted(_ calls: [ToolCall], context: NoteSuggestionContext, gitHub: Bool = false) -> [ToolCall] {
        let valid = calls.filter { call in
            guard allowedTools.contains(call.name),
                  let arguments = try? JSONSerialization.jsonObject(with: call.arguments) as? [String: Any] else { return false }
            switch call.name {
            case "create_task":
                return gitHub || (arguments["source"] as? String) != "github"
            case "update_event":
                return (arguments["event_id"] as? String).map(context.blockEventIDs.contains) ?? false
            default:
                return (arguments["id"] as? String).map(context.taskIDs.contains) ?? false
            }
        }
        return Array(valid.prefix(maximumCards))
    }

    /// True for a `create_task` call that creates a GitHub issue.
    static func isIssue(_ call: ToolCall) -> Bool {
        guard call.name == "create_task",
              let arguments = try? JSONSerialization.jsonObject(with: call.arguments) as? [String: Any] else { return false }
        return arguments["source"] as? String == "github"
    }

    /// A `create_task` call for GitHub with the target the user sees. The people are forced to `null` (the user): the model
    /// knows no logins, and every other person is chosen on the card (decision D8). Repository and projects are resolved
    /// against the stored catalog; a repository the model named is only taken when it is unique. The returned target is
    /// `nil` while the user has to choose; the call then keeps what could be resolved (repository, known projects) and
    /// carries `null` for the rest. Any other call is returned unchanged with a `nil` target.
    static func issueDraft(for call: ToolCall, catalog: GitHubCatalog) -> (call: ToolCall, target: AppTools.GitHubTarget?) {
        guard isIssue(call), var arguments = try? JSONSerialization.jsonObject(with: call.arguments) as? [String: Any] else {
            return (call, nil)
        }
        let named = (arguments["repository"] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        // Without a name the only repository is the only choice; a name that does not match is not replaced by a guess.
        let repository: String?
        if let named {
            repository = Self.repository(named: named, in: catalog)
        } else {
            repository = catalog.repositories.count == 1 ? catalog.repositories[0] : nil
        }

        // Ids the catalog does not know are dropped; none left means "the projects linked to the repository".
        let known = Set(catalog.projects.map(\.id))
        let projectIDs = (arguments["project_ids"] as? [String]).map { $0.filter(known.contains) }.flatMap { $0.isEmpty ? nil : $0 }

        var target: AppTools.GitHubTarget?
        if let repository, case .success(let resolved) = AppTools.gitHubTarget(repository: repository, projectIDs: projectIDs, catalog: catalog) {
            target = resolved
        }
        arguments["repository"] = (target?.repository ?? repository) as Any? ?? NSNull()
        arguments["project_ids"] = (target?.projectIDs ?? projectIDs) as Any? ?? NSNull()
        arguments["assignees"] = NSNull()
        let data = (try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys, .withoutEscapingSlashes])) ?? call.arguments
        return (ToolCall(id: call.id, name: call.name, arguments: data), target)
    }

    /// The repository of the catalog that `text` names: "owner/name", or the name alone (case-insensitive). A name that
    /// matches several repositories (the same name under different owners) matches none.
    static func repository(named text: String, in catalog: GitHubCatalog) -> String? {
        let wanted = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty else { return nil }
        if wanted.contains("/") {
            return catalog.repositories.first { $0.lowercased() == wanted }
        }
        let matches = catalog.repositories.filter { $0.lowercased().split(separator: "/").last.map(String.init) == wanted }
        return matches.count == 1 ? matches[0] : nil
    }

    /// The function definitions of the request. With GitHub, `create_task` is described for what happens here: the model
    /// names a GitHub issue and, at most, the repository from the note; the target is resolved on the device and the
    /// list functions of the chat are not offered.
    static func definitions(from all: [ToolDefinition], gitHub: Bool) -> [ToolDefinition] {
        all.filter { allowedTools.contains($0.name) }.map { definition in
            guard gitHub, definition.name == "create_task",
                  var schema = try? JSONSerialization.jsonObject(with: definition.parameters) as? [String: Any],
                  var properties = schema["properties"] as? [String: Any] else { return definition }
            let notes: [String: String] = [
                "repository": "Repository named in the note, as written there; null if the note names none. GitHub issues only",
                "project_ids": "Always null: the app resolves the projects",
                "assignees": "Always null: the app assigns the user and lets them change it",
            ]
            for (key, note) in notes {
                guard var property = properties[key] as? [String: Any] else { continue }
                property["description"] = note
                properties[key] = property
            }
            schema["properties"] = properties
            var updated = definition
            updated.description = #"Creates a task. For a GitHub issue use source "github"; the app resolves the target. For other sources repository, project_ids and assignees must be null. Needs confirmation by the user."#
            updated.parameters = (try? JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])) ?? definition.parameters
            return updated
        }
    }
}
