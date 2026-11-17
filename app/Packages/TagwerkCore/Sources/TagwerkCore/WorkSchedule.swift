import Foundation

/// Working time of one day in minutes since midnight.
public struct WorkHours: Sendable, Hashable, Codable {
    public var startMinutes: Int
    public var endMinutes: Int

    public init(startMinutes: Int, endMinutes: Int) {
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
    }

    public var minutes: Int { max(0, endMinutes - startMinutes) }
}

/// Working time per weekday (1 = Sunday … 7 = Saturday); a missing weekday is a day off.
public struct WeekSchedule: Sendable, Hashable, Codable {
    public var hoursByWeekday: [Int: WorkHours]

    public init(hoursByWeekday: [Int: WorkHours]) {
        self.hoursByWeekday = hoursByWeekday
    }

    /// Monday to Friday 09:00–18:00, weekend off.
    public static let standard = WeekSchedule(hoursByWeekday: Dictionary(
        uniqueKeysWithValues: (2...6).map { ($0, WorkHours(startMinutes: 540, endMinutes: 1080)) }
    ))
}

/// Deviation for a single date.
public enum DayOverride: Sendable, Hashable, Codable {
    case off
    case hours(WorkHours)
}

/// Working time on `day`: a date override wins over the weekday schedule; `nil` is a day off.
public func workHours(on day: PlanDay, schedule: WeekSchedule, overrides: [PlanDay: DayOverride],
                      calendar: Calendar) -> WorkHours? {
    switch overrides[day] {
    case .off?: return nil
    case .hours(let hours)?: return hours
    case nil: return schedule.hoursByWeekday[day.weekday(in: calendar)]
    }
}

/// Suggested start of a new time block on `day`: on future days the start of work; today the next
/// full hour, at least the start of work and at most the latest start that still ends by the end of
/// work, but never in the past. Days off use 09:00 (today: the next full hour).
public func suggestedBlockStart(on day: PlanDay, hours: WorkHours?, minutes: Int, now: Date, calendar: Calendar) -> Date {
    let dayStart = day.startDate(in: calendar)
    let today = PlanDay(date: now, calendar: calendar)
    let fallbackMinutes = 9 * 60
    guard day == today else {
        return dayStart.addingTimeInterval(TimeInterval((hours?.startMinutes ?? fallbackMinutes) * 60))
    }
    let nowMinutes = Int(now.timeIntervalSince(dayStart) / 60)
    let nextFullHour = (nowMinutes / 60 + 1) * 60
    var start = nextFullHour
    if let hours {
        let latest = max(hours.startMinutes, ((hours.endMinutes - minutes) / 60) * 60)
        start = min(max(nextFullHour, hours.startMinutes), latest)
        if start < nowMinutes { start = nextFullHour }
    }
    return dayStart.addingTimeInterval(TimeInterval(start * 60))
}
