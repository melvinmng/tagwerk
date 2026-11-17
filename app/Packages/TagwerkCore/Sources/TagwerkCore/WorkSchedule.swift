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
