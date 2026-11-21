import Foundation
import Testing
@testable import TagwerkCore

struct PlanDayTests {
    @Test func planDay_survivesTimeZoneChange() {
        let day = PlanDay(year: 2026, month: 11, day: 20)
        let newYork = makeCalendar("America/New_York")
        #expect(PlanDay(date: day.startDate(in: newYork), calendar: newYork) == day)
        #expect(newYork.component(.day, from: day.startDate(in: newYork)) == 20)
    }

    @Test func planDay_addingAcrossDST_isCalendarDay() {
        let calendar = makeCalendar()
        let next = PlanDay(year: 2026, month: 3, day: 28).adding(days: 1, calendar: calendar)
        #expect(next == PlanDay(year: 2026, month: 3, day: 29))
        #expect(calendar.component(.hour, from: next.startDate(in: calendar)) == 0)
    }

    @Test func planDay_weekdayAndOrdering() {
        let calendar = makeCalendar()
        #expect(PlanDay(year: 2026, month: 11, day: 18).weekday(in: calendar) == 4)  // Wednesday
        #expect(PlanDay(year: 2026, month: 11, day: 30) < PlanDay(year: 2026, month: 12, day: 1))
        #expect(PlanDay(DueDate(year: 2026, month: 11, day: 20, hour: 9, minute: 0)) == PlanDay(year: 2026, month: 11, day: 20))
    }
}

struct WorkScheduleTests {
    let calendar = makeCalendar()

    @Test func workHours_standardWeek() {
        #expect(workHours(on: PlanDay(year: 2026, month: 11, day: 18), schedule: .standard, overrides: [:], calendar: calendar)
                == WorkHours(startMinutes: 540, endMinutes: 1080))
        #expect(workHours(on: PlanDay(year: 2026, month: 11, day: 21), schedule: .standard, overrides: [:], calendar: calendar) == nil)
    }

    @Test func workHours_overrideWins() {
        let saturday = PlanDay(year: 2026, month: 11, day: 21)
        let wednesday = PlanDay(year: 2026, month: 11, day: 18)
        let overrides: [PlanDay: DayOverride] = [saturday: .hours(WorkHours(startMinutes: 600, endMinutes: 1200)), wednesday: .off]
        #expect(workHours(on: saturday, schedule: .standard, overrides: overrides, calendar: calendar)
                == WorkHours(startMinutes: 600, endMinutes: 1200))
        #expect(workHours(on: wednesday, schedule: .standard, overrides: overrides, calendar: calendar) == nil)
    }

    @Test func weekSchedule_codableRoundTrip() throws {
        let data = try JSONEncoder().encode(WeekSchedule.standard)
        #expect(try JSONDecoder().decode(WeekSchedule.self, from: data) == .standard)
    }
}

struct CapacityTests {
    let nineToSix = WorkHours(startMinutes: 540, endMinutes: 1080)

    private func input(busy: [Range<Int>] = [], blocks: [Range<Int>] = [], untimed: Int = 0,
                       hours: WorkHours? = nil) -> CapacityInput {
        CapacityInput(hours: hours ?? nineToSix, lunchStartMinutes: 720, lunchMinutes: 60, bufferMinutes: 10,
                      busyIntervals: busy, untimedPlannedMinutes: untimed, estimatedCount: 0, blockIntervals: blocks)
    }

    @Test func capacity_noEvents() {
        #expect(capacity(input()).availableMinutes == 480)
    }

    @Test func capacity_eventWithBuffer() {
        #expect(capacity(input(busy: [600..<660])).availableMinutes == 400)
    }

    @Test func capacity_adjacentEventsShareBuffer() {
        #expect(capacity(input(busy: [600..<660, 660..<720])).availableMinutes == 350)
    }

    @Test func capacity_eventOverlappingLunch() {
        #expect(capacity(input(busy: [690..<750])).availableMinutes == 440)
    }

