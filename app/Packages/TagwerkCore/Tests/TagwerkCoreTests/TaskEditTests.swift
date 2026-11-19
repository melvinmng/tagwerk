import Foundation
import Testing
@testable import TagwerkCore

struct TaskEditTests {
    @Test func taskEdit_diff_onlyChangedFields() {
        let original = makeItem("Alt", due: DueDate(year: 2026, month: 11, day: 20), priority: .p2)
        var changed = original
        changed.title = "Neu"

        let edit = TaskEdit.diff(from: original, to: changed)

        guard case .set(let title) = edit.title else {
            Issue.record("title should be set")
            return
        }
        #expect(title == "Neu")
        #expect(edit.notes.isUnchanged)
        #expect(edit.due.isUnchanged)
        #expect(edit.priority.isUnchanged)
        #expect(edit.estimateMinutes.isUnchanged)
        #expect(edit.containerID.isUnchanged)
        #expect(edit.isCompleted.isUnchanged)
        #expect(!edit.isEmpty)
    }

    @Test func taskEdit_diff_identicalItems_isEmpty() {
        let item = makeItem("Gleich", priority: .p1)
        #expect(TaskEdit.diff(from: item, to: item).isEmpty)
    }

    @Test func taskEdit_diff_clearedDue_isSetToNil() {
        let original = makeItem("A", due: DueDate(year: 2026, month: 11, day: 20))
        var changed = original
        changed.due = nil
        guard case .set(let due) = TaskEdit.diff(from: original, to: changed).due else {
            Issue.record("due should be set")
            return
        }
        #expect(due == nil)
    }

    @Test func diff_assignees_setsDifference() {
        var original = makeItem("A", source: .github)
        original.assignees = ["octo"]
        var changed = original
        changed.assignees = ["octo", "lea-m"]

        let edit = TaskEdit.diff(from: original, to: changed)

        #expect(edit.assignees == .set(AssigneeChange(add: ["lea-m"], remove: [])))
        #expect(!edit.isEmpty)
    }

    @Test func diff_sameAssigneesInOtherOrder_isEmpty() {
        var original = makeItem("A", source: .github)
        original.assignees = ["octo", "lea-m"]
        var changed = original
        changed.assignees = ["Lea-M", "octo"]

        #expect(TaskEdit.diff(from: original, to: changed).isEmpty)
    }

    @Test func taskEdit_default_isEmpty() {
        #expect(TaskEdit().isEmpty)
    }

    @Test func priority_ordersP1First() {
        #expect(Priority.p1 < Priority.p2)
        #expect(Priority.allCases.map(\.label) == ["P1", "P2", "P3", "P4", "P5"])
    }
}

struct TaskEditLabelsTests {
    @Test func taskEdit_diff_labels() {
        var original = makeItem("A")
        original.labels = ["bug"]
        var changed = original
        changed.labels = ["bug", "ui"]
        #expect(TaskEdit.diff(from: original, to: changed).labels == .set(["bug", "ui"]))
        #expect(TaskEdit.diff(from: original, to: original).labels.isUnchanged)
    }

    @Test func taskItem_defaults_noSubContainersNoLabels() {
        let item = makeItem("A")
        #expect(item.subContainers.isEmpty)
        #expect(item.labels == nil)
        #expect(TaskEdit().targetSubContainerIDs == nil)
        #expect(TaskDraft(title: "x").subContainerIDs.isEmpty)
    }
}

struct TaskEditRecurrenceTests {
    let nov19 = PlanDay(year: 2026, month: 11, day: 19)
    let weeklyThursday = RecurrenceRule.weekly(interval: 1, weekdays: [5])

    private func item(_ recurrence: Recurrence?) -> TaskItem {
        var item = makeItem("Serie", due: DueDate(year: 2026, month: 11, day: 19), source: .reminders)
        item.recurrence = recurrence
        return item
    }

    @Test func defaults_noRecurrence() {
        #expect(makeItem("A").recurrence == nil)
        #expect(TaskDraft(title: "x").recurrence == nil)
        #expect(TaskEdit().recurrence.isUnchanged)
    }

