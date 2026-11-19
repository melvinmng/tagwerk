import Foundation
import Testing
@testable import TagwerkCore

struct NowMarkerTests {
    let calendar = makeCalendar()
    let today = PlanDay(year: 2026, month: 11, day: 19)

    @Test func alignsOnOpening_firstOpenOnToday_aligns() {
        #expect(NowMarker.alignsOnOpening(openedDay: nil, shownDay: today, today: today))
        #expect(NowMarker.alignsOnOpening(openedDay: today, shownDay: today, today: today))
    }

    @Test func alignsOnOpening_firstOpenOnAnotherDay_doesNot() {
        let tomorrow = today.adding(days: 1, calendar: calendar)
        #expect(!NowMarker.alignsOnOpening(openedDay: nil, shownDay: tomorrow, today: today))
    }

    @Test func alignsOnOpening_afterPagingToTodayFromAnotherDay_doesNot() {
        let yesterday = today.adding(days: -1, calendar: calendar)
        #expect(!NowMarker.alignsOnOpening(openedDay: yesterday, shownDay: today, today: today))
    }

    @Test func alignsOnOpening_afterPagingAwayFromToday_doesNot() {
        let tomorrow = today.adding(days: 1, calendar: calendar)
        #expect(!NowMarker.alignsOnOpening(openedDay: today, shownDay: tomorrow, today: today))
    }

    @Test func minutes_today_returnsMinutesSinceMidnight() {
        let now = instant(2026, 11, 19, 14, 32)
        #expect(NowMarker.minutes(now: now, day: today, calendar: calendar) == 14 * 60 + 32)
    }

    @Test func minutes_otherDay_isNil() {
        let now = instant(2026, 11, 19, 14, 32)
        #expect(NowMarker.minutes(now: now, day: today.adding(days: 1, calendar: calendar), calendar: calendar) == nil)
        #expect(NowMarker.minutes(now: now, day: today.adding(days: -1, calendar: calendar), calendar: calendar) == nil)
    }

    @Test func minutes_justAfterMidnight_belongsToTheNewDay() {
        // 23:59 is still the old day, 00:00 already the next: the line leaves the old day at midnight.
        let before = instant(2026, 11, 19, 23, 59)
        let after = instant(2026, 11, 20, 0, 0)
        #expect(NowMarker.minutes(now: before, day: today, calendar: calendar) == 1439)
        #expect(NowMarker.minutes(now: after, day: today, calendar: calendar) == nil)
        #expect(NowMarker.minutes(now: after, day: PlanDay(year: 2026, month: 11, day: 20), calendar: calendar) == 0)
    }

    @Test func minutes_onDaylightSavingDay_usesWallClock() {
        // 2026-03-29: clocks jump from 02:00 to 03:00 in Berlin; 10:30 wall clock is 9.5 elapsed hours after midnight.
        let day = PlanDay(year: 2026, month: 3, day: 29)
        let now = instant(2026, 3, 29, 10, 30)
        #expect(NowMarker.minutes(now: now, day: day, calendar: calendar) == 10 * 60 + 30)
    }

    @Test func position_outsideShownRange_isNil() {
        let shown = 480..<1140
        #expect(NowMarker.position(nowMinutes: 479, shown: shown) == nil)
        #expect(NowMarker.position(nowMinutes: 1140, shown: shown) == nil)
        #expect(NowMarker.position(nowMinutes: 0, shown: shown) == nil)
    }

    @Test func position_insideRange_returnsMinutes() {
        #expect(NowMarker.position(nowMinutes: 480, shown: 480..<1140) == 480)
        #expect(NowMarker.position(nowMinutes: 872, shown: 480..<1140) == 872)
    }

    @Test func insertionIndex_beforeFirstFutureRow() {
        // 09:00, 11:00, 15:00 and it is 12:00: the line goes before the 15:00 row.
        #expect(NowMarker.insertionIndex(rowStarts: [540, 660, 900], nowMinutes: 720) == 2)
    }

    @Test func insertionIndex_afterRunningRow() {
        // The 11:00 row is running at 11:30; the line stays after it, before the 15:00 row.
        #expect(NowMarker.insertionIndex(rowStarts: [540, 660, 900], nowMinutes: 690) == 2)
        // A row that starts exactly now counts as running.
        #expect(NowMarker.insertionIndex(rowStarts: [540, 660, 900], nowMinutes: 660) == 2)
    }

    @Test func insertionIndex_afterAllRows_isCount() {
        #expect(NowMarker.insertionIndex(rowStarts: [540, 660, 900], nowMinutes: 1200) == 3)
    }

    @Test func insertionIndex_beforeAllRows_isZero() {
        #expect(NowMarker.insertionIndex(rowStarts: [540, 660], nowMinutes: 300) == 0)
    }

    @Test func insertionIndex_emptyList_isZero() {
        #expect(NowMarker.insertionIndex(rowStarts: [], nowMinutes: 720) == 0)
    }

    @Test func scrollTarget_putsNowAtAThirdOfTheViewport() {
        // Grid 08:00-19:00, 64 pt per hour, now 14:00: 6 h * 64 + 8 inset + 200 canvas top = 592; minus 600/3.
        let offset = NowMarker.scrollTarget(nowMinutes: 840, shown: 480..<1140, hourHeight: 64, inset: 8,
                                            canvasTop: 200, viewportHeight: 600)
        #expect(offset == 392)
    }

    @Test func scrollTarget_clampsAtTop() {
        let offset = NowMarker.scrollTarget(nowMinutes: 490, shown: 480..<1140, hourHeight: 64, inset: 8,
                                            canvasTop: 100, viewportHeight: 900)
        #expect(offset == 0)
    }
}
