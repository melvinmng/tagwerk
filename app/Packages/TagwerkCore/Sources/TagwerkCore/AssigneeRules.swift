import Foundation

/// People to add to and to remove from the assignees of a task, relative to the state the user saw.
public struct AssigneeChange: Sendable, Equatable {
    public var add: [String]
    public var remove: [String]

    public init(add: [String] = [], remove: [String] = []) {
        self.add = add
        self.remove = remove
    }
}

/// Pure rules for assignee logins. Logins are compared without case.
public enum AssigneeRules {
    /// Upper limit of assignees per GitHub issue.
    public static let maximum = 10

    /// Case-insensitive membership.
    public static func contains(_ logins: [String]?, _ login: String) -> Bool {
        let key = login.lowercased()
        return logins?.contains { $0.lowercased() == key } ?? false
    }

    /// Requested logins that are not in `actual`, in the order of `requested`; `[]` when `requested` is nil.
    public static func missing(requested: [String]?, actual: [String]?) -> [String] {
        (requested ?? []).filter { !contains(actual, $0) }
    }

    /// Set difference without case; `nil` when both sides hold the same logins.
    /// `add` keeps the order of `edited`, `remove` the order of `original`.
    public static func change(original: [String]?, edited: [String]?) -> AssigneeChange? {
        let add = (edited ?? []).filter { !contains(original, $0) }
        let remove = (original ?? []).filter { !contains(edited, $0) }
        return add.isEmpty && remove.isEmpty ? nil : AssigneeChange(add: add, remove: remove)
    }

    /// (current ∪ add) − remove, in the order of `current`, then `add`.
    public static func applying(_ change: AssigneeChange, to current: [String]) -> [String] {
        var result = current
        for login in change.add where !contains(result, login) {
            result.append(login)
        }
        return result.filter { !contains(change.remove, $0) }
    }

    /// Spelling of `login` as listed in `candidates`, or `nil` when it is not listed.
    public static func canonical(_ login: String, in candidates: [String]) -> String? {
        let key = login.lowercased()
        return candidates.first { $0.lowercased() == key }
    }
}
