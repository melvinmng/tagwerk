import AIKit
import Foundation

/// Strict JSON schemas of the assistant functions: every property is required, optional values are
/// nullable, no extra properties (`strict: true`, verified with ChatGPT on 2026-11-18).
extension AppTools {
    private typealias Schema = [String: Any]

    private static func object(_ properties: [String: Schema]) -> Schema {
        ["type": "object", "additionalProperties": false, "required": properties.keys.sorted(), "properties": properties]
    }

    private static func string(_ description: String? = nil, nullable: Bool = false) -> Schema {
        var schema: Schema = ["type": nullable ? ["string", "null"] : "string"]
        if let description { schema["description"] = description }
        return schema
    }

    private static func integer(nullable: Bool = false) -> Schema { ["type": nullable ? ["integer", "null"] : "integer"] }
    private static var boolean: Schema { ["type": "boolean"] }

    private static func enumeration(_ values: [String], nullable: Bool = false) -> Schema {
        ["type": nullable ? ["string", "null"] : "string", "enum": nullable ? values.map { $0 as Any } + [NSNull()] : values]
    }

    private static func tool(_ name: String, _ description: String, _ properties: [String: Schema]) -> ToolDefinition {
        let data = (try? JSONSerialization.data(withJSONObject: object(properties), options: [.sortedKeys])) ?? Data("{}".utf8)
        return ToolDefinition(name: name, description: description, parameters: data, strict: true)
    }

    private static func strings(_ description: String? = nil, nullable: Bool = false) -> Schema {
        var schema: Schema = ["type": nullable ? ["array", "null"] : "array", "items": ["type": "string"]]
        if let description { schema["description"] = description }
        return schema
    }

    /// Read tools for creating GitHub issues; only registered while GitHub is signed in.
    static var gitHubDefinitions: [ToolDefinition] {
        [
            tool("list_github_targets", "Lists the user's GitHub repositories (most recently pushed first) with the ids of their linked projects, and all projects with id and title. Call it before creating a GitHub issue.", [:]),
            tool("list_assignees", "Lists the people who can be assigned to issues of one repository: the user as me, everyone else as assignees (GitHub logins). Call it only when the user wants to assign an issue to someone.",
                 ["repository": string("owner/name from list_github_targets")]),
            tool("assign_task", "Changes who is assigned to an existing GitHub issue. add and remove hold GitHub logins: add only logins from list_assignees (or me), remove only logins currently assigned (see get_task). Removing the user hands the issue over: it leaves the user's tasks and its future time blocks are deleted. Needs confirmation.", [
                "id": taskID,
                "add": strings("Logins to assign additionally"),
                "remove": strings("Logins to unassign"),
            ]),
        ]
    }

    private static var taskID: Schema { string("Task id as listed, e.g. github:123 or local:…") }
    private static var day: Schema { string("YYYY-MM-DD") }
    private static var priorities: [String] { ["P1", "P2", "P3", "P4", "P5"] }

