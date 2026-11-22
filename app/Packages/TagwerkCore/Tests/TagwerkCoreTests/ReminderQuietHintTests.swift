import Foundation
import Testing
@testable import TagwerkCore

/// When quiet hours delay a reminder, the reminder list says so (plan g1, RH6c).
struct ReminderQuietHintTests {
    let calendar = makeCalendar()
    let night = QuietHours(startMinutes: 23 * 60, endMinutes: 7 * 60)

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date { instant(2026, 11, day, hour, minute, in: calendar) }

    @Test func delivery_insideQuietHours_isTheirEnd() {
        // Due 19 Nov 00:30; one hour before is 23:30 on the 18th, inside 23:00-07:00.
        let delivery = ReminderQuietHint.delivery(of: .before(amount: 1, unit: .hours), anchor: at(19, 0, 30), isAllDay: false,
                                                  quietHours: night, calendar: calendar)
        #expect(delivery == at(19, 7))
    }

    @Test func delivery_outside_isNil() {
        let delivery = ReminderQuietHint.delivery(of: .before(amount: 1, unit: .hours), anchor: at(19, 15), isAllDay: false,
                                                  quietHours: night, calendar: calendar)
        #expect(delivery == nil)
    }

    @Test func delivery_atTheEndOfTheWindow_isNil() {
        // 07:00 itself is outside: the end is exclusive.
        let delivery = ReminderQuietHint.delivery(of: .before(amount: 0, unit: .minutes), anchor: at(19, 7), isAllDay: false,
                                                  quietHours: night, calendar: calendar)
        #expect(delivery == nil)
    }

    @Test func delivery_withoutQuietHours_isNil() {
        let offset = ReminderOffset.before(amount: 1, unit: .hours)
        #expect(ReminderQuietHint.delivery(of: offset, anchor: at(19, 0, 30), isAllDay: false, quietHours: nil, calendar: calendar) == nil)
        let empty = QuietHours(startMinutes: 300, endMinutes: 300)
        #expect(ReminderQuietHint.delivery(of: offset, anchor: at(19, 0, 30), isAllDay: false, quietHours: empty, calendar: calendar) == nil)
    }

    @Test func delivery_allDayAtTime() {
        // An all-day entry on 19 Nov: "the day before at 23:30" falls into the night and is held until 07:00 on the 19th.
        let delivery = ReminderQuietHint.delivery(of: .at(daysBefore: 1, hour: 23, minute: 30), anchor: at(19, 12), isAllDay: true,
                                                  quietHours: night, calendar: calendar)
        #expect(delivery == at(19, 7))
        let evening = ReminderQuietHint.delivery(of: .at(daysBefore: 1, hour: 18, minute: 0), anchor: at(19, 12), isAllDay: true,
                                                 quietHours: night, calendar: calendar)
        #expect(evening == nil)
    }
}
