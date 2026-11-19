import AIKit
import Foundation
import RemindersKit
import TagwerkCore

/// The app functions the assistant may call (design §8.3, §11.11).
///
/// Read functions answer at once; write functions run only after the user confirmed the action card
/// (the `Conversation` takes care of that). Every answer is compact JSON: `{"ok":true,…}` or `{"error":"…"}`,
/// so the model learns about failures and can react.
@MainActor
final class AppTools: ToolHandler {
    static let readTools: Set<String> = ["list_tasks", "list_events", "list_calendars", "get_task",
                                         "list_github_targets", "list_assignees", "list_shopping"]
    static let maxListedTasks = 60
    static let maxListedRepositories = 30

    let taskList: TaskListModel
    private let planning: PlanningModel
    private let planner: AIPlanner?
    private let events: (DateInterval) -> [CalendarEvent]
    /// GitHub catalog and assignable people; `nil` while GitHub is not signed in.
    let gitHub: () -> (any GitHubDirectory)?
    /// The shopping list; `nil` in contexts without one (the functions then report that no list is set up).
    let shopping: ShoppingModel?
    /// After "plan_period": the chat closes and "Planen" shows the suggestions (review item 11).
    var onPlanned: (() -> Void)?

    init(taskList: TaskListModel, planning: PlanningModel, planner: AIPlanner?,
         events: @escaping (DateInterval) -> [CalendarEvent],
         gitHub: @escaping () -> (any GitHubDirectory)? = { nil }, shopping: ShoppingModel? = nil) {
        self.gitHub = gitHub
        self.shopping = shopping
        self.taskList = taskList
        self.planning = planning
        self.planner = planner
        self.events = events
    }

    /// The GitHub read tools are only registered while GitHub is signed in.
    var definitions: [ToolDefinition] { Self.allDefinitions + (gitHub() != nil ? Self.gitHubDefinitions : []) }

    func kind(of name: String) -> ToolKind { Self.readTools.contains(name) ? .read : .write }

    func run(_ call: ToolCall) async -> String {
        guard let arguments = try? JSONSerialization.jsonObject(with: call.arguments) as? [String: Any] else {
            return Self.error(String(localized: "Die Argumente sind kein gültiges JSON."))
        }
        do {
            return try await dispatch(call.name, Arguments(arguments))
        } catch let error as ToolError {
            return Self.error(error.message)
        } catch {
            return Self.error(TaskListModel.message(for: error))
        }
    }

    // MARK: Dispatch

    private func dispatch(_ name: String, _ args: Arguments) async throws -> String {
        switch name {
        case "list_tasks": return listTasks(filter: args.string("filter") ?? "all")
        case "get_task": return Self.json(["task": Self.detail(try task(args.require("id")))])
        case "list_events": return try listEvents(from: args.day("from"), to: args.day("to"))
        case "list_calendars": return listCalendars()
        case "list_github_targets": return try await listGitHubTargets()
        case "list_assignees": return try await listAssignees(repository: args.require("repository"))
        case "list_shopping": return try await listShopping(includeCompleted: args.bool("include_completed") ?? false)
        case "update_shopping": return try await updateShopping(args)
        case "create_event": return try await createEvent(args)
        case "update_event": return try await updateEvent(args)
        case "delete_event": return try await deleteEvent(args)
        case "create_task": return try await createTask(args)
        case "update_task": return try await updateTask(args)
        case "reschedule_task":
            let task = try task(args.require("id"))
            let updated = try await taskList.rescheduleReturning(task.id, to: try args.due("due"))
            return Self.json(["ok": true, "task": Self.summary(updated)])
        case "complete_task":
            let task = try task(args.require("id"))
            _ = try await taskList.completeReturning(task.id)
            return Self.json(["ok": true, "completed": task.title])
        case "assign_to_day":
            let task = try task(args.require("id"))
            let day = try args.day("day")
            try planning.blocks.moveFutureBlocks(of: task.id, to: day, after: planning.now())
            planning.planStore.assign(task.id, to: day)
            await planning.reload()
            return Self.json(["ok": true, "task": task.title, "day": AIPlanner.dayString(day)])
        case "create_time_block": return try await createBlock(args)
        case "link_event_to_task":
            let task = try task(args.require("task_id"))
            await planning.link(eventID: try args.require("event_id"), to: task.id)
            return Self.json(["ok": true])
        case "set_day_hours": return try await setDayHours(args)
        case "set_lunch":
            let day = try args.day("day")
            let minutes = args.int("minutes") ?? 0
            if minutes <= 0 {
                await planning.removeLunch(on: day)
            } else {
                guard let start = args.string("start").flatMap(AIPlanner.minutes) else { throw ToolError(String(localized: "Die Uhrzeit fehlt.")) }
                await planning.setLunch(startMinutes: start, minutes: minutes, on: day)
            }
            return Self.json(["ok": true])
        case "mark_events_free": return try await markEventsFree(args)
        case "plan_period": return try await planPeriod(args)
        case "add_comment":
            let task = try task(args.require("id"))
            guard let provider = taskList.provider(for: task.id.source) else { throw ToolError(String(localized: "Die Quelle ist nicht verfügbar.")) }
            try await provider.addComment(try args.require("body"), to: task.id)
            return Self.json(["ok": true])
        default:
            throw ToolError(String(localized: "Unbekannte Funktion \(name)."))
        }
    }

