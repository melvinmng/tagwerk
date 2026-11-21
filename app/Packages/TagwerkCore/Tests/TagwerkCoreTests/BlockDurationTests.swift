import Foundation
import Testing
@testable import TagwerkCore

struct BlockDurationTests {
    let calendar = makeCalendar()
    let day = PlanDay(year: 2026, month: 11, day: 18)

    func planDay(busy: [CalendarEvent] = [], blocks: [Range<Int>] = [], lunch: Range<Int>? = 720..<780) -> PlanInputDay {
        PlanInputDay(day: day, hours: WorkHours(startMinutes: 540, endMinutes: 1080), lunch: lunch, events: busy,
                     linkedEventIDs: [], deadlineCalendarIDs: [], blocks: blocks, untimedPlannedMinutes: 0,
                     bufferMinutes: 0, calendar: calendar)
    }

    func event(_ from: Int, _ to: Int) -> CalendarEvent {
        CalendarEvent(id: "\(from)", externalID: nil, calendarID: "c", title: "T",
                      start: instant(2026, 11, 18, from), end: instant(2026, 11, 18, to), isAllDay: false, url: nil,
                      isBusy: true, version: "1")
    }

    @Test func noEstimate_usesDefault() {
        #expect(blockMinutes(estimate: nil, alreadyBlocked: 0, defaultMinutes: 30, largestFreeSlot: 300) == 30)
    }

    @Test func estimate_usesRemainingTime() {
        #expect(blockMinutes(estimate: 180, alreadyBlocked: 60, defaultMinutes: 30, largestFreeSlot: 300) == 120)
    }

    @Test func remainingLongerThanLargestSlot_usesSlot() {
        #expect(blockMinutes(estimate: 240, alreadyBlocked: 0, defaultMinutes: 30, largestFreeSlot: 90) == 90)
    }

    @Test func remainingOverSixHours_usesLargestSlotUpToSixHours() {
        #expect(blockMinutes(estimate: 600, alreadyBlocked: 0, defaultMinutes: 30, largestFreeSlot: 240) == 240)
        #expect(blockMinutes(estimate: 600, alreadyBlocked: 0, defaultMinutes: 30, largestFreeSlot: 480) == 360)
    }

    @Test func fullyBlocked_usesDefault() {
        #expect(blockMinutes(estimate: 60, alreadyBlocked: 60, defaultMinutes: 30, largestFreeSlot: 300) == 30)
    }

    @Test func noFreeSlot_keepsRemainingUpToSixHours() {
        #expect(blockMinutes(estimate: 120, alreadyBlocked: 0, defaultMinutes: 30, largestFreeSlot: 0) == 120)
    }

    @Test func largestFreeSlot_betweenEventsLunchAndBlocks() {
        // 9–10 busy, 12–13 lunch, block 14:00–14:30 → free 10–12 (120), 13–14 (60), 14:30–18 (210).
        let input = planDay(busy: [event(9, 10)], blocks: [840..<870])
        #expect(largestFreeSlot(input, fromMinutes: nil) == 210)
        // From 16:00 on only 120 minutes are left.
        #expect(largestFreeSlot(input, fromMinutes: 960) == 120)
    }

    @Test func nextFreeSlot_firstFittingAfterOriginal() {
        // free 10–12, 13–14, 14:30–18; after 10:30, 90 min → 14:30 (10:30–12 has 90 too: first fit wins).
        let input = planDay(busy: [event(9, 10)], blocks: [840..<870])
        #expect(nextFreeSlot(input, after: 630, minutes: 90, fromMinutes: nil) == 630..<720)
        #expect(nextFreeSlot(input, after: 660, minutes: 90, fromMinutes: nil) == 870..<960)
    }

    @Test func nextFreeSlot_noFit_usesLargestShortened() {
        let input = planDay(busy: [event(9, 10)], blocks: [840..<870])
        #expect(nextFreeSlot(input, after: 870, minutes: 300, fromMinutes: nil) == 870..<1080)
        #expect(nextFreeSlot(input, after: 1075, minutes: 30, fromMinutes: nil) == nil)
    }

    @Test func freeGaps_keepBufferAroundBlocks() {
        var input = planDay(blocks: [840..<900], lunch: nil)
        input.bufferMinutes = 10
        #expect(freeGaps(input, fromMinutes: nil) == [540..<830, 910..<1080])
    }

    @Test func largestFreeSlot_dayOff_isZero() {
        var input = planDay()
        input.hours = nil
        #expect(largestFreeSlot(input, fromMinutes: nil) == 0)
    }
}

struct SessionWindowTests {
    let calendar = makeCalendar()
    let today = PlanDay(year: 2026, month: 11, day: 18)

    @Test func daily_countsOnlyToday() {
        #expect(sessionWindowStart(for: .daily(interval: 1), today: today, calendar: calendar) == today)
    }

    @Test func everyThreeDays_countsThreeDays() {
        #expect(sessionWindowStart(for: .daily(interval: 3), today: today, calendar: calendar) == PlanDay(year: 2026, month: 11, day: 16))
    }

    @Test func weekly_countsLastSixDaysAndToday() {
        #expect(sessionWindowStart(for: .weekly(interval: 1, weekdays: [4]), today: today, calendar: calendar)
            == PlanDay(year: 2026, month: 11, day: 12))
    }

    @Test func monthly_countsSinceSameDayLastMonth() {
        #expect(sessionWindowStart(for: .monthly(interval: 1, day: 18), today: today, calendar: calendar)
            == PlanDay(year: 2026, month: 10, day: 19))
    }

    @Test func monthlyWeekday_countsSinceSameDayLastMonth() {
        #expect(sessionWindowStart(for: .monthlyWeekday(interval: 1, ordinal: 3, weekday: 4), today: today, calendar: calendar)
            == PlanDay(year: 2026, month: 10, day: 19))
        #expect(sessionWindowStart(for: .monthlyWeekday(interval: 2, ordinal: 3, weekday: 4), today: today, calendar: calendar)
            == PlanDay(year: 2026, month: 9, day: 19))
    }

    @Test func yearly_countsSinceDayAfterSameDateLastYear() {
        #expect(sessionWindowStart(for: .yearly(interval: 1), today: today, calendar: calendar)
            == PlanDay(year: 2025, month: 11, day: 19))
        #expect(sessionWindowStart(for: .yearly(interval: 2), today: today, calendar: calendar)
            == PlanDay(year: 2024, month: 11, day: 19))
    }

    @Test func unsupported_hasNoWindow() {
        #expect(sessionWindowStart(for: .unsupported, today: today, calendar: calendar) == nil)
    }
}
