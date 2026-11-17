import Foundation

/// A calendar day without time, independent of the time zone (same idea as `DueDate` without time).
public struct PlanDay: Sendable, Hashable, Codable, Comparable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    public init(_ due: DueDate) {
        self.init(year: due.year, month: due.month, day: due.day)
    }

    /// 00:00 of this day in `calendar`.
    public func startDate(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    /// The calendar day `days` later (or earlier), robust against daylight-saving changes.
    public func adding(days: Int, calendar: Calendar) -> PlanDay {
        let moved = calendar.date(byAdding: .day, value: days, to: startDate(in: calendar)) ?? startDate(in: calendar)
        return PlanDay(date: moved, calendar: calendar)
    }

    /// 1 = Sunday … 7 = Saturday.
    public func weekday(in calendar: Calendar) -> Int {
        calendar.component(.weekday, from: startDate(in: calendar))
    }

    public static func < (lhs: PlanDay, rhs: PlanDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
