import Foundation
import Testing
@testable import TagwerkCore

/// The rules of the day capacity (issue #260): every minute of the working hours counts once.
struct CapacityRulesTests {
    let calendar = makeCalendar()
    let nineToSix = WorkHours(startMinutes: 540, endMinutes: 1080)

    private func input(busy: [Range<Int>] = [], travel: [Range<Int>] = [], blocks: [Range<Int>] = [], untimed: Int = 0,
                       hours: WorkHours? = nil, lunch: Bool = true, now: Int? = nil) -> CapacityInput {
        var result = CapacityInput(hours: hours ?? nineToSix, lunchStartMinutes: lunch ? 720 : 0, lunchMinutes: lunch ? 60 : 0,
                                   bufferMinutes: 10, busyIntervals: busy, untimedPlannedMinutes: untimed, estimatedCount: 0,
                                   travelIntervals: travel, blockIntervals: blocks)
        result.nowMinutes = now
        return result
    }

    private func event(_ id: String, _ start: (Int, Int), _ end: (Int, Int), day: Int = 24, allDay: Bool = false,
                       busy: Bool = true) -> CalendarEvent {
        CalendarEvent(id: id, externalID: nil, calendarID: "c", title: id,
                      start: instant(2026, 11, day, start.0, start.1), end: instant(2026, 11, day, end.0, end.1),
                      isAllDay: allDay, url: nil, isBusy: busy, version: "1")
    }

    // MARK: Blocked time

    @Test func reportedDay_onlyLunchIsBlocked() {
        // Tue 24 Nov: "Away" 12:00–13:00 lies completely in the lunch break and gets no buffer.
        let result = capacity(input(busy: [720..<780]))
        #expect(result.availableMinutes == 480)
        #expect(result.freeMinutes == 480)
        #expect(result.breakdown.eventMinutes == 0)
        #expect(result.breakdown.lunchMinutes == 60)
    }

    /// The day from the report: two all-day events (one "Away"), "Selbststudium" 8:00–18:00 free, "Away" 12:00–13:00 busy,
    /// "RT Young Generation" 18:30–22:00 free, lunch 12:00–13:00, default hours 9:00–18:00, buffer 10 min.
    @Test func reportedDay_isEightHoursFreeOfEight() {
        let day = PlanDay(year: 2026, month: 11, day: 24)
        let events = [
            event("Away (all day)", (0, 0), (23, 59), allDay: true),
            event("Birthday", (0, 0), (23, 59), allDay: true),
            event("Selbststudium", (8, 0), (18, 0), busy: false),
            event("Away", (12, 0), (13, 0)),
            event("RT Young Generation", (18, 30), (22, 0), busy: false)
        ]
        let intervals = busyIntervals(events: events, on: day, calendar: calendar, excluding: [])
        #expect(intervals == [720..<780])
        let result = capacity(input(busy: intervals))
        #expect(result.freeMinutes == 480)
        #expect(result.availableMinutes == 480)
        #expect(result.plannedMinutes == 0)
        #expect(!result.isOverbooked)
    }

    @Test func eventPartlyInLunch_keepsBuffer() {
        #expect(capacity(input(busy: [690..<750])).availableMinutes == 440)
    }

    @Test func overlappingEvents_countOnce() {
        // 10:00–11:00 and 10:30–11:30 with buffer: 09:50–11:40 = 110 min.
        #expect(capacity(input(busy: [600..<660, 630..<690])).availableMinutes == 370)
    }

    @Test func sameEventInTwoCalendars_countsOnce() {
        #expect(capacity(input(busy: [600..<660, 600..<660])).availableMinutes == 400)
    }

    @Test func eventOutsideWindow_changesNothing() {
        #expect(capacity(input(busy: [1110..<1320])).availableMinutes == 480)
    }

    @Test func eventAcrossWindowEnd_countsInsidePart() {
        // 17:30–19:00 with buffer 17:20–19:10; inside the hours 17:20–18:00 = 40 min.
        #expect(capacity(input(busy: [1050..<1140])).availableMinutes == 440)
    }

    @Test func eventInsideTravel_getsNoBuffer() {
        // Trip 10:00–11:00; the event 10:10–10:50 inside it blocks nothing more.
        #expect(capacity(input(busy: [610..<650], travel: [600..<660])).availableMinutes == 420)
    }

