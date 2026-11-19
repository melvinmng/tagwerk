import Foundation
import Testing
@testable import TagwerkCore

struct FocusRulesTests {
    let calendar = makeCalendar()
    let today = PlanDay(year: 2026, month: 11, day: 18)

    @Test func candidates_arePlannedDueOrBlockedToday_withoutRecurring() {
        let planned = makeItem("A geplant")
        let due = makeItem("B fällig", due: DueDate(year: 2026, month: 11, day: 18), priority: .p1)
        let blocked = makeItem("C Block")
        let tomorrow = makeItem("D morgen", due: DueDate(year: 2026, month: 11, day: 19))
        let recurring = makeItem("E wiederkehrend", due: DueDate(year: 2026, month: 11, day: 18))
        var completed = makeItem("F erledigt", due: DueDate(year: 2026, month: 11, day: 18))
        completed.isCompleted = true
        let result = FocusRules.candidates([planned, due, blocked, tomorrow, recurring, completed],
                                           plannedToday: [planned.id], blockedToday: [blocked.id], recurring: [recurring.id],
                                           today: today, calendar: calendar)
        #expect(result.map(\.title) == ["B fällig", "A geplant", "C Block"])
    }

    @Test func candidates_priorityOneOrDueTodayComeFirst() {
        let plain = makeItem("A")
        let p1 = makeItem("B", priority: .p1)
        let dueToday = makeItem("C", due: DueDate(year: 2026, month: 11, day: 18))
        let result = FocusRules.candidates([plain, p1, dueToday], plannedToday: [plain.id, p1.id, dueToday.id], blockedToday: [],
                                           recurring: [], today: today, calendar: calendar)
        #expect(result.map(\.title) == ["C", "B", "A"])
    }

    @Test func maximumMarks_isThree() {
        #expect(FocusRules.maximumMarks == 3)
    }
}
