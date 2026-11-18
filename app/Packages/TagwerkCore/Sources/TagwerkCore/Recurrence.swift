import Foundation

/// The recurrence patterns Tagwerk can expand; anything else is `.unsupported`.
public enum RecurrenceRule: Sendable, Hashable, Codable {
    case daily(interval: Int)
    /// Weekdays 1 = Sunday … 7 = Saturday; empty means the start's weekday.
    case weekly(interval: Int, weekdays: Set<Int>)
    case monthly(interval: Int, day: Int)
    /// The `ordinal`-th `weekday` of the month; ordinal 1...4, weekday 1 = Sunday … 7 = Saturday.
    case monthlyWeekday(interval: Int, ordinal: Int, weekday: Int)
    /// Month and day come from the start of the series; February 29 occurs in leap years only.
    case yearly(interval: Int)
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

    /// Whether the series can be written to a source: positive interval, weekdays in 1...7, day of the month
    /// in 1...31, ordinal in 1...4, count of at least one, end not before the start, and not end and count
    /// together. `.unsupported` is never valid because Tagwerk cannot express it.
    public var isValid: Bool {
        if end != nil && count != nil { return false }
        if let count, count < 1 { return false }
        if let end, end < start { return false }
        let weekdayRange = 1...7
        switch rule {
        case .daily(let interval):
            return interval >= 1
        case .weekly(let interval, let weekdays):
            return interval >= 1 && weekdays.allSatisfy(weekdayRange.contains)
        case .monthly(let interval, let day):
            return interval >= 1 && (1...31).contains(day)
        case .monthlyWeekday(let interval, let ordinal, let weekday):
            return interval >= 1 && (1...4).contains(ordinal) && weekdayRange.contains(weekday)
        case .yearly(let interval):
            return interval >= 1
        case .unsupported:
            return false
        }
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

/// The first day on or after `day` on which the series occurs, or `nil` when it has ended.
/// Uses `occurrences`, so preview, due-date suggestion and planning agree.
public func nextOccurrence(of recurrence: Recurrence, onOrAfter day: PlanDay, calendar: Calendar) -> PlanDay? {
    nextOccurrences(of: recurrence, onOrAfter: day, limit: 1, calendar: calendar).first
}

/// Up to `limit` days on or after `day` on which the series occurs, in one pass over the days from the start
/// of the series (the same matching and counting as `occurrences`). The search stops when no occurrence
/// follows within the largest possible gap of the rule, or after `withinDays` days from `day` when given.
public func nextOccurrences(of recurrence: Recurrence, onOrAfter day: PlanDay, limit: Int, withinDays: Int? = nil,
                            calendar: Calendar) -> [PlanDay] {
    guard limit > 0 else { return [] }
    if case .unsupported = recurrence.rule {
        return recurrence.start >= day ? [recurrence.start] : []
    }
    let horizon = searchHorizonDays(for: recurrence.rule)
    let startWeek = weekStart(of: recurrence.start, calendar: calendar)
    let first = max(day, recurrence.start)
    var result: [PlanDay] = []
    var produced = 0
    var daysWithoutHit = 0
    var daysSearched = 0
    var current = recurrence.start
    while result.count < limit {
        if let end = recurrence.end, current > end { break }
        let isCandidate = current >= first
        if matches(current, recurrence: recurrence, startWeek: startWeek, calendar: calendar) {
            produced += 1
            if let count = recurrence.count, produced > count { break }
            if isCandidate {
                result.append(current)
                daysWithoutHit = 0
            }
        } else if isCandidate {
            daysWithoutHit += 1
            if daysWithoutHit > horizon { break }
        }
        if isCandidate {
            daysSearched += 1
            if let withinDays, daysSearched > withinDays { break }
        }
        current = current.adding(days: 1, calendar: calendar)
    }
    return result
}

/// Upper bound for the gap between two occurrences: months without day 31 (at most a year apart for any
/// interval cycle) and February 29 (at most eight years apart, because of century years).
private func searchHorizonDays(for rule: RecurrenceRule) -> Int {
    switch rule {
    case .daily(let interval): max(1, interval)
    case .weekly(let interval, _): 7 * max(1, interval) + 7
    case .monthly(let interval, _), .monthlyWeekday(let interval, _, _): 372 * max(1, interval)
    case .yearly(let interval): 8 * 366 * max(1, interval)
    case .unsupported: 0
    }
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
    case .monthlyWeekday(let interval, let ordinal, let weekday):
        guard day.weekday(in: calendar) == weekday, (day.day - 1) / 7 + 1 == ordinal else { return false }
        let months = (day.year - recurrence.start.year) * 12 + (day.month - recurrence.start.month)
        return months % max(1, interval) == 0
    case .yearly(let interval):
        guard day.month == recurrence.start.month, day.day == recurrence.start.day else { return false }
        return (day.year - recurrence.start.year) % max(1, interval) == 0
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
