import Foundation
import Testing
@testable import TagwerkCore

struct ImportantDeadlineTests {
    let calendar = makeCalendar()
    let range = PlanDay(year: 2026, month: 11, day: 16)...PlanDay(year: 2026, month: 11, day: 30)

    private func task(_ title: String, priority: Priority?, due: DueDate?, epic: EpicInfo? = nil, isEpic: Bool = false,
                      source: TaskSource = .github) -> TaskItem {
        var item = makeItem(title, due: due, priority: priority, source: source)
        item.epic = epic
        item.isEpic = isEpic
        return item
    }

    @Test func deadlines_includeP1WithDueOnly() {
        let items = [
            task("P1 fällig", priority: .p1, due: DueDate(year: 2026, month: 11, day: 20)),
            task("P1 ohne Datum", priority: .p1, due: nil),
            task("P2 fällig", priority: .p2, due: DueDate(year: 2026, month: 11, day: 20)),
        ]
        let result = importantDeadlines(tasks: items, events: [], deadlineCalendarIDs: [], in: range, calendar: calendar)
        #expect(result.map(\.title) == ["P1 fällig"])
        #expect(result.first?.kind == .priorityOne)
        #expect(result.first?.taskID == items[0].id)
    }

    @Test func deadlines_epicFromParentDeduplicated() {
        let epic = EpicInfo(id: "E_1", number: 1, title: "Phase 2", due: DueDate(year: 2026, month: 11, day: 25), isEpic: true)
        let items = [
            task("Sub A", priority: .p3, due: nil, epic: epic),
            task("Sub B", priority: .p3, due: nil, epic: epic),
        ]
        let result = importantDeadlines(tasks: items, events: [], deadlineCalendarIDs: [], in: range, calendar: calendar)
        #expect(result.count == 1)
        #expect(result.first?.kind == .epic)
        #expect(result.first?.title == "Phase 2")
        #expect(result.first?.day == PlanDay(year: 2026, month: 11, day: 25))
    }

    @Test func deadlines_assignedEpicTaskAndParentAreOneEntry() {
        let epic = EpicInfo(id: "E_1", number: 1, title: "Phase 2", due: DueDate(year: 2026, month: 11, day: 25), isEpic: true)
        var epicTask = task("Phase 2", priority: .p2, due: DueDate(year: 2026, month: 11, day: 25), isEpic: true)
        epicTask = TaskItem(id: TaskID(source: .github, rawValue: "E_1"), title: epicTask.title, notes: nil, due: epicTask.due,
                            priority: .p2, estimateMinutes: nil, isCompleted: false, container: epicTask.container, url: nil,
                            version: "1", editableFields: [], isEpic: true)
        let items = [epicTask, task("Sub", priority: .p3, due: nil, epic: epic)]
        let result = importantDeadlines(tasks: items, events: [], deadlineCalendarIDs: [], in: range, calendar: calendar)
        #expect(result.count == 1)
        #expect(result.first?.taskID == epicTask.id)
    }

    @Test func deadlines_parentWithoutEpicLabel_isIgnored() {
        let parent = EpicInfo(id: "P_1", number: 9, title: "Kein Epic", due: DueDate(year: 2026, month: 11, day: 25), isEpic: false)
        let result = importantDeadlines(tasks: [task("Sub", priority: .p3, due: nil, epic: parent)], events: [],
                                        deadlineCalendarIDs: [], in: range, calendar: calendar)
        #expect(result.isEmpty)
    }

    @Test func deadlines_deadlineCalendarEvents_allDayAndTimed() {
        let exam = CalendarEvent(id: "ev1", externalID: nil, calendarID: "uni", title: "Statistik-Klausur",
                                 start: instant(2026, 11, 20, 10, 0), end: instant(2026, 11, 20, 12, 0),
                                 isAllDay: false, url: nil, isBusy: true, version: "1")
        let submission = CalendarEvent(id: "ev2", externalID: nil, calendarID: "uni", title: "Abgabe Portfolio",
                                       start: instant(2026, 11, 22), end: instant(2026, 11, 23),
                                       isAllDay: true, url: nil, isBusy: true, version: "1")
        let other = CalendarEvent(id: "ev3", externalID: nil, calendarID: "privat", title: "Kino",
                                  start: instant(2026, 11, 20, 20, 0), end: instant(2026, 11, 20, 22, 0),
                                  isAllDay: false, url: nil, isBusy: true, version: "1")
        let result = importantDeadlines(tasks: [], events: [exam, submission, other], deadlineCalendarIDs: ["uni"],
                                        in: range, calendar: calendar)
        #expect(result.map(\.title) == ["Statistik-Klausur", "Abgabe Portfolio"])
        #expect(result[0].time == exam.start)
        #expect(result[1].time == nil)
        #expect(result.allSatisfy { $0.kind == .deadlineCalendar })
    }

    @Test func deadlines_outsideRangeExcluded() {
        let items = [task("Später", priority: .p1, due: DueDate(year: 2026, month: 12, day: 5))]
        #expect(importantDeadlines(tasks: items, events: [], deadlineCalendarIDs: [], in: range, calendar: calendar).isEmpty)
    }
}
