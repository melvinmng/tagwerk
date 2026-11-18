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

    private static var taskID: Schema { string("Task id as listed, e.g. github:123 or local:…") }
    private static var day: Schema { string("YYYY-MM-DD") }
    private static var priorities: [String] { ["P1", "P2", "P3", "P4", "P5"] }

    static var allDefinitions: [ToolDefinition] {
        [
            tool("list_tasks", "Lists open tasks with id, title, source, due, priority, effort and planned day.",
                 ["filter": enumeration(["all", "today", "overdue", "upcoming", "unplanned"])]),
            tool("get_task", "Returns one task with notes, labels, container and link.", ["id": taskID]),
            tool("list_events", "Lists calendar events between two days (inclusive).", ["from": day, "to": day]),
            tool("create_task", "Creates a task. Needs confirmation by the user.", [
                "title": string(),
                "due": string("YYYY-MM-DD or YYYY-MM-DDTHH:mm", nullable: true),
                "priority": enumeration(priorities, nullable: true),
                "minutes": integer(nullable: true),
                "notes": string(nullable: true),
                "source": enumeration(["reminders", "local", "github"], nullable: true),
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
            tool("link_event_to_task", "Links a calendar event to a task. Needs confirmation.",
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
