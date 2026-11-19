import Foundation
import Testing
@testable import TagwerkCore

struct ReminderOffsetTests {
    let calendar = makeCalendar()

    @Test func fireDate_before_subtractsCalendarUnits() {
        let anchor = instant(2026, 11, 20, 14, 30, in: calendar)
        #expect(ReminderOffset.before(amount: 15, unit: .minutes).fireDate(anchor: anchor, isAllDay: false, calendar: calendar)
                == instant(2026, 11, 20, 14, 15, in: calendar))
        #expect(ReminderOffset.before(amount: 2, unit: .hours).fireDate(anchor: anchor, isAllDay: false, calendar: calendar)
                == instant(2026, 11, 20, 12, 30, in: calendar))
        #expect(ReminderOffset.before(amount: 1, unit: .days).fireDate(anchor: anchor, isAllDay: false, calendar: calendar)
                == instant(2026, 11, 19, 14, 30, in: calendar))
        #expect(ReminderOffset.before(amount: 2, unit: .weeks).fireDate(anchor: anchor, isAllDay: false, calendar: calendar)
                == instant(2026, 11, 6, 14, 30, in: calendar))
        #expect(ReminderOffset.before(amount: 0, unit: .minutes).fireDate(anchor: anchor, isAllDay: false, calendar: calendar) == anchor)
    }

    @Test func fireDate_atDaysBefore_setsLocalTime() {
        let anchor = instant(2026, 11, 20, 14, 30, in: calendar)
        #expect(ReminderOffset.at(daysBefore: 1, hour: 18, minute: 0).fireDate(anchor: anchor, isAllDay: false, calendar: calendar)
                == instant(2026, 11, 19, 18, 0, in: calendar))
        #expect(ReminderOffset.at(daysBefore: 0, hour: 9, minute: 5).fireDate(anchor: anchor, isAllDay: false, calendar: calendar)
                == instant(2026, 11, 20, 9, 5, in: calendar))
    }

    @Test func fireDate_at_acrossDaylightSavingChange_keepsWallClock() {
        // Berlin changes to winter time on Sunday 25 Oct 2026; the day before the Monday event is 24 h + 1 h away.
        let anchor = instant(2026, 10, 26, 10, 0, in: calendar)
        let fire = ReminderOffset.at(daysBefore: 2, hour: 18, minute: 0).fireDate(anchor: anchor, isAllDay: false, calendar: calendar)
        #expect(fire == instant(2026, 10, 24, 18, 0, in: calendar))
        let parts = calendar.dateComponents([.hour, .minute], from: fire!)
        #expect(parts.hour == 18 && parts.minute == 0)
        // One day before an anchor right after the change still lands on 18:00 local time.
        let sunday = instant(2026, 10, 25, 12, 0, in: calendar)
        let eve = ReminderOffset.at(daysBefore: 1, hour: 18, minute: 0).fireDate(anchor: sunday, isAllDay: false, calendar: calendar)
        #expect(eve == instant(2026, 10, 24, 18, 0, in: calendar))
    }

    @Test func fireDate_allDay_anchorsAtStartOfDay() {
        // A time inside the day is ignored for an all-day entry.
        let anchor = instant(2026, 11, 20, 13, 0, in: calendar)
        #expect(ReminderOffset.before(amount: 1, unit: .days).fireDate(anchor: anchor, isAllDay: true, calendar: calendar)
                == instant(2026, 11, 19, 0, 0, in: calendar))
        #expect(ReminderOffset.at(daysBefore: 1, hour: 18, minute: 0).fireDate(anchor: anchor, isAllDay: true, calendar: calendar)
                == instant(2026, 11, 19, 18, 0, in: calendar))
    }

    @Test func fireDate_absolute_isUnchanged() {
        let date = instant(2026, 11, 1, 8, 0, in: calendar)
        #expect(ReminderOffset.absolute(date).fireDate(anchor: instant(2026, 12, 1, 8, 0, in: calendar), isAllDay: false,
                                                       calendar: calendar) == date)
    }

    @Test func normalized_removesEquivalentDuplicates() {
        let result = ReminderOffset.normalized([
            .before(amount: 60, unit: .minutes), .before(amount: 1, unit: .hours), .before(amount: 24, unit: .hours),
            .before(amount: 1, unit: .days), .at(daysBefore: 1, hour: 18, minute: 0), .at(daysBefore: 1, hour: 18, minute: 0),
        ], isAllDay: false)
        #expect(result.count == 3)
        #expect(result.contains(.before(amount: 60, unit: .minutes)))
        #expect(result.contains(.at(daysBefore: 1, hour: 18, minute: 0)))
    }

    @Test func normalized_dropsHourOffsetsForAllDay() {
        let result = ReminderOffset.normalized([
            .before(amount: 30, unit: .minutes), .before(amount: 2, unit: .hours), .before(amount: 1, unit: .days),
            .at(daysBefore: 0, hour: 9, minute: 0),
        ], isAllDay: true)
        #expect(result == [.before(amount: 1, unit: .days), .at(daysBefore: 0, hour: 9, minute: 0)])
    }

    @Test func normalized_sortsEarliestFirst() {
        let result = ReminderOffset.normalized([
            .before(amount: 15, unit: .minutes), .before(amount: 1, unit: .weeks), .at(daysBefore: 1, hour: 18, minute: 0),
            .before(amount: 0, unit: .minutes), .before(amount: 2, unit: .hours),
        ], isAllDay: false)
        #expect(result == [
            .before(amount: 1, unit: .weeks), .at(daysBefore: 1, hour: 18, minute: 0), .before(amount: 2, unit: .hours),
            .before(amount: 15, unit: .minutes), .before(amount: 0, unit: .minutes),
        ])
    }

    @Test func normalized_clampsValues() {
        let result = ReminderOffset.normalized([
            .before(amount: 5000, unit: .minutes), .before(amount: -3, unit: .days), .at(daysBefore: 999, hour: 30, minute: 99),
        ], isAllDay: false)
        #expect(result.contains(.before(amount: 999, unit: .minutes)))
        #expect(result.contains(.before(amount: 0, unit: .days)))
        #expect(result.contains(.at(daysBefore: 365, hour: 23, minute: 59)))
    }

    @Test func normalized_keepsAbsoluteAfterRelativeOnes() {
        let date = instant(2026, 11, 1, 8, 0, in: calendar)
        let result = ReminderOffset.normalized([.absolute(date), .before(amount: 1, unit: .days), .absolute(date)], isAllDay: false)
        #expect(result == [.before(amount: 1, unit: .days), .absolute(date)])
    }

    @Test func largestUnit_picksWholeUnits() {
        #expect(ReminderOffset.largestUnit(minutes: 120) == .before(amount: 2, unit: .hours))
        #expect(ReminderOffset.largestUnit(minutes: 2880) == .before(amount: 2, unit: .days))
        #expect(ReminderOffset.largestUnit(minutes: 10080) == .before(amount: 1, unit: .weeks))
        #expect(ReminderOffset.largestUnit(minutes: 90) == .before(amount: 90, unit: .minutes))
        #expect(ReminderOffset.largestUnit(minutes: 15) == .before(amount: 15, unit: .minutes))
        #expect(ReminderOffset.largestUnit(minutes: 0) == .before(amount: 0, unit: .minutes))
    }

    @Test func codable_roundTripsEveryCase() throws {
        let list: [ReminderOffset] = [.before(amount: 2, unit: .weeks), .at(daysBefore: 1, hour: 18, minute: 30),
                                      .absolute(Date(timeIntervalSince1970: 1_800_000_000))]
        let data = try JSONEncoder().encode(list)
        #expect(try JSONDecoder().decode([ReminderOffset].self, from: data) == list)
    }
}
