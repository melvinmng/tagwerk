import Foundation
import Testing
@testable import TagwerkCore

struct BlockStartTests {
    let calendar = makeCalendar()
    let today = PlanDay(year: 2026, month: 11, day: 18)
    let hours = WorkHours(startMinutes: 9 * 60, endMinutes: 18 * 60)

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func today_duringWork_isNextFullHour() {
        #expect(suggestedBlockStart(on: today, hours: hours, minutes: 60, now: at(18, 14, 20), calendar: calendar) == at(18, 15))
    }

    @Test func today_beforeWork_isWorkStart() {
        #expect(suggestedBlockStart(on: today, hours: hours, minutes: 60, now: at(18, 6, 40), calendar: calendar) == at(18, 9))
    }

    @Test func today_nearEnd_latestStartStillFitsBeforeEnd() {
        #expect(suggestedBlockStart(on: today, hours: hours, minutes: 60, now: at(18, 16, 30), calendar: calendar) == at(18, 17))
        #expect(suggestedBlockStart(on: today, hours: hours, minutes: 120, now: at(18, 16, 30), calendar: calendar) == at(18, 17))
    }

    @Test func today_afterWork_neverInThePast() {
        #expect(suggestedBlockStart(on: today, hours: hours, minutes: 60, now: at(18, 19, 10), calendar: calendar) == at(18, 20))
    }

    @Test func futureDay_isWorkStart() {
        let tomorrow = PlanDay(year: 2026, month: 11, day: 19)
        #expect(suggestedBlockStart(on: tomorrow, hours: WorkHours(startMinutes: 8 * 60, endMinutes: 16 * 60), minutes: 60,
                                    now: at(18, 14, 20), calendar: calendar) == at(19, 8))
    }

    @Test func futureDayOff_usesDefaultMorning() {
        let saturday = PlanDay(year: 2026, month: 11, day: 21)
        #expect(suggestedBlockStart(on: saturday, hours: nil, minutes: 60, now: at(18, 14, 20), calendar: calendar) == at(21, 9))
    }

    @Test func todayOff_isNextFullHour() {
        #expect(suggestedBlockStart(on: today, hours: nil, minutes: 60, now: at(18, 14, 20), calendar: calendar) == at(18, 15))
    }

    // MARK: Late evening: the suggestion stays on the day

    @Test func today_after23_staysOnTheSameDay() {
        // The next full hour would be 24:00, which is the next day; the next quarter hour is used instead.
        let start = suggestedBlockStart(on: today, hours: hours, minutes: 60, now: at(18, 23, 20), calendar: calendar)
        #expect(start == at(18, 23, 30))
        #expect(PlanDay(date: start, calendar: calendar) == today)
    }

    @Test func today_afterWorkEndingAtMidnight_staysOnTheSameDay() {
        let lateHours = WorkHours(startMinutes: 9 * 60, endMinutes: 24 * 60)
        #expect(suggestedBlockStart(on: today, hours: lateHours, minutes: 60, now: at(18, 23, 30), calendar: calendar) == at(18, 23, 45))
    }

    @Test func todayOff_after23_staysOnTheSameDay() {
        #expect(suggestedBlockStart(on: today, hours: nil, minutes: 60, now: at(18, 23, 5), calendar: calendar) == at(18, 23, 15))
    }

    @Test func today_inTheLastQuarterHour_isTheLastMinuteOfTheDayAndNeverInThePast() {
        let now = at(18, 23, 50)
        let start = suggestedBlockStart(on: today, hours: hours, minutes: 60, now: now, calendar: calendar)
        #expect(start == at(18, 23, 59))
        #expect(start > now)
        #expect(PlanDay(date: start, calendar: calendar) == today)
    }

    @Test func today_at2259_stillTakesTheFullHour() {
        #expect(suggestedBlockStart(on: today, hours: hours, minutes: 60, now: at(18, 22, 59), calendar: calendar) == at(18, 23))
    }
}
