import Foundation
import Testing
import TagwerkCore
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
}
