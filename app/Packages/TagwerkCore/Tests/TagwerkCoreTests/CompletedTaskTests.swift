import Foundation
import Testing
@testable import TagwerkCore

@Suite struct CompletedTaskTests {
    private func completed(_ title: String, id: String, source: TaskSource = .reminders, list: String = "To Do",
                           at date: Date?) -> CompletedTask {
        var item = makeItem(title, source: source)
        item = TaskItem(id: TaskID(source: source, rawValue: id), title: title, notes: nil, due: nil, priority: nil,
                        estimateMinutes: nil, isCompleted: true,
                        container: TaskContainer(id: list, name: list, colorHex: nil), url: nil, version: "1",
                        editableFields: item.editableFields)
        return CompletedTask(item: item, completedAt: date)
    }

    @Test func latestFirstAndUndatedLast() {
        let tasks = [completed("a", id: "1", at: instant(2026, 11, 12)), completed("b", id: "2", at: nil),
                     completed("c", id: "3", at: instant(2026, 11, 18))]
        #expect(CompletedGrouping.groups(tasks).map(\.latest.item.title) == ["c", "a", "b"])
    }

    @Test func equalRemindersCollapseWithCounter() {
        let tasks = [completed("Müll rausbringen", id: "1", at: instant(2026, 11, 5)),
                     completed("Müll rausbringen", id: "2", at: instant(2026, 11, 12)),
                     completed("Müll rausbringen", id: "3", at: instant(2026, 11, 19)),
                     completed("Müll rausbringen", id: "4", list: "Haus", at: instant(2026, 11, 1))]
        let groups = CompletedGrouping.groups(tasks)
        #expect(groups.count == 2)
        #expect(groups[0].latest.completedAt == instant(2026, 11, 19))
        #expect(groups[0].moreCount == 2)
        #expect(groups[1].moreCount == 0)
    }

    @Test func localAndGitHubTasksNeverCollapse() {
        let tasks = [completed("Gleich", id: "1", source: .local, list: "local", at: instant(2026, 11, 5)),
                     completed("Gleich", id: "2", source: .local, list: "local", at: instant(2026, 11, 6))]
        #expect(CompletedGrouping.groups(tasks).count == 2)
    }
}