    static var allDefinitions: [ToolDefinition] {
        [
            tool("list_tasks", "Lists open tasks with id, title, source, due, priority, effort and planned day.",
                 ["filter": enumeration(["all", "today", "overdue", "upcoming", "unplanned"])]),
            tool("get_task", "Returns one task with notes, labels, container and link.", ["id": taskID]),
            tool("list_events", "Lists calendar events between two days (inclusive) with id, calendar, whether it is editable and recurring, and whether it is a deadline.",
                 ["from": day, "to": day]),
            tool("search", "Searches calendar events, tasks, notes and shopping items by text (title, notes, location, list or repository, labels, issue number). Events are searched in the calendars selected in the settings, by default from 6 months back to 12 months ahead; pass from/to for another period of at most 4 years. Use it instead of guessing periods with list_events. Notes come with a title and a short excerpt. Private notes (journal, Bible Study, dream log) are never included. Notes and shopping items are searched only with kind all.", [
                "query": string("Search text; every word must occur somewhere (at least 2 characters)"),
                "kind": enumeration(["all", "events", "tasks"]),
                "include_completed": boolean,
                "from": string("YYYY-MM-DD, first day of the events period; null for 6 months back", nullable: true),
                "to": string("YYYY-MM-DD, last day of the events period; null for 12 months ahead", nullable: true),
                "github_online": ["type": "boolean", "description": "true only when the user asks about GitHub issues that are not among their tasks (closed, unassigned, assigned to others) or when the local results do not answer the question; it sends the search text to GitHub"],
            ]),
            tool("list_calendars", "Lists the event calendars with id, title, whether they are writable and which one is the default for new events.", [:]),
            tool("list_shopping", "Lists the shopping list: open items with id, name, quantity and category; items completed in the last 7 days only when include_completed is true. Shopping items are not tasks and never appear in list_tasks.",
                 ["include_completed": boolean]),
            tool("update_shopping", "Adds items to the shopping list and checks items off. add: item names with an optional quantity such as \"2\" or \"500 g\"; an item that is already on the list is not added twice. check_off: item ids from list_shopping. At most 30 entries each. Needs confirmation.", [
                "add": ["type": "array", "items": object(["name": string(), "quantity": string(nullable: true)])],
                "check_off": strings("Item ids from list_shopping"),
            ]),
            tool("create_event", "Creates a calendar event. Without calendar_id it goes to the default (plan) calendar; use another writable calendar only when the user names it. Timed: YYYY-MM-DDTHH:mm; all day: YYYY-MM-DD with inclusive end day. Needs confirmation.", [
                "title": string(),
                "start": string("YYYY-MM-DDTHH:mm, or YYYY-MM-DD when all_day"),
                "end": string("YYYY-MM-DDTHH:mm, or YYYY-MM-DD (inclusive) when all_day"),
                "all_day": boolean,
                "calendar_id": string("Calendar id from list_calendars; null for the default", nullable: true),
                "location": string(nullable: true),
                "notes": string(nullable: true),
            ]),
            tool("update_event", "Changes a calendar event; null leaves a field unchanged, a new start without end keeps the duration. For recurring events ask the user whether only this occurrence or all future ones are meant, and pass that as series. Needs confirmation.", [
                "event_id": string(),
                "title": string(nullable: true),
                "start": string("YYYY-MM-DDTHH:mm or YYYY-MM-DD", nullable: true),
                "end": string("YYYY-MM-DDTHH:mm or YYYY-MM-DD (inclusive)", nullable: true),
                "all_day": ["type": ["boolean", "null"]],
                "calendar_id": string(nullable: true),
                "location": string(nullable: true),
                "notes": string(nullable: true),
                "series": boolean,
            ]),
            tool("delete_event", "Deletes a calendar event. For recurring events ask whether only this occurrence or all future ones are meant (series). Needs confirmation.",
                 ["event_id": string(), "series": boolean]),
            tool("create_task", "Creates a task. For GitHub issues call list_github_targets first and pass repository and project_ids ([] creates the issue without a Project; it then does not appear in the user's task lists); assignees only with logins from list_assignees, [] for no one, null for the user. For other sources the three GitHub fields must be null. Needs confirmation by the user.", [
                "title": string(),
                "due": string("YYYY-MM-DD or YYYY-MM-DDTHH:mm", nullable: true),
                "priority": enumeration(priorities, nullable: true),
                "minutes": integer(nullable: true),
                "notes": string(nullable: true),
                "source": enumeration(["reminders", "local", "github"], nullable: true),
                "repository": string("owner/name from list_github_targets; GitHub issues only", nullable: true),
                "project_ids": strings("Project ids from list_github_targets; [] means explicitly no Project; GitHub issues only", nullable: true),
                "assignees": strings("GitHub logins from list_assignees; [] assigns no one, null assigns the user", nullable: true),
            ]),
            tool("update_task", "Changes fields of a task; null leaves a field unchanged. Needs confirmation.", [
                "id": taskID,
                "title": string(nullable: true),
                "notes": string(nullable: true),
                "due": string("YYYY-MM-DD or YYYY-MM-DDTHH:mm", nullable: true),
                "priority": enumeration(priorities, nullable: true),
                "minutes": integer(nullable: true),
            ]),
            tool("reschedule_task", "Moves the due date of a task; null removes it. Needs confirmation.", [
                "id": taskID, "due": string("YYYY-MM-DD or YYYY-MM-DDTHH:mm", nullable: true),
            ]),
            tool("complete_task", "Marks a task as done. Needs confirmation.", ["id": taskID]),
            tool("assign_to_day", "Sets the work day of a task in Tagwerk (not its due date). Needs confirmation.",
                 ["id": taskID, "day": day]),
            tool("create_time_block", "Creates a time block for a task in the plan calendar. Needs confirmation.", [
                "id": taskID, "day": day, "start": string("HH:mm"), "minutes": integer(),
            ]),
            tool("link_event_to_task", "Links a calendar event to a task; use it also to suggest a link you noticed (same title, an issue number in the event). Needs confirmation.",
                 ["event_id": string(), "task_id": taskID]),
            tool("set_day_hours", "Sets the working hours of one day, or marks it off. Needs confirmation.", [
                "day": day, "start": string("HH:mm", nullable: true), "end": string("HH:mm", nullable: true), "off": boolean,
            ]),
            tool("set_lunch", "Moves the lunch break of one day; minutes 0 removes it. Needs confirmation.", [
                "day": day, "start": string("HH:mm", nullable: true), "minutes": integer(),
            ]),
            tool("mark_events_free", "Marks events as free (or busy again) in Tagwerk only. For recurring events ask the user whether only this day or all future occurrences are meant, and pass that as series. Needs confirmation.", [
                "event_ids": ["type": "array", "items": ["type": "string"]], "free": boolean, "series": boolean,
            ]),
            tool("plan_period", "Plans the day, week or month with suggestions that the user accepts in the planning view. Needs confirmation.", [
                "scope": enumeration(["day", "week", "month"]), "day": day,
            ]),
            tool("add_comment", "Adds a comment to a GitHub issue. Needs confirmation.", ["id": taskID, "body": string()]),
        ]
    }
}
