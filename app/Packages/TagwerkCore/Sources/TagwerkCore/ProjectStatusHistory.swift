import Foundation

/// Time a project's items spent in one Status (GitHub Project column), from the changes the user made through Tagwerk.
public struct ProjectStatusDuration: Sendable, Hashable, Identifiable {
    public var status: String
    public var seconds: TimeInterval
    /// Tasks that spent time in the status inside the period.
    public var taskCount: Int
    public var id: String { status }

    public init(status: String, seconds: TimeInterval, taskCount: Int) {
        self.status = status
        self.seconds = seconds
        self.taskCount = taskCount
    }
}

/// How often items moved from one Status to another.
public struct ProjectStatusTransition: Sendable, Hashable, Identifiable {
    public var from: String
    public var to: String
    public var count: Int
    public var id: String { from + "\u{1F}" + to }

    public init(from: String, to: String, count: Int) {
        self.from = from
        self.to = to
        self.count = count
    }
}

/// The evaluation of the local activity log for one project (#332, stage 3).
///
/// GitHub and Reminders keep no history of status changes or reschedules, so everything here covers only the changes the user made
/// through Tagwerk on this device since the log was introduced. `loggedSince` carries that start so the page can say it.
public struct ProjectStatusHistory: Sendable, Hashable {
    /// Time per Status, longest first. Only the stretches between two logged changes count (and from the last change until the item
    /// was completed or closed, or until now while it is open): the time before the first logged change of an item is unknown.
    public var durations: [ProjectStatusDuration]
    /// Moves from one Status to another inside the period, most frequent first.
    public var transitions: [ProjectStatusTransition]
    /// Status changes inside the period.
    public var statusChanges: Int
    /// Items that were reopened, and how often in total.
    public var reopenCount: Int
    public var reopenedTasks: Int
    /// Changes of the due date and of the planned work day ("Planen") inside the period, and the tasks they touched.
    public var dueDateChanges: Int
    public var planDayChanges: Int
    public var rescheduledTasks: Int
    /// The first entry of the whole log (any project); `nil` while the log is empty.
    public var loggedSince: Date?

    public var rescheduleCount: Int { dueDateChanges + planDayChanges }
    /// The log has nothing for this project in the period.
    public var isEmpty: Bool { statusChanges == 0 && reopenCount == 0 && rescheduleCount == 0 }
}

/// The pure evaluation of the activity log of a project.
public enum ProjectStatusHistoryRules {
    /// - Parameters:
    ///   - entries: the activity log (any project); entries of other projects are ignored.
    ///   - projectKey: `ProjectProgressReference.key` of the project.
    ///   - range: the period; counts include only entries inside it, durations are cut to it.
    ///   - closedAt: when each closed task of the project was completed or closed (`TaskID.key` → date), so a task that was closed
    ///     outside Tagwerk stops spending time in its last Status.
    ///   - now: the end of an open stretch.
    public static func make(entries: [TaskActivityEntry], projectKey: String, range: ProjectRange, closedAt: [String: Date],
                            now: Date) -> ProjectStatusHistory {
        let loggedSince = entries.map(\.occurredAt).min()
        let own = entries.filter { $0.projectKeys.contains(projectKey) }.sorted { ($0.occurredAt, $0.taskKey) < ($1.occurredAt, $1.taskKey) }
        let inRange = own.filter { range.contains($0.occurredAt) }

        var transitionCounts: [String: ProjectStatusTransition] = [:]
        for entry in inRange where entry.kind == .statusChanged {
            guard let from = entry.from, let to = entry.to else { continue }
            let key = ProjectStatusTransition(from: from, to: to, count: 0).id
            transitionCounts[key, default: ProjectStatusTransition(from: from, to: to, count: 0)].count += 1
        }
        let transitions = transitionCounts.values.sorted { lhs, rhs in
            lhs.count != rhs.count ? lhs.count > rhs.count : (lhs.from, lhs.to) < (rhs.from, rhs.to)
        }

        let reopened = inRange.filter { $0.kind == .reopened }
        let dueChanges = inRange.filter { $0.kind == .rescheduled }
        let planChanges = inRange.filter { $0.kind == .replanned }

        // Time per Status: for each task the stretch from a change to the next change, the completion of the task, or now.
        var seconds: [String: TimeInterval] = [:]
        var tasksPerStatus: [String: Set<String>] = [:]
        for (taskKey, taskEntries) in Dictionary(grouping: own, by: \.taskKey) {
            let changes = taskEntries.filter { $0.kind == .statusChanged && $0.to != nil }
            for (index, change) in changes.enumerated() {
                guard let status = change.to else { continue }
                var end = now
                if index + 1 < changes.count { end = min(end, changes[index + 1].occurredAt) }
                if let completion = taskEntries.first(where: { $0.kind == .completed && $0.occurredAt >= change.occurredAt }) {
                    end = min(end, completion.occurredAt)
                }
                if let closed = closedAt[taskKey], closed >= change.occurredAt { end = min(end, closed) }
                let start = max(change.occurredAt, range.start), stop = min(end, range.end)
                guard stop > start else { continue }
                seconds[status, default: 0] += stop.timeIntervalSince(start)
                tasksPerStatus[status, default: []].insert(taskKey)
            }
        }
        let durations = seconds.map { ProjectStatusDuration(status: $0.key, seconds: $0.value, taskCount: tasksPerStatus[$0.key]?.count ?? 0) }
            .sorted { lhs, rhs in lhs.seconds != rhs.seconds ? lhs.seconds > rhs.seconds : lhs.status < rhs.status }

        return ProjectStatusHistory(
            durations: durations, transitions: transitions,
            statusChanges: inRange.filter { $0.kind == .statusChanged }.count,
            reopenCount: reopened.count, reopenedTasks: Set(reopened.map(\.taskKey)).count,
            dueDateChanges: dueChanges.count, planDayChanges: planChanges.count,
            rescheduledTasks: Set((dueChanges + planChanges).map(\.taskKey)).count, loggedSince: loggedSince)
    }
}