    // MARK: Read

    private func listTasks(filter: String) -> String {
        let today = planning.today
        let assignments = planning.planStore.assignments(in: PlanDay(year: 1, month: 1, day: 1)...PlanDay(year: 9999, month: 12, day: 31))
        let open = taskList.items.filter { !$0.isCompleted }
        let filtered = open.filter { task in
            let due = task.due.map(PlanDay.init)
            switch filter {
            case "today": return due == today || assignments[task.id] == today
            case "overdue": return due.map { $0 < today } ?? false
            case "upcoming": return due.map { $0 > today } ?? false
            case "unplanned": return assignments[task.id] == nil
            default: return true
            }
        }
        let tasks = sortedTasks(filtered, calendar: planning.calendar).prefix(Self.maxListedTasks).map { task -> [String: Any] in
            var summary = Self.summary(task)
            if let day = assignments[task.id] { summary["plannedDay"] = AIPlanner.dayString(day) }
            return summary
        }
        return Self.json(["tasks": Array(tasks), "count": filtered.count])
    }

    private func listEvents(from: PlanDay, to: PlanDay) throws -> String {
        guard from <= to else { throw ToolError(String(localized: "Der Zeitraum ist ungültig.")) }
        let calendar = planning.calendar
        let interval = DateInterval(start: from.startDate(in: calendar), end: to.adding(days: 1, calendar: calendar).startDate(in: calendar))
        let found = events(interval)
        let deadlineIDs = planning.deadlineEventIDs(among: found)
        let list = found.sorted { $0.start < $1.start }.prefix(100).map { event -> [String: Any] in
            var item: [String: Any] = ["id": event.id, "title": event.title, "allDay": event.isAllDay, "busy": event.isBusy,
                                       "calendarId": event.calendarID, "editable": event.isEditable && !event.isInvitation,
                                       "recurring": event.isRecurring]
            if let name = planning.calendarTitle(event.calendarID) { item["calendar"] = name }
            if let location = event.location, !location.isEmpty { item["location"] = location }
            item["start"] = event.start.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            item["end"] = event.end.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            if let task = planning.linkedTask(eventID: event.id) { item["linkedTask"] = task.id.key }
            if deadlineIDs.contains(event.id) { item["deadline"] = true }
            return item
        }
        return Self.json(["events": Array(list)])
    }

    private func listCalendars() -> String {
        let writable = Set(planning.writableCalendars.map(\.id))
        let list = planning.eventCalendars.map { calendar -> [String: Any] in
            ["id": calendar.id, "title": calendar.title, "writable": writable.contains(calendar.id),
             "default": calendar.id == planning.defaultEventCalendarID]
        }
        return Self.json(["calendars": list])
    }

    // MARK: Write

    private func createEvent(_ args: Arguments) async throws -> String {
        let title = try args.require("title")
        let allDay = args.bool("all_day") ?? false
        let start = try moment(args.require("start"), allDay: allDay, end: false)
        let end = try moment(args.require("end"), allDay: allDay, end: true)
        let calendarID = try writableCalendar(args.string("calendar_id"))
        let draft = EventDraft(title: title, start: start, end: end, isAllDay: allDay, calendarID: calendarID,
                               notes: args.string("notes"), location: args.string("location"), url: nil)
        try Self.checkOrder(draft)
        let event = try await planning.createEventReportingErrors(draft)
        return Self.json(["ok": true, "id": event.id, "title": event.title])
    }