    @Test func eventInsideReturnTrip_getsNoBuffer() {
        let result = capacity(input(busy: [850..<890], travel: [840..<900]))
        #expect(result.availableMinutes == 420)
        #expect(result.breakdown.travelMinutes == 60)
        #expect(result.breakdown.eventMinutes == 0)
    }

    // MARK: Load

    @Test func reservedEffort_takesNoTimeWithoutBlocks() {
        // Recurring effort never reaches the capacity; with no block and no task the day stays free.
        let result = capacity(input(busy: [720..<780]))
        #expect(result.plannedMinutes == 0)
        #expect(result.freeMinutes == 480)
    }

    @Test func overlappingBlocks_countOnce() {
        let result = capacity(input(blocks: [600..<660, 630..<690]))
        #expect(result.breakdown.blockMinutes == 90)
        #expect(result.plannedMinutes == 90)
    }

    @Test func blockOutsideWindow_usesNoFreeTime() {
        let result = capacity(input(blocks: [1140..<1200]))
        #expect(result.breakdown.blockMinutes == 0)
        #expect(result.breakdown.outsideBlockMinutes == 60)
        #expect(result.freeMinutes == 480)
    }

    @Test func blockInLunch_countsOnlyOutsidePart() {
        let result = capacity(input(blocks: [750..<810]))
        #expect(result.breakdown.blockMinutes == 30)
        #expect(result.freeMinutes == 450)
    }

    @Test func blockInsideEvent_countsOnlyOutsidePart() {
        // The event 10:00–11:00 blocks 09:50–11:10; the block 10:30–11:30 adds 11:10–11:30.
        let result = capacity(input(busy: [600..<660], blocks: [630..<690]))
        #expect(result.breakdown.blockMinutes == 20)
    }

    @Test func blocksAndTasksWithoutTime_addUp() {
        let result = capacity(input(blocks: [600..<660], untimed: 45))
        #expect(result.plannedMinutes == 105)
        #expect(result.freeMinutes == 375)
    }

    @Test func blocksBeyondTheDay_areOverbooked() {
        let result = capacity(input(blocks: [540..<1080], untimed: 120))
        #expect(result.freeMinutes == -120)  // 480 min block time outside lunch + 120 min of tasks
        #expect(result.isOverbooked)
    }

    // MARK: Breakdown

