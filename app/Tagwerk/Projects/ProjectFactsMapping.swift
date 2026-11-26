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
            taskKey: loadedTaskKeys.contains(taskKey) ? taskKey : nil)
    }

    /// A reminder. Completing a repeating reminder in the Reminders app moves it on, so it counts as one open item.
    static func fact(_ record: ReminderRecord) -> ProjectItemFact {
        ProjectItemFact(id: record.id, title: record.title, createdAt: record.createdAt,
                        closedAt: record.isCompleted ? record.completedAt : nil, state: record.isCompleted ? .completed : .open,
                        due: record.due, taskKey: TaskID(source: .reminders, rawValue: record.id).key)
    }

    /// A local task. Tasks completed before the weekly review stored the time have no completion date.
    static func fact(_ task: LocalTask) -> ProjectItemFact {
        ProjectItemFact(id: task.id.uuidString, title: task.title, createdAt: task.createdAt,
                        closedAt: task.isCompleted ? task.completedAt : nil, state: task.isCompleted ? .completed : .open,
                        due: task.due, taskKey: TaskID(source: .local, rawValue: task.id.uuidString).key)
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
