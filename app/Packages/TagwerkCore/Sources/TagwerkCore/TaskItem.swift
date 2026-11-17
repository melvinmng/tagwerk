import Foundation

/// Origin of a task.
public enum TaskSource: String, Sendable, Hashable, Codable, CaseIterable {
    case reminders, github, local
}

/// Stable identity of a task across reloads: the source plus the source's own identifier.
public struct TaskID: Sendable, Hashable, Codable {
    public let source: TaskSource
    public let rawValue: String

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
    case title, notes, due, priority, estimate, container
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

    public init(
        id: TaskID, title: String, notes: String?, due: DueDate?, priority: Priority?,
        estimateMinutes: Int?, isCompleted: Bool, container: TaskContainer, url: URL?,
        version: String, editableFields: Set<TaskField>
    ) {
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

    public init(title: String, notes: String? = nil, due: DueDate? = nil, priority: Priority? = nil,
                estimateMinutes: Int? = nil, containerID: String? = nil) {
        self.title = title
        self.notes = notes
        self.due = due
        self.priority = priority
        self.estimateMinutes = estimateMinutes
        self.containerID = containerID
    }
}
