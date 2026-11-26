import Foundation
import GitHubKit
import RemindersKit
import TagwerkCore

/// Turns what the sources deliver into the items the project progress counts.
enum ProjectFactsMapping {
    /// A GitHub issue. `loadedTaskKeys` are the tasks Tagwerk has loaded (`TaskID.key`); only those can be opened in the editor.
    static func fact(_ record: ProjectItemRecord, loadedTaskKeys: Set<String>) -> ProjectItemFact {
        let taskKey = TaskID(source: .github, rawValue: record.issueID).key
        return ProjectItemFact(
            id: record.issueID, title: record.title, number: record.number, createdAt: record.createdAt, closedAt: record.closedAt,
            state: record.state, due: record.due, status: record.status, assignees: record.assignees, url: record.url,
            openBlockedByCount: record.openBlockedByCount, openBlockingCount: record.openBlockingCount,
            taskKey: loadedTaskKeys.contains(taskKey) ? taskKey : nil, estimateMinutes: record.estimateMinutes)
    }

    /// A reminder. Completing a repeating reminder in the Reminders app moves it on, so it counts as one open item.
    /// `estimateMinutes` is the estimate set in Tagwerk (EventKit has no such field).
    static func fact(_ record: ReminderRecord, estimateMinutes: Int? = nil) -> ProjectItemFact {
        ProjectItemFact(id: record.id, title: record.title, createdAt: record.createdAt,
                        closedAt: record.isCompleted ? record.completedAt : nil, state: record.isCompleted ? .completed : .open,
                        due: record.due, taskKey: TaskID(source: .reminders, rawValue: record.id).key,
                        estimateMinutes: estimateMinutes)
    }

    /// A local task. Tasks completed before the weekly review stored the time have no completion date.
    static func fact(_ task: LocalTask) -> ProjectItemFact {
        ProjectItemFact(id: task.id.uuidString, title: task.title, createdAt: task.createdAt,
                        closedAt: task.isCompleted ? task.completedAt : nil, state: task.isCompleted ? .completed : .open,
                        due: task.due, taskKey: TaskID(source: .local, rawValue: task.id.uuidString).key,
                        estimateMinutes: task.estimateMinutes)
    }

    /// The task (`TaskID.key`) whose records belong to the item, open or closed. `taskKey` of a GitHub item is set only while Tagwerk has
    /// the issue loaded (to open the editor), but the focus time, the blocks and the activity log of an issue that was completed stay
    /// in the records, so the key is built from the issue ID, the same ID `GitHubMapping` gives the `TaskID`.
    static func recordKey(of kind: ProjectProgressReference.Kind, _ fact: ProjectItemFact) -> String? {
        switch kind {
        case .gitHubProject, .gitHubRepository: TaskID(source: .github, rawValue: fact.id).key
        case .remindersList, .local: fact.taskKey
        }
    }

    /// The tasks whose time belongs to the project: every item, open or closed.
    static func timeKeys(of kind: ProjectProgressReference.Kind, facts: [ProjectItemFact]) -> Set<String> {
        Set(facts.compactMap { recordKey(of: kind, $0) })
    }

    /// When each closed item of the project was completed or closed, by task key.
    static func closedDates(of kind: ProjectProgressReference.Kind, facts: [ProjectItemFact]) -> [String: Date] {
        var dates: [String: Date] = [:]
        for fact in facts {
            if let key = recordKey(of: kind, fact), let closedAt = fact.closedAt { dates[key] = closedAt }
        }
        return dates
    }

    /// The reason a failed GitHub request is shown with.
    static func failure(_ error: Error) -> ProjectLoadFailure {
        guard let error = error as? GitHubAPIError else { return .other }
        switch error {
        case .network: return .offline
        case .http(let status): return status == 403 || status == 429 ? .rateLimited : .other
        case .graphQL(let message): return message.localizedCaseInsensitiveContains("rate limit") ? .rateLimited : .other
        case .decoding, .invalidRepository: return .other
        }
    }
}
