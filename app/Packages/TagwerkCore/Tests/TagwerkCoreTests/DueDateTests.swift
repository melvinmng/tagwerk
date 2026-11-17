import Foundation
import Testing
@testable import TagwerkCore

struct DueDateTests {
    @Test func dueDate_withoutTime_keepsDayAcrossTimeZones() {
        let due = DueDate(year: 2026, month: 11, day: 20)
        let berlin = makeCalendar("Europe/Berlin")
        let newYork = makeCalendar("America/New_York")
        let now = instant(2026, 11, 18, 10, 0, in: berlin)
        let item = makeItem("Abgabe", due: due)

        #expect(section(for: item, now: now, calendar: berlin) == .thisWeek)
        #expect(section(for: item, now: now, calendar: newYork) == .thisWeek)
        #expect(item.due?.day == 20)
        #expect(newYork.component(.day, from: due.startDate(in: newYork)) == 20)
    }

    @Test func dueDate_initFromDate_withoutTime_dropsHourAndMinute() {
        let calendar = makeCalendar()
        let due = DueDate(date: instant(2026, 11, 20, 14, 30), includeTime: false, calendar: calendar)
        #expect(due == DueDate(year: 2026, month: 11, day: 20))
        #expect(!due.hasTime)
    }

    @Test func dueDate_initFromDate_withTime_keepsHourAndMinute() {
        let calendar = makeCalendar()
        let due = DueDate(date: instant(2026, 11, 20, 14, 30), includeTime: true, calendar: calendar)
        #expect(due == DueDate(year: 2026, month: 11, day: 20, hour: 14, minute: 30))
        #expect(due.hasTime)
    }

    @Test func dueDate_movedTo_keepsTime() {
        let due = DueDate(year: 2026, month: 11, day: 18, hour: 14, minute: 30)
        let moved = due.movedTo(day: DueDate(year: 2026, month: 12, day: 1))
        #expect(moved == DueDate(year: 2026, month: 12, day: 1, hour: 14, minute: 30))
    }
}
