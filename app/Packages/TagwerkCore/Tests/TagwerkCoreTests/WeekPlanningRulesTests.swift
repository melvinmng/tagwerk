import Foundation
import Testing
@testable import TagwerkCore

struct WeekPlanningRulesTests {
    let calendar = makeCalendar()

    @Test func reviewedWeek_onSunday_isTheRunningWeek() {
        let sunday = PlanDay(year: 2026, month: 11, day: 22)
        #expect(WeekPlanningRules.reviewedWeekStart(today: sunday, calendar: calendar) == PlanDay(year: 2026, month: 11, day: 16))
        #expect(WeekPlanningRules.plannedWeekStart(today: sunday, calendar: calendar) == PlanDay(year: 2026, month: 11, day: 23))
    }

    @Test func reviewedWeek_onMonday_isThePreviousWeek() {
        let monday = PlanDay(year: 2026, month: 11, day: 23)
        #expect(WeekPlanningRules.reviewedWeekStart(today: monday, calendar: calendar) == PlanDay(year: 2026, month: 11, day: 16))
        #expect(WeekPlanningRules.plannedWeekStart(today: monday, calendar: calendar) == PlanDay(year: 2026, month: 11, day: 23))
        // Midweek: still the week before the running one.
        let thursday = PlanDay(year: 2026, month: 11, day: 19)
        #expect(WeekPlanningRules.reviewedWeekStart(today: thursday, calendar: calendar) == PlanDay(year: 2026, month: 11, day: 9))
    }

    @Test func steps_areFiveInAFixedOrder() {
        #expect(WeekPlanningRules.steps == [.review, .reflection, .deadlines, .plan, .habits])
        #expect(WeekPlanningStep.allCases.map(\.rawValue) == [0, 1, 2, 3, 4])
    }

    @Test func deadlineTasks_coverThePlannedWeekAndOverdue() {
        let week = PlanDay(year: 2026, month: 11, day: 23)
        let overdue = makeItem("Überfällig", due: DueDate(year: 2026, month: 11, day: 20))
        let monday = makeItem("Montag", due: DueDate(year: 2026, month: 11, day: 23))
        let sunday = makeItem("Sonntag", due: DueDate(year: 2026, month: 11, day: 29))
        let later = makeItem("Später", due: DueDate(year: 2026, month: 11, day: 30))
        let noDue = makeItem("Ohne")
        var done = makeItem("Erledigt", due: DueDate(year: 2026, month: 11, day: 24))
        done.isCompleted = true
        let result = WeekPlanningRules.deadlineTasks([sunday, later, noDue, monday, done, overdue], plannedWeek: week, calendar: calendar)
        #expect(result.map(\.title) == ["Überfällig", "Montag", "Sonntag"])
    }
}
