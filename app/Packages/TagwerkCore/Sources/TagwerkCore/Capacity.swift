import Foundation

/// Inputs for one day's capacity; intervals are minutes since midnight.
public struct CapacityInput: Sendable, Hashable {
    public var hours: WorkHours?
    public var lunchStartMinutes: Int
    public var lunchMinutes: Int
    public var bufferMinutes: Int
    public var busyIntervals: [Range<Int>]
    public var recurringMinutes: Int
    public var plannedMinutes: Int
    public var estimatedCount: Int

    public init(hours: WorkHours?, lunchStartMinutes: Int, lunchMinutes: Int, bufferMinutes: Int,
                busyIntervals: [Range<Int>], recurringMinutes: Int, plannedMinutes: Int, estimatedCount: Int) {
        self.hours = hours
        self.lunchStartMinutes = lunchStartMinutes
        self.lunchMinutes = lunchMinutes
        self.bufferMinutes = bufferMinutes
        self.busyIntervals = busyIntervals
        self.recurringMinutes = recurringMinutes
        self.plannedMinutes = plannedMinutes
        self.estimatedCount = estimatedCount
    }
}

public struct DayCapacity: Sendable, Hashable {
    /// Working time left for tasks after events (with buffer), lunch and recurring effort.
    public let availableMinutes: Int
    public let plannedMinutes: Int
    /// May be negative when the day is overbooked.
    public let freeMinutes: Int
    public let isOverbooked: Bool
    public let isDayOff: Bool
    /// Tasks counted with the default duration because they have no effort.
    public let estimatedCount: Int
}

/// Blocked time is the union of lunch and busy intervals (each widened by the buffer on both sides),
/// limited to the working hours; recurring effort comes off the rest.
public func capacity(_ input: CapacityInput) -> DayCapacity {
    guard let hours = input.hours, hours.minutes > 0 else {
        return DayCapacity(availableMinutes: 0, plannedMinutes: input.plannedMinutes, freeMinutes: -input.plannedMinutes,
                           isOverbooked: input.plannedMinutes > 0, isDayOff: true, estimatedCount: input.estimatedCount)
    }
    var blocks = input.busyIntervals.map { ($0.lowerBound - input.bufferMinutes)..<($0.upperBound + input.bufferMinutes) }
    if input.lunchMinutes > 0 {
        blocks.append(input.lunchStartMinutes..<(input.lunchStartMinutes + input.lunchMinutes))
    }
    let work = hours.startMinutes..<hours.endMinutes
    let blocked = mergedLength(blocks.compactMap { clip($0, to: work) })
    let available = max(0, hours.minutes - blocked - input.recurringMinutes)
    return DayCapacity(availableMinutes: available, plannedMinutes: input.plannedMinutes,
                       freeMinutes: available - input.plannedMinutes, isOverbooked: input.plannedMinutes > available,
                       isDayOff: false, estimatedCount: input.estimatedCount)
}

/// Busy minutes of `day` from timed events that are not free/declined and not linked to a task.
public func busyIntervals(events: [CalendarEvent], on day: PlanDay, calendar: Calendar,
                          excluding linkedIDs: Set<String>) -> [Range<Int>] {
    let dayStart = day.startDate(in: calendar)
    let dayEnd = day.adding(days: 1, calendar: calendar).startDate(in: calendar)
    let dayLength = Int(dayEnd.timeIntervalSince(dayStart) / 60)
    return events.compactMap { event in
        guard !event.isAllDay, event.isBusy, !linkedIDs.contains(event.id),
              event.end > dayStart, event.start < dayEnd else { return nil }
        let start = max(0, Int(event.start.timeIntervalSince(dayStart) / 60))
        let end = min(dayLength, Int(event.end.timeIntervalSince(dayStart) / 60))
        return start < end ? start..<end : nil
    }
    .sorted { $0.lowerBound < $1.lowerBound }
}

private func clip(_ range: Range<Int>, to bounds: Range<Int>) -> Range<Int>? {
    let lower = max(range.lowerBound, bounds.lowerBound), upper = min(range.upperBound, bounds.upperBound)
    return lower < upper ? lower..<upper : nil
}

private func mergedLength(_ ranges: [Range<Int>]) -> Int {
    var total = 0
    var current: Range<Int>?
    for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
        if let open = current, range.lowerBound <= open.upperBound {
            current = open.lowerBound..<max(open.upperBound, range.upperBound)
        } else {
            if let open = current { total += open.count }
            current = range
        }
    }
    return total + (current?.count ?? 0)
}
