import Foundation
import Testing
@testable import TagwerkCore

struct ReminderChoicesTests {
    @Test func common_withTime() {
        #expect(ReminderChoices.common(isAllDay: false) == [
            .before(amount: 0, unit: .minutes), .before(amount: 15, unit: .minutes), .before(amount: 1, unit: .hours),
            .before(amount: 1, unit: .days), .before(amount: 1, unit: .weeks),
        ])
    }

    @Test func common_withoutTime() {
        #expect(ReminderChoices.common(isAllDay: true) == [
            .before(amount: 0, unit: .days), .before(amount: 1, unit: .days), .before(amount: 1, unit: .weeks),
        ])
    }

    @Test func rows_containCommonAndSelected_once() {
        let own = ReminderOffset.at(daysBefore: 1, hour: 18, minute: 0)
        let rows = ReminderChoices.rows(selected: [own, .before(amount: 60, unit: .minutes), .before(amount: 1, unit: .days)], isAllDay: false)
        #expect(rows.count == 6)
        #expect(rows.filter { $0 == own }.count == 1)
        // 60 minutes is the same distance as the common "1 hour": one row, the common spelling.
        #expect(rows.contains(.before(amount: 1, unit: .hours)))
        #expect(!rows.contains(.before(amount: 60, unit: .minutes)))
    }

    @Test func rows_areOrderedFromTheNearestReminderToTheFarthest() {
        let rows = ReminderChoices.rows(selected: [.at(daysBefore: 1, hour: 18, minute: 0)], isAllDay: false)
        #expect(rows == [
            .before(amount: 0, unit: .minutes), .before(amount: 15, unit: .minutes), .before(amount: 1, unit: .hours),
            .at(daysBefore: 1, hour: 18, minute: 0), .before(amount: 1, unit: .days), .before(amount: 1, unit: .weeks),
        ])
    }

    @Test func rows_allDay_haveNoHourDistances() {
        let rows = ReminderChoices.rows(selected: [.before(amount: 2, unit: .hours), .at(daysBefore: 0, hour: 9, minute: 0)], isAllDay: true)
        #expect(rows == [
            .at(daysBefore: 0, hour: 9, minute: 0), .before(amount: 0, unit: .days), .before(amount: 1, unit: .days),
            .before(amount: 1, unit: .weeks),
        ])
    }

    @Test func rows_keepAbsoluteAlarms() {
        let alarm = ReminderOffset.absolute(Date(timeIntervalSince1970: 1_800_000_000))
        let rows = ReminderChoices.rows(selected: [alarm], isAllDay: false)
        #expect(rows.last == alarm)
        #expect(rows.count == 6)
    }
}
