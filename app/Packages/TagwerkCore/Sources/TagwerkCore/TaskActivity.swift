import Foundation

/// What happened to a task in Tagwerk (#332, local activity log).
public enum TaskActivityKind: String, Sendable, Hashable, Codable, CaseIterable {
    case created
    case completed
    case reopened
    case statusChanged
    case rescheduled
}

/// One entry of the local activity log: a change the user made to a task through Tagwerk. GitHub and Reminders keep no history of
/// status changes or reschedules, so the log starts when it was introduced and only knows changes made on this device.
public struct TaskActivityEntry: Sendable, Hashable {
    public var kind: TaskActivityKind
    /// `TaskID.key` of the task.
    public var taskKey: String
    public var title: String
    /// Before and after of a status change (the stage) or a reschedule ("yyyy-MM-dd" or "yyyy-MM-dd HH:mm"; `nil` for no due date).
    public var from: String?
    public var to: String?
    /// `ProjectProgressReference.key` of the projects the entry belongs to, at the time of the change. A status change belongs to the
    /// one project whose status changed.
    public var projectKeys: [String]
    public var occurredAt: Date

    public init(kind: TaskActivityKind, taskKey: String, title: String, from: String? = nil, to: String? = nil,
                projectKeys: [String], occurredAt: Date) {
        self.kind = kind
        self.taskKey = taskKey
        self.title = title
        self.from = from
        self.to = to
        self.projectKeys = projectKeys
        self.occurredAt = occurredAt
    }
}

/// Derives log entries from the two states of a task.
public enum TaskActivityRules {
    /// The entry of a task that was just created.
    public static func created(_ item: TaskItem, at date: Date) -> TaskActivityEntry {
        TaskActivityEntry(kind: .created, taskKey: item.id.key, title: item.title, projectKeys: ProjectProgressReference.keys(of: item),
                          occurredAt: date)
    }

    /// What changed between `before` and `after` of the same task: completion or reopening, status per project, due date. `before == nil`
    /// (the earlier state is unknown) gives nothing.
    public static func entries(before: TaskItem?, after: TaskItem, at date: Date) -> [TaskActivityEntry] {
        guard let before, before.id == after.id else { return [] }
        let projectKeys = ProjectProgressReference.keys(of: after)
        var entries: [TaskActivityEntry] = []
        func entry(_ kind: TaskActivityKind, from: String? = nil, to: String? = nil, keys: [String]? = nil) -> TaskActivityEntry {
            TaskActivityEntry(kind: kind, taskKey: after.id.key, title: after.title, from: from, to: to,
                              projectKeys: keys ?? projectKeys, occurredAt: date)
        }
        if before.isCompleted != after.isCompleted {
            entries.append(entry(after.isCompleted ? .completed : .reopened))
        }
        for status in after.statuses {
            guard let previous = before.statuses.first(where: { $0.subContainerID == status.subContainerID }),
                  previous.current != status.current else { continue }
            entries.append(entry(.statusChanged, from: previous.current, to: status.current,
                                 keys: ["\(ProjectProgressReference.Kind.gitHubProject.rawValue):\(status.subContainerID)"]))
        }
        if before.due != after.due {
            entries.append(entry(.rescheduled, from: before.due.map(dueText), to: after.due.map(dueText)))
        }
        return entries
    }

    /// "2026-11-25" or "2026-11-25 14:30"; independent of the locale, so the log stays readable after a language change.
    public static func dueText(_ due: DueDate) -> String {
        let day = String(format: "%04d-%02d-%02d", due.year, due.month, due.day)
        guard let hour = due.hour else { return day }
        return day + String(format: " %02d:%02d", hour, due.minute ?? 0)
    }
}