    private func updateEvent(_ args: Arguments) async throws -> String {
        let event = try editableEvent(args.require("event_id"))
        var draft = EventDraft(event)
        if let title = args.string("title") { draft.title = title }
        let allDay = args.bool("all_day") ?? event.isAllDay
        draft.isAllDay = allDay
        let length = event.end.timeIntervalSince(event.start)
        if let start = args.string("start") {
            draft.start = try moment(start, allDay: allDay, end: false)
            draft.end = draft.start.addingTimeInterval(length)
        }
        if let end = args.string("end") { draft.end = try moment(end, allDay: allDay, end: true) }
        if let calendarID = args.string("calendar_id") { draft.calendarID = try writableCalendar(calendarID) }
        if let location = args.string("location") { draft.location = location }
        if let notes = args.string("notes") { draft.notes = notes }
        try Self.checkOrder(draft)
        let span: EventSpan = args.bool("series") == true ? .futureEvents : .thisEvent
        let updated = try await planning.updateEventReportingErrors(event, with: draft, span: span)
        return Self.json(["ok": true, "id": updated.id, "title": updated.title])
    }

    private func deleteEvent(_ args: Arguments) async throws -> String {
        let event = try editableEvent(args.require("event_id"))
        let span: EventSpan = args.bool("series") == true ? .futureEvents : .thisEvent
        try await planning.deleteEventReportingErrors(event, span: span)
        return Self.json(["ok": true, "title": event.title])
    }

    private func editableEvent(_ id: String) throws -> CalendarEvent {
        guard let event = planning.event(id: id) else { throw ToolError(String(localized: "Diesen Termin gibt es nicht mehr.")) }
        guard event.isEditable, !event.isInvitation else { throw ToolError(String(localized: "Dieser Termin lässt sich nicht ändern.")) }
        return event
    }

    /// The given writable calendar, or the default one (plan calendar) when `id` is nil.
    private func writableCalendar(_ id: String?) throws -> String {
        guard let id else {
            guard let fallback = planning.defaultEventCalendarID ?? planning.writableCalendars.first?.id else {
                throw ToolError(String(localized: "Es gibt keinen beschreibbaren Kalender."))
            }
            return fallback
        }
        guard planning.writableCalendars.contains(where: { $0.id == id }) else {
            throw ToolError(String(localized: "In diesen Kalender kann Tagwerk nicht schreiben."))
        }
        return id
    }

    /// "YYYY-MM-DDTHH:mm", or "YYYY-MM-DD" for all-day events; an all-day end day counts inclusively.
    private func moment(_ text: String, allDay: Bool, end: Bool) throws -> Date {
        let parts = text.split(separator: "T")
        guard let day = parts.first.flatMap({ AIPlanner.planDay(String($0)) }) else { throw ToolError(String(localized: "Das Datum \(text) ist ungültig.")) }
        let calendar = planning.calendar
        if allDay { return (end ? day.adding(days: 1, calendar: calendar) : day).startDate(in: calendar) }
        guard parts.count == 2, let minutes = AIPlanner.minutes(String(parts[1])) else {
            throw ToolError(String(localized: "Die Uhrzeit fehlt bei \(text)."))
        }
        var components = DateComponents(year: day.year, month: day.month, day: day.day)
        components.hour = minutes / 60
        components.minute = minutes % 60
        guard let date = calendar.date(from: components) else { throw ToolError(String(localized: "Die Uhrzeit ist ungültig.")) }
        return date
    }

    private static func checkOrder(_ draft: EventDraft) throws {
        guard draft.end > draft.start else { throw ToolError(String(localized: "Das Ende liegt nicht nach dem Beginn.")) }
    }

