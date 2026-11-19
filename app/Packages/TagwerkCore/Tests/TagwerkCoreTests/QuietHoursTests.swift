import Foundation
import Testing
@testable import TagwerkCore

struct QuietHoursTests {
    let calendar = makeCalendar()
    /// 23:00 to 07:00, across midnight.
    let night = QuietHours(startMinutes: 23 * 60, endMinutes: 7 * 60)
    /// 12:00 to 14:00, within one day.
    let noon = QuietHours(startMinutes: 12 * 60, endMinutes: 14 * 60)

    private func at(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, year: Int = 2026) -> Date {
        instant(year, month, day, hour, minute, in: calendar)
    }

    // MARK: Membership

    @Test func sameDayWindow_startInclusiveEndExclusive() {
        #expect(!noon.contains(at(11, 18, 11, 59), calendar: calendar))
        #expect(noon.contains(at(11, 18, 12, 0), calendar: calendar))
        #expect(noon.contains(at(11, 18, 13, 59), calendar: calendar))
        #expect(!noon.contains(at(11, 18, 14, 0), calendar: calendar))
    }

    @Test func windowAcrossMidnight_coversBothSides() {
        #expect(!night.contains(at(11, 18, 22, 59), calendar: calendar))
        #expect(night.contains(at(11, 18, 23, 0), calendar: calendar))
        #expect(night.contains(at(11, 19, 0, 0), calendar: calendar))
        #expect(night.contains(at(11, 19, 6, 59), calendar: calendar))
        #expect(!night.contains(at(11, 19, 7, 0), calendar: calendar))
        #expect(!night.contains(at(11, 19, 12, 0), calendar: calendar))
    }

    @Test func seconds_doNotMoveTheEdges() {
        // 06:59:59 still belongs to the window, 07:00:30 does not.
        #expect(night.contains(at(11, 19, 6, 59).addingTimeInterval(59), calendar: calendar))
        #expect(!night.contains(at(11, 19, 7, 0).addingTimeInterval(30), calendar: calendar))
    }

    @Test func startEqualsEnd_isNoWindow() {
        let empty = QuietHours(startMinutes: 420, endMinutes: 420)
        #expect(empty.isEmpty)
        #expect(!empty.contains(at(11, 18, 7, 0), calendar: calendar))
        #expect(!empty.contains(at(11, 18, 3, 0), calendar: calendar))
        #expect(empty.shifted(at(11, 18, 7, 0), calendar: calendar) == at(11, 18, 7, 0))
        #expect(empty.nextEnd(after: at(11, 18, 3, 0), calendar: calendar) == nil)
        #expect(!night.isEmpty)
    }

    @Test func minutes_areNormalizedIntoOneDay() {
        let window = QuietHours(startMinutes: 1440 + 60, endMinutes: -60)
        #expect(window == QuietHours(startMinutes: 60, endMinutes: 1380))
    }

    // MARK: Shifting

    @Test func outsideTheWindow_isUnchanged() {
        let date = at(11, 18, 15, 30)
        #expect(night.shifted(date, calendar: calendar) == date)
        #expect(night.shifted(at(11, 19, 7, 0), calendar: calendar) == at(11, 19, 7, 0))
    }

    @Test func beforeMidnight_movesToNextMorning() {
        #expect(night.shifted(at(11, 18, 23, 30), calendar: calendar) == at(11, 19, 7, 0))
        #expect(night.shifted(at(11, 18, 23, 0), calendar: calendar) == at(11, 19, 7, 0))
    }

    @Test func afterMidnight_movesToSameMorning() {
        #expect(night.shifted(at(11, 19, 0, 0), calendar: calendar) == at(11, 19, 7, 0))
        #expect(night.shifted(at(11, 19, 3, 15), calendar: calendar) == at(11, 19, 7, 0))
        #expect(night.shifted(at(11, 19, 6, 59), calendar: calendar) == at(11, 19, 7, 0))
    }

    @Test func sameDayWindow_movesToItsEnd() {
        #expect(noon.shifted(at(11, 18, 12, 0), calendar: calendar) == at(11, 18, 14, 0))
        #expect(noon.shifted(at(11, 18, 13, 59), calendar: calendar) == at(11, 18, 14, 0))
    }

    @Test func monthAndYearBoundary_areCrossed() {
        #expect(night.shifted(at(12, 31, 23, 30), calendar: calendar) == at(1, 1, 7, 0, year: 2027))
    }

    @Test func nextEnd_isStrictlyAfterTheDate() {
        #expect(night.nextEnd(after: at(11, 19, 7, 0), calendar: calendar) == at(11, 20, 7, 0))
        #expect(night.nextEnd(after: at(11, 19, 6, 0), calendar: calendar) == at(11, 19, 7, 0))
        #expect(night.nextEnd(after: at(11, 19, 12, 0), calendar: calendar) == at(11, 20, 7, 0))
    }

