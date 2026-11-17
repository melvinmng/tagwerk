/// A field in an edit: either left alone or set to a new value (which may be `nil` to clear it).
public enum FieldChange<Value: Sendable>: Sendable {
    case unchanged
    case set(Value)

    public var isUnchanged: Bool {
        if case .unchanged = self { return true }
        return false
    }
}

extension FieldChange: Equatable where Value: Equatable {}

/// The fields a user changed. Sources write only fields that are `.set`.
public struct TaskEdit: Sendable, Equatable {
    public var title: FieldChange<String> = .unchanged
    public var notes: FieldChange<String?> = .unchanged
    public var due: FieldChange<DueDate?> = .unchanged
    public var priority: FieldChange<Priority?> = .unchanged
    public var estimateMinutes: FieldChange<Int?> = .unchanged
    public var containerID: FieldChange<String> = .unchanged
    public var isCompleted: FieldChange<Bool> = .unchanged
    public var labels: FieldChange<[String]> = .unchanged
    /// Sub-containers (e.g. GitHub Projects) that field changes apply to; `nil` means all.
    public var targetSubContainerIDs: Set<String>? = nil

    public init() {}

    public var isEmpty: Bool {
        title.isUnchanged && notes.isUnchanged && due.isUnchanged && priority.isUnchanged
            && estimateMinutes.isUnchanged && containerID.isUnchanged && isCompleted.isUnchanged
            && labels.isUnchanged
    }

    /// Builds an edit that sets exactly the fields in which `edited` differs from `original`.
    public static func diff(from original: TaskItem, to edited: TaskItem) -> TaskEdit {
        var edit = TaskEdit()
        if edited.title != original.title { edit.title = .set(edited.title) }
        if edited.notes != original.notes { edit.notes = .set(edited.notes) }
        if edited.due != original.due { edit.due = .set(edited.due) }
        if edited.priority != original.priority { edit.priority = .set(edited.priority) }
        if edited.estimateMinutes != original.estimateMinutes { edit.estimateMinutes = .set(edited.estimateMinutes) }
        if edited.container.id != original.container.id { edit.containerID = .set(edited.container.id) }
        if edited.isCompleted != original.isCompleted { edit.isCompleted = .set(edited.isCompleted) }
        if edited.labels != original.labels { edit.labels = .set(edited.labels ?? []) }
        return edit
    }
}
