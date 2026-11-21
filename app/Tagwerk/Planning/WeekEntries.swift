import Foundation
import TagwerkCore

/// One timed entry of a day in the week view: a calendar event or a time block of a task. It carries what the day list
/// shows in rows of its own around it, so the week stays one row per entry: the trips to and from the event, and the
/// deadline the event stands for.
struct WeekEntry: Identifiable, Equatable {
    let event: CalendarEvent
    /// The task of a time block; `nil` for an event that is no block.
    let taskID: TaskID?
    /// The trip to the event first, then the way home from it; empty without travel time.
    let trips: [TravelSegment]
    /// The deadline this event is (deadline calendar or marked): the week shows it here and not as a line of its own.
    let deadline: ImportantDeadline?

    var id: String { event.id }
    var isBlock: Bool { taskID != nil }
}

/// What the week shows of one day besides suggestions and tasks without a time: all-day events on top, then the timed
/// entries in the order of the day list, then the deadlines that are not already one of those entries.
struct WeekDayContent: Equatable {
    let allDay: [CalendarEvent]
    let timed: [WeekEntry]
    let deadlines: [ImportantDeadline]

    var hasEntries: Bool { !allDay.isEmpty || !timed.isEmpty }
}

extension PlanningModel {
    /// The events, time blocks and deadlines of a day for the week view, built from the plan of the day, so capacity,
    /// events and trips are the very numbers of the day view.
    ///
    /// Order of the timed entries: by start; entries that start together keep the order of the day list (events before
    /// blocks). An event that began on an earlier day comes first, as it does in the day list. Lunch break and free
    /// stretches are left out: the week has no place for them, and the day is the drop target as a whole.
    func weekContent(for plan: DayPlan) -> WeekDayContent {
        let dayStart = plan.day.startDate(in: calendar)
        let deadlineByEvent = Dictionary(plan.deadlines.compactMap { deadline in deadline.eventID.map { ($0, deadline) } },
                                         uniquingKeysWith: { first, _ in first })
        let tripsByEvent = Dictionary(grouping: plan.travel, by: \.eventID)
            .mapValues { $0.sorted { $0.direction == .toEvent && $1.direction != .toEvent } }

        var candidates: [(start: Int, entry: WeekEntry)] = []
        for event in plan.events where !event.isAllDay {
            candidates.append((minutes(of: event.start, from: dayStart),
                               WeekEntry(event: event, taskID: nil, trips: tripsByEvent[event.id] ?? [],
                                         deadline: deadlineByEvent[event.id])))
        }
        for block in plan.blocks {
            guard let taskID = plan.links[block.id] else { continue }
            candidates.append((minutes(of: block.start, from: dayStart),
                               WeekEntry(event: block, taskID: taskID, trips: tripsByEvent[block.id] ?? [],
                                         deadline: deadlineByEvent[block.id])))
        }
        let timed = candidates.enumerated()
            .sorted { lhs, rhs in
                lhs.element.start != rhs.element.start ? lhs.element.start < rhs.element.start : lhs.offset < rhs.offset
            }
            .map(\.element.entry)

        let shownAsEntry = Set(timed.compactMap { $0.deadline?.id })
        let deadlineEvents = Set(plan.deadlines.compactMap(\.eventID))
        return WeekDayContent(
            allDay: allDayEvents(for: plan).filter { !deadlineEvents.contains($0.id) },
            timed: timed,
            deadlines: plan.deadlines.filter { !shownAsEntry.contains($0.id) }
        )
    }

    private func minutes(of date: Date, from dayStart: Date) -> Int {
        Int(date.timeIntervalSince(dayStart) / 60)
    }
}