    @Test func capacity_untimedAndBlocksAreLoad() {
        // 120 min of tasks without a time and a block of 3 h: 480 available, 300 planned.
        let result = capacity(input(blocks: [840..<1020], untimed: 120))
        #expect(result.availableMinutes == 480)
        #expect(result.plannedMinutes == 300)
        #expect(result.freeMinutes == 180)
        #expect(!result.isOverbooked)
    }

    @Test func capacity_overbooked() {
        let result = capacity(input(untimed: 540))
        #expect(result.freeMinutes == -60)
        #expect(result.isOverbooked)
    }

    private func now(_ minutes: Int, busy: [Range<Int>] = [], blocks: [Range<Int>] = [], untimed: Int = 0) -> DayCapacity {
        var value = input(busy: busy, blocks: blocks, untimed: untimed)
        value.nowMinutes = minutes
        return capacity(value)
    }

    @Test func capacity_withNow_countsOnlyRemainingWorkTime() {
        let result = now(14 * 60)
        #expect(result.remainingMinutes == 240)
        #expect(result.availableMinutes == 480)
    }

    @Test func capacity_withNow_partOfRunningEventAndBuffer() {
        #expect(now(14 * 60, busy: [810..<900]).remainingMinutes == 170)  // 14:00–15:10 blocked
    }

    @Test func capacity_withNow_subtractsUntimedInFullAndBlocksAhead() {
        // Block 13:00–15:00 is half over at 14:00; 30 min of tasks without a time still wait.
        #expect(now(14 * 60, blocks: [780..<900], untimed: 30).remainingMinutes == 240 - 60 - 30)
    }

    @Test func capacity_nowAfterWork_remainingZero() {
        #expect(now(19 * 60).remainingMinutes == 0)
    }

    @Test func capacity_nowBeforeWork_remainingEqualsAvailable() {
        #expect(now(7 * 60).remainingMinutes == 480)
    }

    @Test func capacity_withoutNow_hasNoRemaining() {
        #expect(capacity(input()).remainingMinutes == nil)
    }

    @Test func capacity_dayOff() {
        let result = capacity(CapacityInput(hours: nil, lunchStartMinutes: 720, lunchMinutes: 60, bufferMinutes: 10,
                                            busyIntervals: [], untimedPlannedMinutes: 30, estimatedCount: 1))
        #expect(result.availableMinutes == 0)
        #expect(result.isDayOff)
        #expect(result.isOverbooked)
    }

    @Test func busyIntervals_skipsAllDayFreeAndLinked() {
        let calendar = makeCalendar()
        let day = PlanDay(year: 2026, month: 11, day: 18)
        func event(_ id: String, _ start: Int, _ end: Int, allDay: Bool = false, busy: Bool = true) -> CalendarEvent {
            CalendarEvent(id: id, externalID: nil, calendarID: "c", title: id,
                          start: instant(2026, 11, 18, start / 60, start % 60), end: instant(2026, 11, 18, end / 60, end % 60),
                          isAllDay: allDay, url: nil, isBusy: busy, version: "1")
        }
        let events = [event("a", 600, 660), event("b", 0, 1439, allDay: true), event("c", 700, 760, busy: false), event("d", 800, 860)]
        #expect(busyIntervals(events: events, on: day, calendar: calendar, excluding: ["d"]) == [600..<660])
    }

    @Test func busyIntervals_clipsMultiDayEvent() {
        let calendar = makeCalendar()
        let event = CalendarEvent(id: "n", externalID: nil, calendarID: "c", title: "Nacht",
                                  start: instant(2026, 11, 17, 22, 0), end: instant(2026, 11, 18, 2, 0),
                                  isAllDay: false, url: nil, isBusy: true, version: "1")
        #expect(busyIntervals(events: [event], on: PlanDay(year: 2026, month: 11, day: 18), calendar: calendar, excluding: []) == [0..<120])
    }
}
