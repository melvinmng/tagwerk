import Foundation

/// A completed task together with its completion moment, which `TaskItem` does not carry.
public struct CompletedTask: Sendable, Hashable, Identifiable {
    public var id: TaskID { item.id }
    public let item: TaskItem
    public let completedAt: Date?

    public init(item: TaskItem, completedAt: Date?) {
        self.item = item
        self.completedAt = completedAt
    }
}

/// One row of completed tasks: the latest one and the number of equal ones behind it.
public struct CompletedGroup: Sendable, Hashable, Identifiable {
    public var id: TaskID { latest.id }
    public let latest: CompletedTask
    /// Further completed reminders with the same title and list.
    public let moreCount: Int

    public init(latest: CompletedTask, moreCount: Int = 0) {
        self.latest = latest
        self.moreCount = moreCount
    }
}

public enum CompletedGrouping {
    private struct Key: Hashable {
        let title: String
        let containerID: String
    }

    /// Latest first, tasks without a completion date last; reminders with equal title and container collapse.
    public static func groups(_ tasks: [CompletedTask]) -> [CompletedGroup] {
        let sorted = tasks.sorted { first, second in
            switch (first.completedAt, second.completedAt) {
            case let (a?, b?): a > b
            case (_?, nil): true
            default: false
            }
        }
        var positions: [Key: Int] = [:]
        var result: [(latest: CompletedTask, more: Int)] = []
        for task in sorted {
            guard task.item.id.source == .reminders else {
                result.append((task, 0))
                continue
            }
            let key = Key(title: task.item.title, containerID: task.item.container.id)
            if let position = positions[key] {
                result[position].more += 1
            } else {
                positions[key] = result.count
                result.append((task, 0))
            }
        }
        return result.map { CompletedGroup(latest: $0.latest, moreCount: $0.more) }
    }
}
