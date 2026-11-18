import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// Mockups VC1, VL1, VU1: priority, due date and effort of the task behind a suggestion.
struct SuggestionFactsTests {
    let calendar = testCalendar()
    let today = PlanDay(year: 2026, month: 11, day: 18)  // Wednesday
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 8, minute: 42))! }

    private func task(due: DueDate? = nil, priority: Priority? = nil) -> TaskItem {
        var task = makeTask("Methodik", source: .local, due: due)
        task.priority = priority
        return task
    }

    private func block(minutes: Int = 45, day: PlanDay? = nil) -> PlanSuggestion {
        PlanSuggestion(id: UUID(), kind: .block, taskKey: "local:Methodik", title: "Methodik", day: day ?? today,
                       startMinutes: 18 * 60, minutes: minutes, reason: "", endMinutes: nil, fromDay: nil, dependsOn: nil)
    }

    private func facts(_ suggestion: PlanSuggestion, _ task: TaskItem?, effort: Int? = nil, blocked: Int = 0) -> SuggestionFacts {
        SuggestionFacts(suggestion: suggestion, task: task, effort: effort, blocked: blocked, today: today, now: now, calendar: calendar)
    }

    @Test func priority_p1Red_p2Orange_restNeutral() {
        #expect(facts(block(), task(priority: .p1)).priority == SuggestionFacts.Mark(text: "P1", urgency: .high))
        #expect(facts(block(), task(priority: .p2)).priority == SuggestionFacts.Mark(text: "P2", urgency: .medium))
        #expect(facts(block(), task(priority: .p4)).priority == SuggestionFacts.Mark(text: "P4", urgency: .none))
        #expect(facts(block(), task()).priority == nil)
    }

    @Test func due_overdueTodayTomorrowLater() {
        let overdue = facts(block(), task(due: DueDate(year: 2026, month: 11, day: 16)))
        #expect(overdue.due == SuggestionFacts.Mark(text: "überfällig seit 16.11.", urgency: .high))
        #expect(overdue.dueShort == "seit 16.11.")
        let dueToday = facts(block(), task(due: DueDate(year: 2026, month: 11, day: 18, hour: 18, minute: 0)))
        #expect(dueToday.due == SuggestionFacts.Mark(text: "heute, 18:00", urgency: .medium))
        #expect(dueToday.dueShort == "heute")
        #expect(facts(block(), task(due: DueDate(year: 2026, month: 11, day: 19))).due?.text == "morgen")
        let later = facts(block(), task(due: DueDate(year: 2026, month: 11, day: 20)))
        #expect(later.due == SuggestionFacts.Mark(text: "fällig Fr 20.11.", urgency: .none))
        #expect(later.dueShort == "20.11.")
        #expect(later.dueDistance == "in 2 Tagen")
        #expect(facts(block(), task()).due == nil)
    }

    @Test func due_isUrgentOnlyWhenTodayOrOverdue() {
        #expect(facts(block(), task(due: DueDate(year: 2026, month: 11, day: 16))).dueIsUrgent)
        #expect(!facts(block(), task(due: DueDate(year: 2026, month: 11, day: 24))).dueIsUrgent)
    }

    @Test func effort_blockOfTotal_orDurationOnly() {
        let withEffort = facts(block(minutes: 45), task(), effort: 180)
        #expect(withEffort.effort == "45 min von 3 h")
        #expect(withEffort.effortShort == "von 3 h")
        let without = facts(block(minutes: 45), task())
        #expect(without.effort == "45 min")
        #expect(without.effortShort == nil)
    }

    @Test func effortBar_plannedThisAndOpen() {
        let bar = facts(block(minutes: 45), task(), effort: 180, blocked: 60).bar
        #expect(bar == SuggestionFacts.Bar(total: 180, planned: 60, suggested: 45))
        #expect(bar?.open == 75)
        #expect(facts(block(), task()).bar == nil)
    }

    @Test func unscheduled_showsOpenEffort() {
        let entry = UnscheduledTask(taskKey: "local:Methodik", title: "Methodik", reason: "")
        let open = SuggestionFacts(unscheduled: entry, task: task(priority: .p1), effort: 180, blocked: 60,
                                   today: today, now: now, calendar: calendar)
        #expect(open.effort == "2 h offen")
        #expect(open.priority?.text == "P1")
    }

    @Test func move_targetIsLateWhenAfterDue() {
        var move = block()
        move.kind = .move
        move.startMinutes = nil
        move.minutes = nil
        move.fromDay = today
        move.day = PlanDay(year: 2026, month: 11, day: 23)
        let late = facts(move, task(due: DueDate(year: 2026, month: 11, day: 20)), effort: 60)
        #expect(late.moveTarget == SuggestionFacts.Mark(text: "nach Mo 23.", urgency: .high))
        #expect(late.effort == "1 h")
        let fine = facts(move, task(due: DueDate(year: 2026, month: 11, day: 30)))
        #expect(fine.moveTarget?.urgency == SuggestionFacts.Urgency.none)
    }

    @Test func missingTask_showsNothingButDuration() {
        let facts = facts(block(minutes: 30), nil)
        #expect(facts.priority == nil && facts.due == nil)
        #expect(facts.effort == "30 min")
    }
}
