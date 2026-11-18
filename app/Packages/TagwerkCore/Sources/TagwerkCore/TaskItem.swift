import Foundation

/// Origin of a task.
public enum TaskSource: String, Sendable, Hashable, Codable, CaseIterable {
    case reminders, github, local
}

/// Stable identity of a task across reloads: the source plus the source's own identifier.
public struct TaskID: Sendable, Hashable, Codable {
    public let source: TaskSource
    public let rawValue: String

    /// Stable string form "<source>:<rawValue>" for storage and drag & drop.
    public var key: String { "\(source.rawValue):\(rawValue)" }

    public init?(key: String) {
        guard let separator = key.firstIndex(of: ":"),
              let source = TaskSource(rawValue: String(key[..<separator])) else { return nil }
        self.init(source: source, rawValue: String(key[key.index(after: separator)...]))
    }

    public init(source: TaskSource, rawValue: String) {
        self.source = source
        self.rawValue = rawValue
    }
}

/// Grouping a task belongs to, such as a reminder list, a repository or "Lokal".
public struct TaskContainer: Sendable, Hashable, Codable {
    public let id: String
    public let name: String
    public let colorHex: String?

    public init(id: String, name: String, colorHex: String?) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

/// Fields the editor can show and change. A source lists only the fields it supports.
public enum TaskField: Sendable, Hashable, Codable {
    case title, notes, due, priority, estimate, container, labels, recurrence
}

/// Source-independent view of a task.
public struct TaskItem: Identifiable, Sendable, Hashable {
    public let id: TaskID
    public var title: String
    public var notes: String?
    public var due: DueDate?
    public var priority: Priority?
    public var estimateMinutes: Int?
    public var isCompleted: Bool
    public var container: TaskContainer
    public var url: URL?
    /// Opaque change marker of the source, compared before every write.
    public var version: String
    public var editableFields: Set<TaskField>
    /// Secondary groupings, such as the GitHub Projects an issue belongs to.
    public var subContainers: [TaskContainer]
    /// Labels, for sources that have them (GitHub); `nil` otherwise.
    public var labels: [String]?
    /// Parent issue (GitHub sub-issues), used for epic deadlines.
    public var epic: EpicInfo?
    /// True for GitHub issues labelled `epic`.
    public var isEpic: Bool
    /// Repetition of the task (reminders only in stage 1); its `start` follows the due date.
    public var recurrence: Recurrence?

    public init(
        id: TaskID, title: String, notes: String?, due: DueDate?, priority: Priority?,
        estimateMinutes: Int?, isCompleted: Bool, container: TaskContainer, url: URL?,
        version: String, editableFields: Set<TaskField>,
        subContainers: [TaskContainer] = [], labels: [String]? = nil, epic: EpicInfo? = nil, isEpic: Bool = false,
        recurrence: Recurrence? = nil
    ) {
        self.recurrence = recurrence
        self.epic = epic
        self.isEpic = isEpic
        self.id = id
        self.title = title
        self.notes = notes
        self.due = due
        self.priority = priority
        self.estimateMinutes = estimateMinutes
        self.isCompleted = isCompleted
        self.container = container
        self.url = url
        self.version = version
        self.editableFields = editableFields
        self.subContainers = subContainers
        self.labels = labels
    }
}

/// Input for creating a task in a source.
public struct TaskDraft: Sendable, Hashable {
    public var title: String
    public var notes: String?
    public var due: DueDate?
    public var priority: Priority?
    public var estimateMinutes: Int?
    /// Target container; `nil` lets the source pick its default.
    public var containerID: String?
    /// Secondary targets, such as the GitHub Projects of a new issue.
    public var subContainerIDs: [String]
    /// Repetition of the new task; requires a due date.
    public var recurrence: Recurrence?

    public init(title: String, notes: String? = nil, due: DueDate? = nil, priority: Priority? = nil,
                estimateMinutes: Int? = nil, containerID: String? = nil, subContainerIDs: [String] = [],
                recurrence: Recurrence? = nil) {
        self.recurrence = recurrence
        self.subContainerIDs = subContainerIDs
        self.title = title
        self.notes = notes
        self.due = due
        self.priority = priority
        self.estimateMinutes = estimateMinutes
        self.containerID = containerID
    }
}