    private func createTask(_ args: Arguments) async throws -> String {
        var draft = TaskDraft(title: try args.require("title"))
        draft.due = try args.due("due")
        draft.priority = args.priority("priority")
        draft.estimateMinutes = args.int("minutes")
        draft.notes = args.string("notes")
        let available = Set(TaskSource.allCases.filter { taskList.provider(for: $0) != nil })
        let source = args.string("source").flatMap(TaskSource.init(rawValue:))
            ?? (available.contains(.reminders) ? .reminders : .local)
        guard available.contains(source) else { throw ToolError(String(localized: "Diese Quelle ist nicht verfügbar.")) }
        let repository = args.string("repository"), projectIDs = args.optionalStrings("project_ids")
        let assignees = args.optionalStrings("assignees")
        if source == .github {
            return try await createIssue(draft, repository: repository, projectIDs: projectIDs, assignees: assignees)
        }
        guard repository == nil, projectIDs == nil, assignees == nil else {
            throw ToolError(String(localized: "Repository, Projects und Zugewiesene gibt es nur bei GitHub-Issues."))
        }
        let created = try await taskList.createReturning(draft, in: source)
        return Self.json(["ok": true, "id": created.id.key, "task": Self.summary(created)])
    }

    private func updateTask(_ args: Arguments) async throws -> String {
        let task = try task(args.require("id"))
        var edit = TaskEdit()
        if let title = args.string("title") { edit.title = .set(title) }
        if let notes = args.string("notes") { edit.notes = .set(notes) }
        if let priority = args.string("priority") { edit.priority = .set(Self.priority(priority)) }
        if let minutes = args.int("minutes") { edit.estimateMinutes = .set(minutes) }
        if args.string("due") != nil { edit.due = .set(try args.due("due")) }
        guard !edit.isEmpty else { throw ToolError(String(localized: "Es gibt nichts zu ändern.")) }
        let updated = try await taskList.applyReturning(edit, to: task.id)
        return Self.json(["ok": true, "task": Self.summary(updated)])
    }

    private func createBlock(_ args: Arguments) async throws -> String {
        let task = try task(args.require("id"))
        let day = try args.day("day")
        guard let start = args.string("start").flatMap(AIPlanner.minutes), let minutes = args.int("minutes"), minutes > 0 else {
            throw ToolError(String(localized: "Beginn oder Dauer fehlen."))
        }
        var components = DateComponents(year: day.year, month: day.month, day: day.day)
        components.hour = start / 60
        components.minute = start % 60
        guard let date = planning.calendar.date(from: components) else { throw ToolError(String(localized: "Die Uhrzeit ist ungültig.")) }
        try planning.blocks.createBlock(for: task, start: date, minutes: minutes)
        await planning.reload()
        return Self.json(["ok": true, "task": task.title, "day": AIPlanner.dayString(day), "start": AIPlanner.time(start)])
    }

    private func setDayHours(_ args: Arguments) async throws -> String {
        let day = try args.day("day")
        if args.bool("off") == true {
            planning.planStore.setOverride(.off, on: day)
        } else {
            guard let start = args.string("start").flatMap(AIPlanner.minutes), let end = args.string("end").flatMap(AIPlanner.minutes),
                  start < end else { throw ToolError(String(localized: "Beginn und Ende sind ungültig.")) }
            planning.planStore.setOverride(.hours(WorkHours(startMinutes: start, endMinutes: end)), on: day)
        }
        await planning.reload()
        return Self.json(["ok": true])
    }

    private func markEventsFree(_ args: Arguments) async throws -> String {
        let ids = Set(args.strings("event_ids"))
        guard !ids.isEmpty else { throw ToolError(String(localized: "Keine Termine angegeben.")) }
        let now = planning.now()
        let window = DateInterval(start: now.addingTimeInterval(-60 * 86_400), duration: 400 * 86_400)
        let matches = events(window).filter { ids.contains($0.id) }
        guard !matches.isEmpty else { throw ToolError(String(localized: "Diese Termine gibt es nicht.")) }
        await planning.setFree(matches, free: args.bool("free") ?? true, series: args.bool("series") ?? false)
        return Self.json(["ok": true, "count": matches.count])
    }

