import Foundation
import Testing
@testable import TagwerkCore

struct BlockDurationTests {
    let calendar = makeCalendar()
    let day = PlanDay(year: 2026, month: 11, day: 18)

    func planDay(busy: [CalendarEvent] = [], blocks: [Range<Int>] = [], lunch: Range<Int>? = 720..<780) -> PlanInputDay {
        PlanInputDay(day: day, hours: WorkHours(startMinutes: 540, endMinutes: 1080), lunch: lunch, events: busy,
                     linkedEventIDs: [], deadlineCalendarIDs: [], blocks: blocks, recurringMinutes: 0, plannedMinutes: 0,
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

    @Test func largestFreeSlot_dayOff_isZero() {
        var input = planDay()
        input.hours = nil
        #expect(largestFreeSlot(input, fromMinutes: nil) == 0)
    }
}