    @Test func breakdown_partsAddUpToWindow() {
        let value = input(busy: [600..<660, 1000..<1100], travel: [570..<600], blocks: [900..<960, 1070..<1200], untimed: 30)
        let result = capacity(value)
        let parts = result.breakdown
        #expect(parts.lunchMinutes == 60)
        #expect(parts.travelMinutes + parts.eventMinutes + parts.lunchMinutes == parts.windowMinutes - result.availableMinutes)
        #expect(parts.lunchMinutes + parts.travelMinutes + parts.eventMinutes + parts.blockMinutes + result.freeMinutes + parts.untimedMinutes
                == parts.windowMinutes)
    }

    @Test func breakdown_blockedPartsFollowTheOrderLunchTravelEvents() {
        // Trip 11:30–12:30 overlaps the lunch break 12:00–13:00; the event 13:20–14:00 has its buffer 13:10–14:10.
        let result = capacity(input(busy: [800..<840], travel: [690..<750]))
        #expect(result.breakdown.lunchMinutes == 60)
        #expect(result.breakdown.travelMinutes == 30)
        #expect(result.breakdown.eventMinutes == 60)
    }

    // MARK: Today

    @Test func today_countsBlocksAheadOnly() {
        let result = capacity(input(blocks: [600..<660, 900..<960], now: 840))
        #expect(result.remainingMinutes == 180)
    }

    @Test func today_blockOutsideWindowIsIgnored() {
        #expect(capacity(input(blocks: [1100..<1160], now: 840)).remainingMinutes == 240)
    }

    // MARK: Free marks

    @Test func freedMinutes_overlappingEvents_giveBackTheUnion() {
        let value = input(busy: [600..<660, 630..<690])
        #expect(freedMinutes(value, removing: [600..<660, 630..<690]) == 110)
        // A single one of them leaves the other blocking.
        #expect(freedMinutes(value, removing: [600..<660]) == 110 - 80)
    }

    @Test func freedMinutes_withTravelOfTheDayWithoutTheEvent_givesBackTheTripToo() {
        let value = input(busy: [840..<900], travel: [815..<840])
        // Blocked: trip 13:35–14:00 and the event with buffer 13:50–15:10 = 13:35–15:10 = 95 min.
        #expect(freedMinutes(value, removing: [840..<900]) == 70)  // the trip still blocks 25 min
        #expect(freedMinutes(value, removing: [840..<900], travelIntervals: []) == 95)
    }

    @Test func freedMinutes_eventInLunch_givesNothing() {
        #expect(freedMinutes(input(busy: [720..<780]), removing: [720..<780]) == 0)
    }

    @Test func freedMinutes_eventOutsideWindow_givesNothing() {
        #expect(freedMinutes(input(busy: [1110..<1320]), removing: [1110..<1320]) == 0)
    }

    @Test func freedMinutes_matchesTheCardAfterwards() {
        let value = input(busy: [600..<660, 630..<690, 700..<720])
        let freed = freedMinutes(value, removing: [630..<690])
        var after = value
        after.busyIntervals.remove(at: 1)
        #expect(capacity(after).freeMinutes - capacity(value).freeMinutes == freed)
    }

    // MARK: Events of the day

    @Test func busyIntervals_eventAcrossMidnight_isSplit() {
        let overnight = CalendarEvent(id: "n", externalID: nil, calendarID: "c", title: "Nacht",
                                      start: instant(2026, 11, 23, 23, 0), end: instant(2026, 11, 24, 1, 0),
                                      isAllDay: false, url: nil, isBusy: true, version: "1")
        let day = PlanDay(year: 2026, month: 11, day: 24)
        #expect(busyIntervals(events: [overnight], on: day, calendar: calendar, excluding: []) == [0..<60])
        #expect(busyIntervals(events: [overnight], on: day.adding(days: -1, calendar: calendar), calendar: calendar,
                              excluding: []) == [1380..<1440])
    }

    // MARK: AI input

    private func planDay(events: [CalendarEvent] = [], blocks: [Range<Int>] = [], travel: [Range<Int>] = [],
                         untimed: Int = 0) -> PlanInputDay {
        PlanInputDay(day: PlanDay(year: 2026, month: 11, day: 24), hours: nineToSix, lunch: 720..<780, events: events,
                     linkedEventIDs: [], deadlineCalendarIDs: [], blocks: blocks, untimedPlannedMinutes: untimed,
                     bufferMinutes: 10, calendar: calendar, travel: travel)
    }

    @Test func planInput_reportedDay_matchesTheCard() {
        let day = planDay(events: [event("Away", (12, 0), (13, 0)), event("Selbststudium", (8, 0), (18, 0), busy: false)])
        #expect(day.availableMinutes == 480)
        #expect(day.plannedMinutes == 0)
        #expect(freeGaps(day, fromMinutes: nil).reduce(0) { $0 + $1.count } == 480)
    }

    @Test func planInput_withTravel_hasTheFreeMinutesOfTheCard() {
        let day = planDay(travel: [600..<630])
        #expect(day.availableMinutes == 450)
        #expect(freeGaps(day, fromMinutes: nil) == [540..<600, 630..<720, 780..<1080])
        #expect(freeGaps(day, fromMinutes: nil).reduce(0) { $0 + $1.count } == day.availableMinutes)
    }

    @Test func planInput_eventInLunch_keepsNoBufferInTheGaps() {
        let day = planDay(events: [event("Away", (12, 0), (13, 0))])
        #expect(freeGaps(day, fromMinutes: nil) == [540..<720, 780..<1080])
    }

    @Test func planInput_loadCountsBlocksOnceAndTasksWithoutTime() {
        let day = planDay(blocks: [600..<660, 630..<690, 1140..<1200], untimed: 30)
        #expect(day.plannedMinutes == 90 + 30)
    }

    @Test func planInput_withHours_countsBlocksInTheNewHours() {
        let day = planDay(blocks: [1090..<1150], untimed: 30)
        #expect(day.plannedMinutes == 30)
        let longer = day.withHours(WorkHours(startMinutes: 540, endMinutes: 1200))
        #expect(longer.plannedMinutes == 90)
        #expect(longer.availableMinutes == 600)
    }
}