    private func planPeriod(_ args: Arguments) async throws -> String {
        guard let planner else { throw ToolError(String(localized: "Planen ist gerade nicht verfügbar.")) }
        guard let scope = args.string("scope").flatMap(PlanScope.init(rawValue:)) else { throw ToolError(String(localized: "Der Zeitraum fehlt.")) }
        let day = (try? args.day("day")) ?? planning.today
        await planner.plan(scope: scope, anchor: day)
        if case .failed(let message) = planner.state { throw ToolError(message) }
        if let notice = planner.notice, notice == AIPlanner.nothingToPlanMessage { throw ToolError(notice) }
        let batches = planning.suggestionBatches
        onPlanned?()
        return Self.json([
            "ok": true,
            "suggestions": batches.reduce(0) { $0 + $1.suggestions.count },
            "unscheduled": batches.reduce(0) { $0 + $1.unscheduled.count },
            "message": "Die Vorschläge stehen in der Planen-Ansicht und warten dort auf Bestätigung.",
        ])
    }

    // MARK: Helpers

    private func task(_ id: String) throws -> TaskItem {
        guard let task = taskList.items.first(where: { $0.id.key == id }) else { throw ToolError(String(localized: "Diese Aufgabe gibt es nicht.")) }
        return task
    }

    static func summary(_ task: TaskItem) -> [String: Any] {
        var item: [String: Any] = ["id": task.id.key, "title": task.title, "source": task.id.source.rawValue]
        if let due = task.due { item["due"] = dueString(due) }
        if let priority = task.priority { item["priority"] = priority.label }
        if let minutes = task.estimateMinutes { item["minutes"] = minutes }
        return item
    }

    static func detail(_ task: TaskItem) -> [String: Any] {
        var item = summary(task)
        item["container"] = task.container.name
        if let notes = task.notes, !notes.isEmpty { item["notes"] = notes }
        if let labels = task.labels, !labels.isEmpty { item["labels"] = labels }
        if let url = task.url { item["url"] = url.absoluteString }
        if let epic = task.epic { item["epic"] = "#\(epic.number) \(epic.title)" }
        return item
    }

    static func dueString(_ due: DueDate) -> String {
        let day = AIPlanner.dayString(PlanDay(due))
        guard let hour = due.hour else { return day }
        return day + "T" + AIPlanner.time(hour * 60 + (due.minute ?? 0))
    }

    nonisolated static func priority(_ label: String) -> Priority? {
        guard label.count == 2, label.first == "P", let value = Int(label.dropFirst()) else { return nil }
        return Priority(rawValue: value)
    }

    static func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func error(_ message: String) -> String { json(["error": message]) }

    struct ToolError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    /// Typed access to the decoded arguments; JSON `null` counts as missing.
    struct Arguments {
        let values: [String: Any]
        init(_ values: [String: Any]) { self.values = values }

        func string(_ key: String) -> String? {
            guard let value = values[key] as? String, !value.isEmpty else { return nil }
            return value
        }

        func require(_ key: String) throws -> String {
            guard let value = string(key) else { throw ToolError(String(localized: "Das Argument \(key) fehlt.")) }
            return value
        }

        func int(_ key: String) -> Int? { (values[key] as? NSNumber)?.intValue }
        func bool(_ key: String) -> Bool? { values[key] as? Bool }
        func strings(_ key: String) -> [String] { values[key] as? [String] ?? [] }
        /// `nil` for a missing or null value, so an empty list stays distinguishable.
        func optionalStrings(_ key: String) -> [String]? { values[key] as? [String] }
        func priority(_ key: String) -> Priority? { string(key).flatMap(AppTools.priority) }

        func day(_ key: String) throws -> PlanDay {
            guard let day = string(key).flatMap(AIPlanner.planDay) else { throw ToolError(String(localized: "Das Datum \(key) ist ungültig.")) }
            return day
        }

        /// "YYYY-MM-DD" or "YYYY-MM-DDTHH:mm"; missing means no due date.
        func due(_ key: String) throws -> DueDate? {
            guard let text = string(key) else { return nil }
            let parts = text.split(separator: "T")
            guard let day = AIPlanner.planDay(String(parts[0])) else { throw ToolError(String(localized: "Das Datum \(key) ist ungültig.")) }
            if parts.count == 2, let minutes = AIPlanner.minutes(String(parts[1])) {
                return DueDate(year: day.year, month: day.month, day: day.day, hour: minutes / 60, minute: minutes % 60)
            }
            return DueDate(year: day.year, month: day.month, day: day.day)
        }
    }
}
