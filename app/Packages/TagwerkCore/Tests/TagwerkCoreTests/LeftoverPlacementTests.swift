import Foundation
import Testing
@testable import TagwerkCore

struct LeftoverPlacementTests {
    let calendar = makeCalendar()
    let today = PlanDay(year: 2026, month: 11, day: 19)          // Thursday
    var friday: PlanDay { today.adding(days: 1, calendar: calendar) }
    var saturday: PlanDay { today.adding(days: 2, calendar: calendar) }
    var monday: PlanDay { today.adding(days: 4, calendar: calendar) }

    /// A working day 09:00 to 17:00 without lunch or buffer.
    func day(_ day: PlanDay, hours: WorkHours? = WorkHours(startMinutes: 540, endMinutes: 1020), blocks: [Range<Int>] = []) -> PlanInputDay {
        PlanInputDay(day: day, hours: hours, lunch: nil, events: [], linkedEventIDs: [], deadlineCalendarIDs: [], blocks: blocks,
                     recurringMinutes: 0, plannedMinutes: 0, bufferMinutes: 0, calendar: calendar)
    }

    func item(_ key: String, _ minutes: Int, due: PlanDay? = nil, priority: Priority? = nil) -> LeftoverPlacement.Item {
        .init(taskKey: key, minutes: minutes, due: due, priority: priority)
    }

    @Test func place_putsTasksIntoTheFirstFittingGap() {
        // 09:00-10:00 is taken, so a 30 minute task starts at 10:00; the next one follows it.
        let result = LeftoverPlacement.place(tasks: [item("a", 30), item("b", 60)], days: [day(friday, blocks: [540..<600])],
                                             nowMinutes: nil, today: today)
        #expect(result.unplaced.isEmpty)
        #expect(result.placed.map(\.taskKey) == ["a", "b"])
        #expect(result.placed[0].day == friday && result.placed[0].range == 600..<630)
        #expect(result.placed[1].range == 630..<690)
    }

    @Test func place_neverOverlapsPlacedOrExistingBlocks() {
        let existing: [Range<Int>] = [600..<660, 720..<780]
        let tasks = (0..<8).map { item("t\($0)", 45) }
        let result = LeftoverPlacement.place(tasks: tasks, days: [day(friday, blocks: existing), day(monday)], nowMinutes: nil, today: today)
        var byDay: [PlanDay: [Range<Int>]] = [friday: existing, monday: []]
        for placed in result.placed {
            for other in byDay[placed.day] ?? [] { #expect(!placed.range.overlaps(other), "\(placed) overlaps \(other)") }
            byDay[placed.day, default: []].append(placed.range)
        }
        #expect(result.placed.count + result.unplaced.count == 8)
    }

    @Test func place_respectsTheDueDayWhileThereIsRoom() {
        // Due Friday: Friday has room, so the task does not drift to the Monday.
        let result = LeftoverPlacement.place(tasks: [item("a", 60, due: friday)], days: [day(friday), day(monday)], nowMinutes: nil, today: today)
        #expect(result.placed.first?.day == friday && result.placed.first?.lateForDue == false)
    }

    @Test func place_marksLatePlacementWhenTheDueDayIsFull() {
        let full = day(friday, blocks: [540..<1020])
        let result = LeftoverPlacement.place(tasks: [item("a", 60, due: friday)], days: [full, day(monday)], nowMinutes: nil, today: today)
        #expect(result.placed.first?.day == monday && result.placed.first?.lateForDue == true)
        // A task that was due before the first day is late as well.
        let overdue = LeftoverPlacement.place(tasks: [item("b", 60, due: today)], days: [day(friday)], nowMinutes: nil, today: today)
        #expect(overdue.placed.first?.day == friday && overdue.placed.first?.lateForDue == true)
    }

    @Test func place_ordersByDueThenPriorityThenInput() {
        let result = LeftoverPlacement.place(
            tasks: [item("noDue", 30), item("p2", 30, due: monday, priority: .p2), item("p1", 30, due: monday, priority: .p1),
                    item("early", 30, due: friday)],
            days: [day(friday), day(monday)], nowMinutes: nil, today: today)
        #expect(result.placed.map(\.taskKey) == ["early", "p1", "p2", "noDue"])
    }

    @Test func place_skipsDaysOff() {
        let off = day(friday, hours: nil)
        let result = LeftoverPlacement.place(tasks: [item("a", 30)], days: [off, day(saturday, hours: WorkHours(startMinutes: 0, endMinutes: 0)), day(monday)],
                                             nowMinutes: nil, today: today)
        #expect(result.placed.first?.day == monday)
    }

    @Test func place_leavesUnplacedWhenNothingFits() {
        let result = LeftoverPlacement.place(tasks: [item("big", 600), item("small", 30)], days: [day(friday)], nowMinutes: nil, today: today)
        #expect(result.unplaced == ["big"])
        #expect(result.placed.map(\.taskKey) == ["small"])
        // A shortened slot is not enough: the whole length has to fit.
        let tight = LeftoverPlacement.place(tasks: [item("a", 120)], days: [day(friday, blocks: [540..<960])], nowMinutes: nil, today: today)
        #expect(tight.unplaced == ["a"])
    }

    @Test func place_todayStartsAtNow() {
        // It is 14:20: a task placed today starts at or after that time.
        let result = LeftoverPlacement.place(tasks: [item("a", 30)], days: [day(today)], nowMinutes: 860, today: today)
        #expect(result.placed.first?.day == today && result.placed.first?.range.lowerBound == 860)
        // After the end of work nothing is left today.
        let late = LeftoverPlacement.place(tasks: [item("a", 30)], days: [day(today), day(friday)], nowMinutes: 1030, today: today)
        #expect(late.placed.first?.day == friday)
    }
}
