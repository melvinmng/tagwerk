import Foundation

/// Inputs for one day's capacity; intervals are minutes since midnight.
public struct CapacityInput: Sendable, Hashable {
    public var hours: WorkHours?
    public var lunchStartMinutes: Int
    public var lunchMinutes: Int
    public var bufferMinutes: Int
    public var busyIntervals: [Range<Int>]
    /// Load without a clock time: tasks planned for the day that have no time block. Effort that a recurring task only
    /// reserves counts as nothing; time is taken once a time block is booked (`blockIntervals`).
    public var untimedPlannedMinutes: Int
    public var estimatedCount: Int
    /// Current time in minutes since midnight; set only for today to compute the remaining time.
    public var nowMinutes: Int?
    /// Travel time before and after events with a place (minutes since midnight). Blocked like the lunch break: without
    /// buffer, and counted once where it overlaps the buffer of another event.
    public var travelIntervals: [Range<Int>]
    /// Time blocks of the day (events linked to a task). They are load, not blocked time: the part inside the working
    /// hours that is not already blocked counts, once even where blocks overlap.
    public var blockIntervals: [Range<Int>]

    public init(hours: WorkHours?, lunchStartMinutes: Int, lunchMinutes: Int, bufferMinutes: Int,
                busyIntervals: [Range<Int>], untimedPlannedMinutes: Int, estimatedCount: Int,
                travelIntervals: [Range<Int>] = [], blockIntervals: [Range<Int>] = []) {
        self.hours = hours
        self.lunchStartMinutes = lunchStartMinutes
        self.lunchMinutes = lunchMinutes
        self.bufferMinutes = bufferMinutes
        self.busyIntervals = busyIntervals
        self.untimedPlannedMinutes = untimedPlannedMinutes
        self.estimatedCount = estimatedCount
        self.travelIntervals = travelIntervals
        self.blockIntervals = blockIntervals
    }

    /// The lunch break as an interval; `nil` without one.
    var lunch: Range<Int>? {
        lunchMinutes > 0 ? lunchStartMinutes..<(lunchStartMinutes + lunchMinutes) : nil
    }
}

/// Where the minutes of the working window went. Every minute belongs to one part, in this order: lunch, travel, events
/// (with buffer), time blocks, free. The parts up to the events add up to the blocked time.
public struct CapacityBreakdown: Sendable, Hashable {
    public let windowMinutes: Int
    public let lunchMinutes: Int
    /// Travel time outside the lunch break.
    public let travelMinutes: Int
    /// Events with buffer, outside lunch and travel.
    public let eventMinutes: Int
    /// Time blocks inside the window, outside the blocked time; overlapping blocks count once.
    public let blockMinutes: Int
    /// Time blocks outside the working hours; they use no free time.
    public let outsideBlockMinutes: Int
    /// Tasks without a time block.
    public let untimedMinutes: Int

    public var blockedMinutes: Int { lunchMinutes + travelMinutes + eventMinutes }
    /// Time blocks and tasks without a time block.
    public var plannedMinutes: Int { blockMinutes + untimedMinutes }

    static let empty = CapacityBreakdown(windowMinutes: 0, lunchMinutes: 0, travelMinutes: 0, eventMinutes: 0, blockMinutes: 0,
                                         outsideBlockMinutes: 0, untimedMinutes: 0)
}

public struct DayCapacity: Sendable, Hashable {
    /// Working time left for tasks: the working hours minus lunch, travel and events (with buffer).
    public let availableMinutes: Int
    /// Time blocks inside the working hours plus tasks without a time block.
    public let plannedMinutes: Int
    /// May be negative when the day is overbooked.
    public let freeMinutes: Int
    public let isOverbooked: Bool
    public let isDayOff: Bool
    /// Tasks counted with the default duration because they have no effort.
    public let estimatedCount: Int
    public let breakdown: CapacityBreakdown
    /// Free time from now until the end of work (today only); negative when overbooked.
    public var remainingMinutes: Int? = nil
}

/// Intervals of the events that block time, widened by the buffer on both sides. An event that lies completely inside
/// the lunch break or a trip gets no buffer: that time is blocked anyway.
public func bufferedEventIntervals(_ events: [Range<Int>], lunch: Range<Int>?, travel: [Range<Int>],
                                   buffer: Int) -> [Range<Int>] {
    let unbuffered = (lunch.map { [$0] } ?? []) + travel
    return events.map { event in
        unbuffered.contains { $0.lowerBound <= event.lowerBound && event.upperBound <= $0.upperBound }
            ? event : (event.lowerBound - buffer)..<(event.upperBound + buffer)
    }
}

