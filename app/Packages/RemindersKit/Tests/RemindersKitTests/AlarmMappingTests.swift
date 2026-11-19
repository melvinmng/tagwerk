import Foundation
import Testing
import TagwerkCore
@testable import RemindersKit

struct AlarmMappingTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 0, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    @Test func relativeOffset_roundTripsWholeUnits() {
        let anchor = date(20, 14)
        for offset in [ReminderOffset.before(amount: 15, unit: .minutes), .before(amount: 2, unit: .hours),
                       .before(amount: 3, unit: .days), .before(amount: 2, unit: .weeks), .before(amount: 0, unit: .minutes)] {
            let seconds = AlarmMapping.relativeOffset(for: offset, anchor: anchor, isAllDay: false, calendar: calendar)
            #expect(seconds != nil)
            #expect(AlarmMapping.offset(relativeOffset: seconds ?? 1, isAllDay: false) == offset)
        }
    }

    @Test func atDaysBefore_becomesTheDistanceOfThatOccurrence() {
        let seconds = AlarmMapping.relativeOffset(for: .at(daysBefore: 1, hour: 18, minute: 0), anchor: date(20, 10), isAllDay: false,
                                                  calendar: calendar)
        #expect(seconds == TimeInterval(-16 * 3600))
        #expect(AlarmMapping.offset(relativeOffset: -16 * 3600, isAllDay: false) == .before(amount: 16, unit: .hours))
    }

    @Test func atDaysBefore_acrossDaylightSaving_isComputedPerOccurrence() {
        // 25 Oct 2026 has 25 hours: "2 days before at 18:00" is 40 h away for a Friday event and 41 h for the Monday after the change.
        let monday = AlarmMapping.relativeOffset(for: .at(daysBefore: 2, hour: 18, minute: 0), anchor: date(26, 10, month: 10),
                                                 isAllDay: false, calendar: calendar)
        let friday = AlarmMapping.relativeOffset(for: .at(daysBefore: 2, hour: 18, minute: 0), anchor: date(23, 10, month: 10),
                                                 isAllDay: false, calendar: calendar)
        #expect(friday == TimeInterval(-40 * 3600))
        #expect(monday == TimeInterval(-41 * 3600))
    }

    @Test func allDay_eveningBefore_mapsToAtDaysBefore() {
        #expect(AlarmMapping.offset(relativeOffset: -6 * 3600, isAllDay: true) == .at(daysBefore: 1, hour: 18, minute: 0))
        #expect(AlarmMapping.offset(relativeOffset: -(24 + 6) * 3600, isAllDay: true) == .at(daysBefore: 2, hour: 18, minute: 0))
        let seconds = AlarmMapping.relativeOffset(for: .at(daysBefore: 1, hour: 18, minute: 0), anchor: date(20, 11), isAllDay: true,
                                                  calendar: calendar)
        #expect(seconds == TimeInterval(-6 * 3600))
    }

    @Test func allDay_wholeDays_mapToDaysAndWeeks() {
        #expect(AlarmMapping.offset(relativeOffset: -2 * 86_400, isAllDay: true) == .before(amount: 2, unit: .days))
        #expect(AlarmMapping.offset(relativeOffset: -7 * 86_400, isAllDay: true) == .before(amount: 1, unit: .weeks))
        #expect(AlarmMapping.offset(relativeOffset: 0, isAllDay: true) == .before(amount: 0, unit: .days))
    }

    @Test func allDay_positiveOffset_mapsToSameDay() {
        #expect(AlarmMapping.offset(relativeOffset: 9 * 3600, isAllDay: true) == .at(daysBefore: 0, hour: 9, minute: 0))
        #expect(AlarmMapping.offset(relativeOffset: 9 * 3600 + 1800, isAllDay: true) == .at(daysBefore: 0, hour: 9, minute: 30))
        #expect(AlarmMapping.relativeOffset(for: .at(daysBefore: 0, hour: 9, minute: 0), anchor: date(20, 13), isAllDay: true,
                                            calendar: calendar) == TimeInterval(9 * 3600))
    }

    @Test func unrepresentableAlarms_giveNoOffset() {
        #expect(AlarmMapping.offset(relativeOffset: 600, isAllDay: false) == nil)
        #expect(AlarmMapping.offset(relativeOffset: 2 * 86_400, isAllDay: true) == nil)
    }

    @Test func absolute_staysAbsolute() {
        let fixed = ReminderOffset.absolute(date(19, 8))
        #expect(AlarmMapping.relativeOffset(for: fixed, anchor: date(20, 14), isAllDay: false, calendar: calendar) == nil)
    }
}
