import Foundation
import Testing
@testable import TagwerkCore

/// Moving a repeating task on to its next occurrence when it is ticked off (plan 2026-11-18, stage 2).
struct RecurrenceAdvanceTests {
    let calendar = makeCalendar()

    private func day(_ day: Int, month: Int = 11, year: Int = 2026) -> PlanDay { PlanDay(year: year, month: month, day: day) }

    @Test func daily_movesToNextDayAndKeepsTime() throws {
        let series = Recurrence(rule: .daily(interval: 1), start: day(18), end: nil, count: nil)
        let result = try #require(advancedSeries(due: DueDate(year: 2026, month: 11, day: 18, hour: 9, minute: 30),
                                                 recurrence: series, calendar: calendar))
        #expect(result.due == DueDate(year: 2026, month: 11, day: 19, hour: 9, minute: 30))
        #expect(result.recurrence.start == day(19))
        #expect(result.recurrence.count == nil)
    }

    @Test func dateOnlyDue_staysDateOnly() throws {
        let series = Recurrence(rule: .daily(interval: 3), start: day(18), end: nil, count: nil)
        let result = try #require(advancedSeries(due: DueDate(year: 2026, month: 11, day: 18), recurrence: series, calendar: calendar))
        #expect(result.due == DueDate(year: 2026, month: 11, day: 21))
        #expect(result.due.hasTime == false)
    }

    /// Monday and Thursday: Monday → Thursday → next Monday.
    @Test func weekly_severalWeekdays() throws {
        let series = Recurrence(rule: .weekly(interval: 1, weekdays: [2, 5]), start: day(16), end: nil, count: nil)
        let first = try #require(advancedSeries(due: DueDate(year: 2026, month: 11, day: 16), recurrence: series, calendar: calendar))
        #expect(first.due == DueDate(year: 2026, month: 11, day: 19))
        let second = try #require(advancedSeries(due: first.due, recurrence: first.recurrence, calendar: calendar))
        #expect(second.due == DueDate(year: 2026, month: 11, day: 23))
    }

    /// Every second week on Monday and Thursday keeps its rhythm across both weekdays.
    @Test func weekly_everySecondWeek_keepsRhythm() throws {
        let series = Recurrence(rule: .weekly(interval: 2, weekdays: [2, 5]), start: day(16), end: nil, count: nil)
        let first = try #require(advancedSeries(due: DueDate(year: 2026, month: 11, day: 16), recurrence: series, calendar: calendar))
        #expect(first.due == DueDate(year: 2026, month: 11, day: 19))
        let second = try #require(advancedSeries(due: first.due, recurrence: first.recurrence, calendar: calendar))
        #expect(second.due == DueDate(year: 2026, month: 11, day: 30))
    }

    @Test func monthly_withInterval() throws {
        let series = Recurrence(rule: .monthly(interval: 2, day: 18), start: day(18), end: nil, count: nil)
        let result = try #require(advancedSeries(due: DueDate(year: 2026, month: 11, day: 18), recurrence: series, calendar: calendar))
        #expect(result.due == DueDate(year: 2027, month: 1, day: 18))
    }

    @Test func count_decrementsAndEndsAtOne() throws {
        let series = Recurrence(rule: .daily(interval: 1), start: day(18), end: nil, count: 2)
        let result = try #require(advancedSeries(due: DueDate(year: 2026, month: 11, day: 18), recurrence: series, calendar: calendar))
        #expect(result.recurrence.count == 1)
        #expect(advancedSeries(due: result.due, recurrence: result.recurrence, calendar: calendar) == nil)
    }

    @Test func endDate_stopsTheSeries() throws {
        let series = Recurrence(rule: .daily(interval: 1), start: day(18), end: day(19), count: nil)
        let result = try #require(advancedSeries(due: DueDate(year: 2026, month: 11, day: 18), recurrence: series, calendar: calendar))
        #expect(result.due == DueDate(year: 2026, month: 11, day: 19))
        #expect(result.recurrence.end == day(19))
        #expect(advancedSeries(due: result.due, recurrence: result.recurrence, calendar: calendar) == nil)
    }

    /// The series starts at the due date, whatever start the stored rule carries.
    @Test func startFollowsDueDate() throws {
        let series = Recurrence(rule: .daily(interval: 2), start: day(1), end: nil, count: nil)
        let result = try #require(advancedSeries(due: DueDate(year: 2026, month: 11, day: 18), recurrence: series, calendar: calendar))
        #expect(result.due == DueDate(year: 2026, month: 11, day: 20))
    }

    /// A due date off the rule (Wednesday for "every Monday") is not an occurrence and does not use up the count.
    @Test func dueOffTheRule_keepsCount() throws {
        let series = Recurrence(rule: .weekly(interval: 1, weekdays: [2]), start: day(18), end: nil, count: 3)
        let result = try #require(advancedSeries(due: DueDate(year: 2026, month: 11, day: 18), recurrence: series, calendar: calendar))
        #expect(result.due == DueDate(year: 2026, month: 11, day: 23))
        #expect(result.recurrence.count == 3)
    }

    @Test func unsupported_hasNoNextOccurrence() {
        let series = Recurrence(rule: .unsupported, start: day(18), end: nil, count: nil)
        #expect(advancedSeries(due: DueDate(year: 2026, month: 11, day: 18), recurrence: series, calendar: calendar) == nil)
    }
}
