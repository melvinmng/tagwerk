import Foundation
import Testing
import TagwerkCore
import GitHubKit
@testable import Tagwerk

/// The spoken text of a task row: one element with title, due date, repeat, priority and list.
@MainActor
struct TaskRowTextTests {
    let calendar = testCalendar()
    let now = testNow()   // Wed 2026-11-18 10:00

    private func item(due: DueDate?, priority: Priority?) -> TaskItem {
        TaskItem(id: TaskID(source: .reminders, rawValue: "r1"), title: "Bericht", notes: nil, due: due, priority: priority,
                 estimateMinutes: nil, isCompleted: false, container: TaskContainer(id: "l1", name: "Uni", colorHex: nil),
                 url: nil, version: "1", editableFields: [])
    }

    @Test func fullRow_readsTitleDueRepeatPriorityAndList() {
        let text = TaskRowText.accessibilityLabel(item: item(due: DueDate(year: 2026, month: 11, day: 18), priority: .p2),
                                                  isRecurring: true, now: now, calendar: calendar)
        #expect(text == "Bericht, fällig heute, wiederkehrend, Priorität 2, Uni")
    }

    @Test func plainRow_readsTitleAndListOnly() {
        let text = TaskRowText.accessibilityLabel(item: item(due: nil, priority: nil), isRecurring: false, now: now, calendar: calendar)
        #expect(text == "Bericht, Uni")
    }

    @Test func dueDate_isSpelledWithTheDayWord() {
        let tomorrow = TaskRowText.accessibilityLabel(item: item(due: DueDate(year: 2026, month: 11, day: 19), priority: nil),
                                                      isRecurring: false, now: now, calendar: calendar)
        #expect(tomorrow == "Bericht, fällig morgen, Uni")
    }

    private func issue(statuses: [SubContainerStatus], source: TaskSource = .github) -> TaskItem {
        TaskItem(id: TaskID(source: source, rawValue: "I_1"), title: "Bericht", notes: nil, due: nil, priority: nil,
                 estimateMinutes: nil, isCompleted: false, container: TaskContainer(id: "beispiel/app", name: "beispiel/app", colorHex: nil),
                 url: nil, version: "1", editableFields: [], statuses: statuses)
    }

    private func stage(_ current: String, project: String = "Tagwerk", options: [String] = ["Backlog", "Ready", "In Progress", "In Review", "Done"]) -> SubContainerStatus {
        SubContainerStatus(subContainerID: "PVT_\(project)", subContainerName: project, current: current, options: options, isWritable: true)
    }

    @Test func accessibilityLabel_namesTheStatus() {
        let one = TaskRowText.accessibilityLabel(item: issue(statuses: [stage("In Progress")]), isRecurring: false, now: now, calendar: calendar)
        #expect(one == "Bericht, beispiel/app, Status In Progress")
        let several = TaskRowText.accessibilityLabel(
            item: issue(statuses: [stage("In Progress", project: "A"), stage("In Review", project: "B")]),
            isRecurring: false, now: now, calendar: calendar)
        #expect(several == "Bericht, beispiel/app, 2 Status")
    }

    @Test func accessibilityLabel_startStageHasNoStatus() {
        let text = TaskRowText.accessibilityLabel(item: issue(statuses: [stage("Ready")]), isRecurring: false, now: now, calendar: calendar)
        #expect(text == "Bericht, beispiel/app")
    }

    @Test func accessibilityLabel_localTask_hasNoStatus() {
        let text = TaskRowText.accessibilityLabel(item: issue(statuses: [stage("In Progress")], source: .local), isRecurring: false,
                                                  now: now, calendar: calendar)
        #expect(text == "Bericht, beispiel/app")
    }

    @Test func statusText_isTheStageOrTheCount() {
        #expect(TaskRowText.statusText(.stage("In Progress")) == "In Progress")
        #expect(TaskRowText.statusText(.several(3)) == "3 Status")
    }
}