    @Test func diff_setsRecurrence() {
        let original = item(nil)
        let edited = item(Recurrence(rule: weeklyThursday, start: nov19, end: nil, count: nil))
        #expect(TaskEdit.diff(from: original, to: edited).recurrence == .set(edited.recurrence))

        let longer = item(Recurrence(rule: weeklyThursday, start: nov19, end: nil, count: 5))
        #expect(TaskEdit.diff(from: edited, to: longer).recurrence == .set(longer.recurrence))
        let until = item(Recurrence(rule: weeklyThursday, start: nov19, end: PlanDay(year: 2027, month: 1, day: 1), count: nil))
        #expect(TaskEdit.diff(from: edited, to: until).recurrence == .set(until.recurrence))
    }

    @Test func diff_ignoresStartShift() {
        let original = item(Recurrence(rule: weeklyThursday, start: nov19, end: nil, count: nil))
        var edited = original
        edited.due = DueDate(year: 2026, month: 11, day: 26)
        edited.recurrence?.start = PlanDay(year: 2026, month: 11, day: 26)
        let edit = TaskEdit.diff(from: original, to: edited)
        #expect(edit.recurrence.isUnchanged)
        #expect(!edit.due.isUnchanged)
    }

    /// A rule Tagwerk cannot express must never be written just because the due date moved.
    @Test func diff_unsupportedRuleWithShiftedStart_staysUnchanged() {
        let original = item(Recurrence(rule: .unsupported, start: nov19, end: nil, count: nil))
        var edited = original
        edited.recurrence?.start = PlanDay(year: 2026, month: 11, day: 20)
        #expect(TaskEdit.diff(from: original, to: edited).recurrence.isUnchanged)
    }

    @Test func diff_clearsRecurrence() {
        let original = item(Recurrence(rule: weeklyThursday, start: nov19, end: nil, count: nil))
        #expect(TaskEdit.diff(from: original, to: item(nil)).recurrence == .set(nil))
    }

    @Test func isEmpty_falseWithRecurrence() {
        var edit = TaskEdit()
        edit.recurrence = .set(nil)
        #expect(!edit.isEmpty)
    }

    // MARK: Status per sub-container

    private func statusRow(_ id: String, current: String?, writable: Bool = true) -> SubContainerStatus {
        SubContainerStatus(subContainerID: id, subContainerName: "Projekt \(id)", current: current,
                           options: ["Backlog", "Ready", "Done"], isWritable: writable)
    }

    @Test func diff_status_setsChangedProjectOnly() {
        var original = makeItem("A", source: .github)
        original.statuses = [statusRow("P1", current: "Ready"), statusRow("P2", current: "Backlog")]
        var changed = original
        changed.statuses[1].current = "Done"

        let edit = TaskEdit.diff(from: original, to: changed)

        #expect(edit.statusChanges == ["P2": "Done"])
        #expect(!edit.isEmpty)
    }

    @Test func diff_status_unchanged_isEmpty() {
        var item = makeItem("A", source: .github)
        item.statuses = [statusRow("P1", current: "Ready")]
        #expect(TaskEdit.diff(from: item, to: item).statusChanges.isEmpty)
        #expect(TaskEdit.diff(from: item, to: item).isEmpty)
    }

    @Test func diff_status_clearedToNil_isNotAChange() {
        var original = makeItem("A", source: .github)
        original.statuses = [statusRow("P1", current: "Ready")]
        var changed = original
        changed.statuses[0].current = nil
        #expect(TaskEdit.diff(from: original, to: changed).statusChanges.isEmpty)
    }

    @Test func statusOnlyEdit_isNotEmpty() {
        var edit = TaskEdit()
        edit.statusChanges = ["P1": "Done"]
        #expect(!edit.isEmpty)
    }

    @Test func taskItem_defaultsHaveNoStatuses_andDraftHasNoStartStatus() {
        #expect(makeItem("A").statuses.isEmpty)
        #expect(TaskDraft(title: "A").startStatus == nil)
        #expect(TaskEdit().statusChanges.isEmpty)
    }
}
