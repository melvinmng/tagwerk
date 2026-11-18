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

    // MARK: n-th weekday of the month

    private func day(_ year: Int, _ month: Int, _ day: Int) -> PlanDay { PlanDay(year: year, month: month, day: day) }

    @Test func monthlyWeekday_thirdWednesday() {
        let recurrence = Recurrence(rule: .monthlyWeekday(interval: 1, ordinal: 3, weekday: 4), start: day(2026, 11, 18),
                                    end: nil, count: nil)
        #expect(occurrences(of: recurrence, in: day(2026, 11, 1)...day(2027, 1, 31), calendar: calendar)
                == [day(2026, 11, 18), day(2026, 12, 16), day(2027, 1, 20)])
    }

    @Test func monthlyWeekday_everySecondMonth() {
        let recurrence = Recurrence(rule: .monthlyWeekday(interval: 2, ordinal: 1, weekday: 2), start: day(2026, 11, 2),
                                    end: nil, count: nil)
        #expect(occurrences(of: recurrence, in: day(2026, 11, 1)...day(2027, 3, 31), calendar: calendar)
                == [day(2026, 11, 2), day(2027, 1, 4), day(2027, 3, 1)])
    }

    @Test func monthlyWeekday_endsAfterCount() {
        let recurrence = Recurrence(rule: .monthlyWeekday(interval: 1, ordinal: 3, weekday: 4), start: day(2026, 11, 18),
                                    end: nil, count: 2)
        #expect(occurrences(of: recurrence, in: day(2026, 11, 1)...day(2027, 6, 30), calendar: calendar)
                == [day(2026, 11, 18), day(2026, 12, 16)])
    }

    // MARK: Yearly

    @Test func yearly_sameDay() {
        let recurrence = Recurrence(rule: .yearly(interval: 1), start: day(2026, 11, 18), end: nil, count: nil)
        #expect(occurrences(of: recurrence, in: day(2026, 11, 1)...day(2028, 12, 31), calendar: calendar)
                == [day(2026, 11, 18), day(2027, 11, 18), day(2028, 11, 18)])
    }

    @Test func yearly_everySecondYear() {
        let recurrence = Recurrence(rule: .yearly(interval: 2), start: day(2026, 11, 18), end: nil, count: nil)
        #expect(occurrences(of: recurrence, in: day(2026, 11, 1)...day(2030, 12, 31), calendar: calendar)
                == [day(2026, 11, 18), day(2028, 11, 18), day(2030, 11, 18)])
    }

    @Test func yearly_leapDaySkipsOtherYears() {
        let recurrence = Recurrence(rule: .yearly(interval: 1), start: day(2028, 2, 29), end: nil, count: nil)
        #expect(occurrences(of: recurrence, in: day(2028, 1, 1)...day(2032, 12, 31), calendar: calendar)
                == [day(2028, 2, 29), day(2032, 2, 29)])
    }

    // MARK: Next occurrence

    @Test func nextOccurrence_onOrAfter() {
        let weekly = Recurrence(rule: .weekly(interval: 2, weekdays: [2, 5]), start: day(2026, 11, 19), end: nil, count: nil)
        #expect(nextOccurrence(of: weekly, onOrAfter: day(2026, 11, 18), calendar: calendar) == day(2026, 11, 19))
        #expect(nextOccurrence(of: weekly, onOrAfter: day(2026, 11, 20), calendar: calendar) == day(2026, 11, 30))
        #expect(nextOccurrence(of: weekly, onOrAfter: day(2026, 11, 30), calendar: calendar) == day(2026, 11, 30))
        let leap = Recurrence(rule: .yearly(interval: 1), start: day(2028, 2, 29), end: nil, count: nil)
        #expect(nextOccurrence(of: leap, onOrAfter: day(2028, 3, 1), calendar: calendar) == day(2032, 2, 29))
    }

    @Test func nextOccurrence_noneAfterEnd() {
        let ending = Recurrence(rule: .daily(interval: 1), start: day(2026, 11, 18), end: day(2026, 11, 20), count: nil)
        #expect(nextOccurrence(of: ending, onOrAfter: day(2026, 11, 21), calendar: calendar) == nil)
        let counted = Recurrence(rule: .daily(interval: 1), start: day(2026, 11, 18), end: nil, count: 2)
        #expect(nextOccurrence(of: counted, onOrAfter: day(2026, 11, 19), calendar: calendar) == day(2026, 11, 19))
        #expect(nextOccurrence(of: counted, onOrAfter: day(2026, 11, 20), calendar: calendar) == nil)
    }

    @Test func isValid_rejectsEndAndCount() {
        let start = day(2026, 11, 18)
        #expect(Recurrence(rule: .daily(interval: 1), start: start, end: day(2026, 12, 1), count: nil).isValid)
        #expect(Recurrence(rule: .daily(interval: 1), start: start, end: nil, count: 3).isValid)
        #expect(!Recurrence(rule: .daily(interval: 1), start: start, end: day(2026, 12, 1), count: 3).isValid)
    }

    @Test func isValid_checksValueRanges() {
        let start = day(2026, 11, 18)
        func valid(_ rule: RecurrenceRule, end: PlanDay? = nil, count: Int? = nil) -> Bool {
            Recurrence(rule: rule, start: start, end: end, count: count).isValid
        }
        #expect(!valid(.daily(interval: 0)))
        #expect(!valid(.weekly(interval: 1, weekdays: [0])))
        #expect(!valid(.weekly(interval: 1, weekdays: [8])))
        #expect(valid(.weekly(interval: 1, weekdays: [1, 7])))
        #expect(!valid(.monthly(interval: 1, day: 0)))
        #expect(!valid(.monthly(interval: 1, day: 32)))
        #expect(valid(.monthly(interval: 1, day: 31)))
        #expect(!valid(.monthlyWeekday(interval: 1, ordinal: 5, weekday: 4)))
        #expect(!valid(.monthlyWeekday(interval: 1, ordinal: 1, weekday: 0)))
        #expect(valid(.yearly(interval: 3)))
        #expect(!valid(.daily(interval: 1), count: 0))
        #expect(!valid(.daily(interval: 1), end: day(2026, 11, 17)))
        #expect(valid(.daily(interval: 1), end: start))
        // An unreadable rule is never valid for writing.
        #expect(!valid(.unsupported))
    }
}