/// Every minute of the working hours counts once: as blocked time (lunch, travel, events with buffer), as a time block
/// or as free. Blocked time is the union of its intervals, limited to the working hours. Time blocks and tasks without
/// a time are the load; effort that recurring tasks only reserve is not.
public func capacity(_ input: CapacityInput) -> DayCapacity {
    let blockUnion = merged(input.blockIntervals)
    guard let hours = input.hours, hours.minutes > 0 else {
        let planned = length(blockUnion) + input.untimedPlannedMinutes
        return DayCapacity(availableMinutes: 0, plannedMinutes: planned, freeMinutes: -planned, isOverbooked: planned > 0,
                           isDayOff: true, estimatedCount: input.estimatedCount, breakdown: .empty)
    }
    let events = bufferedEventIntervals(input.busyIntervals, lunch: input.lunch, travel: input.travelIntervals,
                                        buffer: input.bufferMinutes)
    let lunch = input.lunch.map { [$0] } ?? []
    let work = hours.startMinutes..<hours.endMinutes
    let blocked = merged(lunch + input.travelIntervals + events, within: work)
    let withLunch = length(merged(lunch, within: work))
    let withTravel = length(merged(lunch + input.travelIntervals, within: work))
    let withBlocks = length(merged(lunch + input.travelIntervals + events + input.blockIntervals, within: work))
    let breakdown = CapacityBreakdown(
        windowMinutes: work.count, lunchMinutes: withLunch, travelMinutes: withTravel - withLunch,
        eventMinutes: length(blocked) - withTravel, blockMinutes: withBlocks - length(blocked),
        outsideBlockMinutes: length(blockUnion) - length(merged(input.blockIntervals, within: work)),
        untimedMinutes: input.untimedPlannedMinutes)
    let available = work.count - length(blocked)
    let planned = breakdown.plannedMinutes
    var result = DayCapacity(availableMinutes: available, plannedMinutes: planned, freeMinutes: available - planned,
                             isOverbooked: planned > available, isDayOff: false, estimatedCount: input.estimatedCount,
                             breakdown: breakdown)
    if let now = input.nowMinutes {
        let start = min(max(hours.startMinutes, now), hours.endMinutes)
        let window = start..<hours.endMinutes
        let blockedAhead = length(merged(lunch + input.travelIntervals + events, within: window))
        let withBlocksAhead = length(merged(lunch + input.travelIntervals + events + input.blockIntervals, within: window))
        let blocksAhead = withBlocksAhead - blockedAhead
        result.remainingMinutes = window.count - blockedAhead - blocksAhead - input.untimedPlannedMinutes
    }
    return result
}

/// Time a "free" mark gives back: the available minutes after the given busy intervals no longer block, minus the
/// available minutes now. Overlapping events, events outside the working hours and events inside the lunch break give
/// back only what really becomes free. Each interval removes one equal busy interval (a copy in a second calendar
/// keeps blocking until it is freed too).
public func freedMinutes(_ input: CapacityInput, removing intervals: [Range<Int>]) -> Int {
    var reduced = input
    for interval in intervals {
        if let index = reduced.busyIntervals.firstIndex(of: interval) { reduced.busyIntervals.remove(at: index) }
    }
    return capacity(reduced).availableMinutes - capacity(input).availableMinutes
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

/// The union of the ranges as sorted, separate ranges; with `bounds` each range is limited to them first.
private func merged(_ ranges: [Range<Int>], within bounds: Range<Int>? = nil) -> [Range<Int>] {
    let candidates = bounds.map { limit in ranges.compactMap { clip($0, to: limit) } } ?? ranges.filter { !$0.isEmpty }
    var result: [Range<Int>] = []
    for range in candidates.sorted(by: { $0.lowerBound < $1.lowerBound }) {
        if let last = result.last, range.lowerBound <= last.upperBound {
            result[result.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
        } else {
            result.append(range)
        }
    }
    return result
}

private func length(_ ranges: [Range<Int>]) -> Int {
    ranges.reduce(0) { $0 + $1.count }
}
