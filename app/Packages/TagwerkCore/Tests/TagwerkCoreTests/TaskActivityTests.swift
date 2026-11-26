import Foundation
import Testing
@testable import TagwerkCore

struct TaskActivityTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func task(source: TaskSource = .github, completed: Bool = false, due: DueDate? = nil, status: String? = "Ready",
                      projects: [String] = ["PVT_1"]) -> TaskItem {
        TaskItem(
            id: TaskID(source: source, rawValue: "I_1"), title: "Task", notes: nil, due: due, priority: nil, estimateMinutes: nil,
            isCompleted: completed, container: TaskContainer(id: source == .github ? "octo/repo" : "list-1", name: "Container", colorHex: nil),
            url: nil, version: "1", editableFields: [],
            subContainers: projects.map { TaskContainer(id: $0, name: $0, colorHex: nil) },
            statuses: projects.map { SubContainerStatus(subContainerID: $0, subContainerName: $0, current: status, options: [], isWritable: true) })
    }

    @Test func keys_ofAGitHubIssueAreRepositoryAndProjects() {
        #expect(ProjectProgressReference.keys(of: task(projects: ["PVT_1", "PVT_2"]))
                == ["gitHubRepository:octo/repo", "gitHubProject:PVT_1", "gitHubProject:PVT_2"])
    }

    @Test func keys_ofReminderAndLocalTasks() {
        #expect(ProjectProgressReference.keys(of: task(source: .reminders, projects: [])) == ["remindersList:list-1"])
        #expect(ProjectProgressReference.keys(of: task(source: .local, projects: [])) == ["local:local"])
    }

    @Test func entries_completionAndReopening() {
        let open = task(), done = task(completed: true)
        #expect(TaskActivityRules.entries(before: open, after: done, at: now).map(\.kind) == [.completed])
        #expect(TaskActivityRules.entries(before: done, after: open, at: now).map(\.kind) == [.reopened])
    }

    @Test func entries_statusChangeBelongsToTheChangedProjectOnly() {
        let entries = TaskActivityRules.entries(before: task(status: "Ready", projects: ["PVT_1", "PVT_2"]),
                                                after: task(status: "In progress", projects: ["PVT_1", "PVT_2"]), at: now)
        #expect(entries.map(\.kind) == [.statusChanged, .statusChanged])
        #expect(entries[0].from == "Ready" && entries[0].to == "In progress")
        #expect(entries[0].projectKeys == ["gitHubProject:PVT_1"])
        #expect(entries[1].projectKeys == ["gitHubProject:PVT_2"])
    }

    @Test func entries_rescheduleKeepsBeforeAndAfterAsText() {
        let entries = TaskActivityRules.entries(
            before: task(due: DueDate(year: 2026, month: 11, day: 25)),
            after: task(due: DueDate(year: 2026, month: 11, day: 27, hour: 9, minute: 5)), at: now)
        #expect(entries.map(\.kind) == [.rescheduled])
        #expect(entries[0].from == "2026-11-25")
        #expect(entries[0].to == "2026-11-27 09:05")
        #expect(entries[0].occurredAt == now)
    }

    @Test func entries_removingTheDueDateHasNoTarget() {
        let entries = TaskActivityRules.entries(before: task(due: DueDate(year: 2026, month: 11, day: 25)), after: task(), at: now)
        #expect(entries.first?.to == nil)
    }

    @Test func entries_withoutChangeOrWithoutEarlierStateAreEmpty() {
        #expect(TaskActivityRules.entries(before: task(), after: task(), at: now).isEmpty)
        #expect(TaskActivityRules.entries(before: nil, after: task(), at: now).isEmpty)
    }

    @Test func entries_severalChangesAtOnce() {
        let entries = TaskActivityRules.entries(before: task(status: "Ready"), after: task(completed: true, due: DueDate(year: 2026, month: 12, day: 1), status: "Done"), at: now)
        #expect(entries.map(\.kind) == [.completed, .statusChanged, .rescheduled])
    }

    @Test func created_carriesTheProjects() {
        let entry = TaskActivityRules.created(task(), at: now)
        #expect(entry.kind == .created)
        #expect(entry.projectKeys == ["gitHubRepository:octo/repo", "gitHubProject:PVT_1"])
    }
}
