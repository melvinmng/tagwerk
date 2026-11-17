import Foundation
import Testing
@testable import TagwerkCore

struct RecurrenceTests {
    let calendar = makeCalendar()
    let nov16 = PlanDay(year: 2026, month: 11, day: 16)  // Monday

    private func days(_ list: [Int], month: Int = 11) -> [PlanDay] { list.map { PlanDay(year: 2026, month: month, day: $0) } }

    @Test func daily_everyDay() {
        let recurrence = Recurrence(rule: .daily(interval: 1), start: nov16, end: nil, count: nil)
        #expect(occurrences(of: recurrence, in: PlanDay(year: 2026, month: 11, day: 18)...PlanDay(year: 2026, month: 11, day: 20),
                            calendar: calendar) == days([18, 19, 20]))
    }

    @Test func daily_everyThirdDay() {
        let recurrence = Recurrence(rule: .daily(interval: 3), start: nov16, end: nil, count: nil)
        #expect(occurrences(of: recurrence, in: nov16...PlanDay(year: 2026, month: 11, day: 25), calendar: calendar) == days([16, 19, 22, 25]))
    }

    @Test func weekly_monWedFri() {
        let recurrence = Recurrence(rule: .weekly(interval: 1, weekdays: [2, 4, 6]), start: nov16, end: nil, count: nil)
        #expect(occurrences(of: recurrence, in: nov16...PlanDay(year: 2026, month: 11, day: 22), calendar: calendar) == days([16, 18, 20]))
    }

    @Test func weekly_everySecondWeek() {
        let recurrence = Recurrence(rule: .weekly(interval: 2, weekdays: [3]), start: nov16, end: nil, count: nil)
        #expect(occurrences(of: recurrence, in: nov16...PlanDay(year: 2026, month: 12, day: 6), calendar: calendar)
                == [PlanDay(year: 2026, month: 11, day: 17), PlanDay(year: 2026, month: 12, day: 1)])
    }

    @Test func monthly_day31_skipsShortMonths() {
        let recurrence = Recurrence(rule: .monthly(interval: 1, day: 31), start: PlanDay(year: 2026, month: 10, day: 31), end: nil, count: nil)
        #expect(occurrences(of: recurrence, in: PlanDay(year: 2026, month: 10, day: 1)...PlanDay(year: 2027, month: 1, day: 31),
                            calendar: calendar)
                == [PlanDay(year: 2026, month: 10, day: 31), PlanDay(year: 2026, month: 12, day: 31), PlanDay(year: 2027, month: 1, day: 31)])
    }

    @Test func countLimitsOccurrences() {
        let recurrence = Recurrence(rule: .daily(interval: 1), start: nov16, end: nil, count: 3)
        #expect(occurrences(of: recurrence, in: nov16...PlanDay(year: 2026, month: 11, day: 30), calendar: calendar) == days([16, 17, 18]))
    }

    @Test func endDateLimitsOccurrences() {
        let recurrence = Recurrence(rule: .daily(interval: 1), start: nov16, end: PlanDay(year: 2026, month: 11, day: 17), count: nil)
        #expect(occurrences(of: recurrence, in: nov16...PlanDay(year: 2026, month: 11, day: 30), calendar: calendar) == days([16, 17]))
    }

    @Test func unsupported_onlyStartDay() {
        let recurrence = Recurrence(rule: .unsupported, start: PlanDay(year: 2026, month: 11, day: 19), end: nil, count: nil)
        #expect(occurrences(of: recurrence, in: nov16...PlanDay(year: 2026, month: 11, day: 30), calendar: calendar) == days([19]))
        #expect(occurrences(of: recurrence, in: nov16...PlanDay(year: 2026, month: 11, day: 18), calendar: calendar).isEmpty)
    }
}