    // MARK: Daylight saving time, Europe/Berlin (29 March and 25 October 2026)

    @Test func springForward_windowEndStaysAtLocalSeven() {
        // The night of 28 to 29 March has 7 hours: 23:30 CET to 07:00 CEST is 6.5 hours, not 7.5.
        let fire = at(3, 28, 23, 30)
        let shifted = night.shifted(fire, calendar: calendar)
        #expect(shifted == at(3, 29, 7, 0))
        #expect(shifted.timeIntervalSince(fire) == 6.5 * 3600)
    }

    @Test func springForward_dateInsideTheNight_movesToSeven() {
        // 01:30 CET exists; 02:00 to 03:00 does not.
        #expect(night.shifted(at(3, 29, 1, 30), calendar: calendar) == at(3, 29, 7, 0))
        #expect(night.contains(at(3, 29, 3, 0), calendar: calendar))
        #expect(!night.contains(at(3, 29, 7, 0), calendar: calendar))
    }

    @Test func fallBack_windowEndStaysAtLocalSeven() {
        // The night of 24 to 25 October has 9 hours: 23:30 CEST to 07:00 CET is 7.5 hours on the clock, 8.5 elapsed.
        let fire = at(10, 24, 23, 30)
        let shifted = night.shifted(fire, calendar: calendar)
        #expect(shifted == at(10, 25, 7, 0))
        #expect(shifted.timeIntervalSince(fire) == 8.5 * 3600)
    }

    @Test func fallBack_repeatedHourInsideTheNight_movesToSeven() {
        let firstTwoThirty = at(10, 25, 2, 30)  // 02:30 CEST, the first of two
        #expect(night.contains(firstTwoThirty, calendar: calendar))
        #expect(night.shifted(firstTwoThirty, calendar: calendar) == at(10, 25, 7, 0))
        let secondTwoThirty = firstTwoThirty.addingTimeInterval(3600)  // 02:30 CET
        #expect(calendar.dateComponents([.hour, .minute], from: secondTwoThirty).hour == 2)
        #expect(night.shifted(secondTwoThirty, calendar: calendar) == at(10, 25, 7, 0))
    }

    @Test func endInsideTheSkippedHour_movesToTheNextValidTime() {
        // A window that ends at 02:30 on the night that has no 02:30: the end becomes 03:00 CEST, outside the window.
        let window = QuietHours(startMinutes: 22 * 60, endMinutes: 2 * 60 + 30)
        let shifted = window.shifted(at(3, 28, 23, 0), calendar: calendar)
        #expect(shifted == at(3, 29, 3, 0))
        #expect(!window.contains(shifted, calendar: calendar))
    }

    @Test func endInsideTheRepeatedHour_usesTheFirstOccurrence() {
        let window = QuietHours(startMinutes: 22 * 60, endMinutes: 2 * 60 + 30)
        let shifted = window.shifted(at(10, 24, 23, 0), calendar: calendar)
        #expect(shifted == at(10, 25, 2, 30))
        #expect(!window.contains(shifted, calendar: calendar))
    }

    @Test func shiftedDate_isNeverInsideTheWindow_acrossTheYear() {
        // Every 25 minutes through 2026, including both transitions.
        var date = at(1, 1, 0, 0)
        let end = at(12, 31, 23, 59)
        while date < end {
            let shifted = night.shifted(date, calendar: calendar)
            #expect(shifted >= date)
            #expect(!night.contains(shifted, calendar: calendar))
            #expect(shifted.timeIntervalSince(date) <= 24 * 3600)
            date = date.addingTimeInterval(25 * 60)
        }
    }

    // MARK: Window from settings

    @Test func resolved_followsTheSwitchesAndBedtime() {
        #expect(QuietHours.resolved(enabled: false, startsAtBedtime: true, bedtimeMinutes: 1380, startMinutes: 1320,
                                    endMinutes: 420) == nil)
        #expect(QuietHours.resolved(enabled: true, startsAtBedtime: true, bedtimeMinutes: 1350, startMinutes: 1320,
                                    endMinutes: 420) == QuietHours(startMinutes: 1350, endMinutes: 420))
        #expect(QuietHours.resolved(enabled: true, startsAtBedtime: false, bedtimeMinutes: 1350, startMinutes: 1320,
                                    endMinutes: 420) == QuietHours(startMinutes: 1320, endMinutes: 420))
    }

    @Test func resolved_emptyWindowIsNil() {
        #expect(QuietHours.resolved(enabled: true, startsAtBedtime: true, bedtimeMinutes: 420, startMinutes: 1320,
                                    endMinutes: 420) == nil)
    }
}
