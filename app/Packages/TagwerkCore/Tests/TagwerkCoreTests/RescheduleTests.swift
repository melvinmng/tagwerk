import Foundation
import Testing
@testable import TagwerkCore

struct RescheduleTests {
    let calendar = makeCalendar()

    @Test func reschedule_tomorrow_keepsTime() {
        let now = instant(2026, 11, 18, 10, 0)
        let due = DueDate(year: 2026, month: 11, day: 18, hour: 14, minute: 30)
        let result = rescheduled(due, option: .tomorrow, now: now, calendar: calendar)
        #expect(result == DueDate(year: 2026, month: 11, day: 19, hour: 14, minute: 30))
    }

    @Test func reschedule_nextMonday_onMonday_addsSevenDays() {
        let now = instant(2026, 11, 16, 9, 0)
        let result = rescheduled(DueDate(year: 2026, month: 11, day: 16), option: .nextMonday, now: now, calendar: calendar)
        #expect(result == DueDate(year: 2026, month: 11, day: 23))
    }

    @Test func reschedule_nextMonday_onSunday_equalsTomorrow() {
        let now = instant(2026, 11, 22, 21, 0)
        let due = DueDate(year: 2026, month: 11, day: 20)
        let nextMonday = rescheduled(due, option: .nextMonday, now: now, calendar: calendar)
        let tomorrow = rescheduled(due, option: .tomorrow, now: now, calendar: calendar)
        #expect(nextMonday == DueDate(year: 2026, month: 11, day: 23))
        #expect(nextMonday == tomorrow)
    }

    @Test func reschedule_nilDue_tomorrow_isDateOnly() {
        let now = instant(2026, 11, 18, 10, 0)
        let result = rescheduled(nil, option: .tomorrow, now: now, calendar: calendar)
        #expect(result == DueDate(year: 2026, month: 11, day: 19))
    }

    @Test func reschedule_toDate_keepsTime() {
        let now = instant(2026, 11, 18, 10, 0)
        let due = DueDate(year: 2026, month: 11, day: 18, hour: 8, minute: 15)
        let result = rescheduled(due, option: .date(DueDate(year: 2026, month: 12, day: 24)), now: now, calendar: calendar)
        #expect(result == DueDate(year: 2026, month: 12, day: 24, hour: 8, minute: 15))
    }

    @Test func reschedule_acrossMonthEnd() {
        let now = instant(2026, 11, 30, 10, 0)
        #expect(rescheduled(nil, option: .tomorrow, now: now, calendar: calendar) == DueDate(year: 2026, month: 12, day: 1))
    }

    @Test func reschedule_weekend_onWednesday_isComingSaturday() {
        let now = instant(2026, 11, 18, 10, 0)
        let due = DueDate(year: 2026, month: 11, day: 18, hour: 9, minute: 30)
        #expect(rescheduled(due, option: .weekend, now: now, calendar: calendar)
                == DueDate(year: 2026, month: 11, day: 21, hour: 9, minute: 30))
    }

    @Test func reschedule_weekend_onSaturday_isNextSaturday() {
        let now = instant(2026, 11, 21, 10, 0)
        #expect(rescheduled(nil, option: .weekend, now: now, calendar: calendar) == DueDate(year: 2026, month: 11, day: 28))
    }

    @Test func reschedule_weekend_onSunday_isSixDaysLater() {
        let now = instant(2026, 11, 22, 10, 0)
        #expect(rescheduled(nil, option: .weekend, now: now, calendar: calendar) == DueDate(year: 2026, month: 11, day: 28))
    }

    @Test func reschedule_today_keepsTime() {
        let now = instant(2026, 11, 18, 10, 0)
        let due = DueDate(year: 2026, month: 11, day: 15, hour: 9, minute: 30)
        #expect(rescheduled(due, option: .today, now: now, calendar: calendar)
                == DueDate(year: 2026, month: 11, day: 18, hour: 9, minute: 30))
        #expect(rescheduled(nil, option: .today, now: now, calendar: calendar) == DueDate(year: 2026, month: 11, day: 18))
    }
}
