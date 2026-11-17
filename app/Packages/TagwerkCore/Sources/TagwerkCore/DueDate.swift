import Foundation

/// A due date stored as calendar fields, so that a date without time never shifts its day
/// when the time zone changes.
public struct DueDate: Sendable, Hashable, Codable {
    public var year: Int
    public var month: Int
    public var day: Int
    public var hour: Int?
    public var minute: Int?

    public init(year: Int, month: Int, day: Int, hour: Int? = nil, minute: Int? = nil) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = hour == nil ? nil : (minute ?? 0)
    }

    /// Reads the calendar fields of `date` in `calendar`; drops hour and minute unless `includeTime`.
    public init(date: Date, includeTime: Bool, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        self.init(
            year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1,
            hour: includeTime ? parts.hour : nil, minute: includeTime ? parts.minute : nil
        )
    }

    public var hasTime: Bool { hour != nil }

    /// Start of the due moment in `calendar`: the given time, or 00:00 for a date without time.
    public func startDate(in calendar: Calendar) -> Date {
        var parts = dayComponents()
        parts.hour = hour ?? 0
        parts.minute = minute ?? 0
        return calendar.date(from: parts) ?? .distantFuture
    }

    public func dayComponents() -> DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    /// Takes year, month and day from `day` and keeps this date's time.
    public func movedTo(day target: DueDate) -> DueDate {
        DueDate(year: target.year, month: target.month, day: target.day, hour: hour, minute: minute)
    }

    /// Orders by calendar day only.
    func compareDay(with other: DueDate) -> ComparisonResult {
        let lhs = (year, month, day), rhs = (other.year, other.month, other.day)
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }
}
