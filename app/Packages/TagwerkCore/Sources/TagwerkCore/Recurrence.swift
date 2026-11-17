import Foundation

/// The recurrence patterns Tagwerk can expand; anything else is `.unsupported`.
public enum RecurrenceRule: Sendable, Hashable, Codable {
    case daily(interval: Int)
    /// Weekdays 1 = Sunday … 7 = Saturday; empty means the start's weekday.
    case weekly(interval: Int, weekdays: Set<Int>)
    case monthly(interval: Int, day: Int)
    case unsupported
}

public struct Recurrence: Sendable, Hashable, Codable {
    public var rule: RecurrenceRule
    public var start: PlanDay
    public var end: PlanDay?
    public var count: Int?

    public init(rule: RecurrenceRule, start: PlanDay, end: PlanDay?, count: Int?) {
        self.rule = rule
        self.start = start
        self.end = end
        self.count = count
    }
}

/// Days within `range` on which the series occurs. `.unsupported` yields only the start day,
/// so the effort is reserved at least for the next due date.
public func occurrences(of recurrence: Recurrence, in range: ClosedRange<PlanDay>, calendar: Calendar) -> [PlanDay] {
    if case .unsupported = recurrence.rule {
        return range.contains(recurrence.start) ? [recurrence.start] : []
    }
    let last = [range.upperBound, recurrence.end].compactMap { $0 }.min()!
    guard recurrence.start <= last else { return [] }
    let startWeek = weekStart(of: recurrence.start, calendar: calendar)
    var result: [PlanDay] = []
    var produced = 0
    var day = recurrence.start
    while day <= last {
        if matches(day, recurrence: recurrence, startWeek: startWeek, calendar: calendar) {
            produced += 1
            if let count = recurrence.count, produced > count { break }
            if range.contains(day) { result.append(day) }
        }
        day = day.adding(days: 1, calendar: calendar)
    }
    return result
}

private func matches(_ day: PlanDay, recurrence: Recurrence, startWeek: Date, calendar: Calendar) -> Bool {
    switch recurrence.rule {
    case .daily(let interval):
        return daysBetween(recurrence.start, day, calendar: calendar) % max(1, interval) == 0
    case .weekly(let interval, let weekdays):
        let allowed = weekdays.isEmpty ? [recurrence.start.weekday(in: calendar)] : weekdays
        guard allowed.contains(day.weekday(in: calendar)) else { return false }
        let weeks = calendar.dateComponents([.day], from: startWeek, to: weekStart(of: day, calendar: calendar)).day! / 7
        return weeks % max(1, interval) == 0
    case .monthly(let interval, let dayOfMonth):
        guard day.day == dayOfMonth else { return false }
        let months = (day.year - recurrence.start.year) * 12 + (day.month - recurrence.start.month)
        return months % max(1, interval) == 0
    case .unsupported:
        return false
    }
}

private func daysBetween(_ from: PlanDay, _ to: PlanDay, calendar: Calendar) -> Int {
    calendar.dateComponents([.day], from: from.startDate(in: calendar), to: to.startDate(in: calendar)).day ?? 0
}

private func weekStart(of day: PlanDay, calendar: Calendar) -> Date {
    calendar.dateInterval(of: .weekOfYear, for: day.startDate(in: calendar))?.start ?? day.startDate(in: calendar)
}
