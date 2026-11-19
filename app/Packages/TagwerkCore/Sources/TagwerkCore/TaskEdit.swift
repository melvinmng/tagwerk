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
    /// Written only when `.set`; `.set(nil)` removes the repetition. Sources never rewrite an unchanged rule.
    public var recurrence: FieldChange<Recurrence?> = .unchanged
    /// Always a difference against the state the user saw, never a target list.
    public var assignees: FieldChange<AssigneeChange> = .unchanged
    /// Sub-containers (e.g. GitHub Projects) that field changes apply to; `nil` means all.
    public var targetSubContainerIDs: Set<String>? = nil
    /// New stage per sub-container ID (GitHub: Project ID to option name). Independent of
    /// `targetSubContainerIDs`, because a status is always set per sub-container.
    public var statusChanges: [String: String] = [:]

    public init() {}

    public var isEmpty: Bool {
        title.isUnchanged && notes.isUnchanged && due.isUnchanged && priority.isUnchanged
            && estimateMinutes.isUnchanged && containerID.isUnchanged && isCompleted.isUnchanged
            && labels.isUnchanged && recurrence.isUnchanged && assignees.isUnchanged && statusChanges.isEmpty
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
        if !sameSeries(original.recurrence, edited.recurrence) { edit.recurrence = .set(edited.recurrence) }
        if let change = AssigneeRules.change(original: original.assignees, edited: edited.assignees) {
            edit.assignees = .set(change)
        }
        for edited in edited.statuses {
            guard let current = edited.current,
                  let before = original.statuses.first(where: { $0.subContainerID == edited.subContainerID }),
                  before.current != current else { continue }
            edit.statusChanges[edited.subContainerID] = current
        }
        return edit
    }

    /// Compares rule, end and count but not `start`: the start follows the due date, and comparing it
    /// would rewrite (and, for unreadable rules, destroy) a rule whenever only the due date moved.
    private static func sameSeries(_ lhs: Recurrence?, _ rhs: Recurrence?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (lhs?, rhs?): lhs.rule == rhs.rule && lhs.end == rhs.end && lhs.count == rhs.count
        default: false
        }
    }
}
