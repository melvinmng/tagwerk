import Foundation
import Testing
@testable import TagwerkCore

/// Travel time in the capacity and in the AI planning input (#168).
struct TravelCapacityTests {
    let calendar = makeCalendar()
    let today = PlanDay(year: 2026, month: 11, day: 18)
    let hours = WorkHours(startMinutes: 540, endMinutes: 1080)  // 09:00-18:00

    private func input(busy: [Range<Int>] = [], travel: [Range<Int>] = [], buffer: Int = 0,
                       now: Int? = nil) -> CapacityInput {
        var result = CapacityInput(hours: hours, lunchStartMinutes: 0, lunchMinutes: 0, bufferMinutes: buffer,
                                   busyIntervals: busy, recurringMinutes: 0, plannedMinutes: 0, estimatedCount: 0,
                                   travelIntervals: travel)
        result.nowMinutes = now
        return result
    }

    // MARK: Capacity

    @Test func travelInterval_reducesAvailableMinutes() {
        let without = capacity(input())
        let with = capacity(input(travel: [600..<630]))
        #expect(without.availableMinutes - with.availableMinutes == 30)
    }

    @Test func travelOverlappingBuffer_countsOnce() {
        // The meeting 10:00-11:00 with 15 minutes buffer blocks 09:45-11:15; the trip 09:30-10:00 reaches into it.
        // The union is 09:30-11:15 = 105 minutes, not 75 + 30.
        let result = capacity(input(busy: [600..<660], travel: [570..<600], buffer: 15))
        #expect(result.availableMinutes == 540 - 105)
    }

    @Test func travelWithoutBuffer_isNotWidened() {
        let result = capacity(input(travel: [600..<630], buffer: 15))
        #expect(result.availableMinutes == 540 - 30)
    }

    @Test func travelBeforeNow_doesNotReduceRemaining() {
        // It is 12:00; the trip lay at 10:00-10:30, the one at 14:00-14:30 is still ahead.
        let result = capacity(input(travel: [600..<630, 840..<870], now: 720))
        #expect(result.remainingMinutes == (1080 - 720) - 30)
        #expect(result.availableMinutes == 540 - 60)
    }

    @Test func travelOutsideWorkHours_isIgnored() {
        #expect(capacity(input(travel: [480..<540])).availableMinutes == 540)
    }

    // MARK: AI input

    private func planDay(travel: [Range<Int>], events: [CalendarEvent] = [], hours: WorkHours? = nil,
                         buffer: Int = 10) -> PlanInputDay {
        PlanInputDay(day: today, hours: hours ?? self.hours, lunch: nil, events: events, linkedEventIDs: [],
                     deadlineCalendarIDs: [], blocks: [], recurringMinutes: 0, plannedMinutes: 0, bufferMinutes: buffer,
                     calendar: calendar, travel: travel)
    }

    private func task(_ name: String) -> PlanInputTask {
        PlanInputTask(id: "local:\(name)", source: .local, title: name, due: nil, priority: nil, minutes: 60,
                      important: false, plannedDay: nil, anchor: nil)
    }

    private func planInput(_ day: PlanInputDay, tasks: [PlanInputTask] = []) -> PlanInput {
        PlanInput(scope: .day, days: [day], tasks: tasks, today: today, nowMinutes: 480, timeZoneID: "Europe/Berlin",
                  defaultTaskMinutes: 30)
    }

    @Test func travel_isBusyAndListedAsEvent() throws {
        let day = planDay(travel: [840..<870])
        #expect(day.busy == [840..<870])
        let travelEvent = try #require(day.events.first)
        #expect(travelEvent.title == "Fahrzeit")
        #expect(travelEvent.busy)
        #expect(travelEvent.travel)
        #expect(travelEvent.start == 840)
        #expect(travelEvent.end == 870)
        #expect(!travelEvent.linkedToTask)
        // The capacity of the day counts it once, without buffer.
        #expect(day.availableMinutes == 540 - 30)
        // The model sees the trip as a busy event without any place.
        let json = try #require(try JSONSerialization.jsonObject(with: planInput(day).modelJSON()) as? [String: Any])
        let firstDay = try #require((json["days"] as? [[String: Any]])?.first)
        let busyEvents = try #require(firstDay["busyEvents"] as? [[String: Any]])
        #expect(busyEvents.map { $0["title"] as? String } == ["Fahrzeit"])
        #expect(busyEvents.first?["start"] as? String == "14:00")
    }

    @Test func travel_keepsEventOrder() {
        let meeting = CalendarEvent(id: "m", externalID: nil, calendarID: "work", title: "Meeting",
                                    start: instant(2026, 11, 18, 14, 30), end: instant(2026, 11, 18, 15, 30),
                                    isAllDay: false, url: nil, isBusy: true, version: "1")
        let day = planDay(travel: [840..<870], events: [meeting])
        #expect(day.events.map(\.title) == ["Fahrzeit", "Meeting"])
        #expect(day.busy.sorted { $0.lowerBound < $1.lowerBound } == [840..<870, 870..<930])
    }

    @Test func travel_withHours_keepsTravelBlocked() {
        let day = planDay(travel: [840..<870])
        let shorter = day.withHours(WorkHours(startMinutes: 540, endMinutes: 960))
        #expect(shorter.busy == [840..<870])
        #expect(shorter.availableMinutes == 420 - 30)
        // The same capacity as built directly, so a changed day and a fresh day agree.
        #expect(shorter.availableMinutes == planDay(travel: [840..<870], hours: WorkHours(startMinutes: 540, endMinutes: 960)).availableMinutes)
    }

    @Test func suggestionOverlappingTravel_isRejected() {
        let day = planDay(travel: [840..<870])
        let overlapping = PlanBlock(taskId: "local:a", start: "14:15", minutes: 30, reason: "r")
        let result = validate(.day(DayPlanOutput(blocks: [overlapping], unscheduled: [], risks: [], estimates: [])),
                              input: planInput(day, tasks: [task("a")]))
        #expect(result.violations == [PlanViolation(taskId: "local:a", reason: .overlapsEvent)])
        // A block right after the trip plus buffer is fine.
        let after = PlanBlock(taskId: "local:a", start: "14:40", minutes: 30, reason: "r")
        let accepted = validate(.day(DayPlanOutput(blocks: [after], unscheduled: [], risks: [], estimates: [])),
                                input: planInput(day, tasks: [task("a")]))
        #expect(accepted.violations.isEmpty)
    }

    @Test func freeGaps_leaveOutTravel() {
        let day = planDay(travel: [840..<870])
        // 09:00-18:00 minus 14:00-14:30 with 10 minutes buffer on both sides.
        #expect(freeGaps(day, fromMinutes: nil) == [540..<830, 880..<1080])
    }
}
