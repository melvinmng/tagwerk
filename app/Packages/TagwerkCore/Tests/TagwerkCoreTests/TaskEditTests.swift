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
