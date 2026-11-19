import Foundation

/// Unit of a relative reminder offset ("2 hours before").
public enum ReminderUnit: String, Codable, CaseIterable, Hashable, Sendable {
    case minutes, hours, days, weeks

    /// Length in minutes, used to compare and merge offsets that mean the same distance.
    var minutes: Int {
        switch self {
        case .minutes: 1
        case .hours: 60
        case .days: 24 * 60
        case .weeks: 7 * 24 * 60
        }
    }

    /// Hours and minutes make no sense for entries without a time of day.
    public var needsTimeOfDay: Bool { self == .minutes || self == .hours }
}

/// When a reminder fires relative to the moment of an entry (plan P4, assumption A4).
public enum ReminderOffset: Codable, Hashable, Sendable {
    /// A distance before the anchor; an amount of 0 means "at the time".
    case before(amount: Int, unit: ReminderUnit)
    /// A time of day on a day before the anchor's day; `daysBefore` 0 is the day of the anchor itself.
    case at(daysBefore: Int, hour: Int, minute: Int)
    /// A fixed moment. It is only read from EventKit, kept and deletable, and never created in Tagwerk.
    case absolute(Date)

    public static let maximumAmount = 999
    public static let maximumDaysBefore = 365

    /// The moment this reminder fires for an entry that starts or is due at `anchor`. For an all-day entry the anchor is
    /// the start of its day. Uses calendar arithmetic, so "1 day before at 18:00" keeps its wall-clock time across a
    /// daylight-saving change.
    public func fireDate(anchor: Date, isAllDay: Bool, calendar: Calendar) -> Date? {
        let anchor = isAllDay ? calendar.startOfDay(for: anchor) : anchor
        switch self {
        case .before(let amount, let unit):
            switch unit {
            case .minutes: return calendar.date(byAdding: .minute, value: -amount, to: anchor)
            case .hours: return calendar.date(byAdding: .hour, value: -amount, to: anchor)
            case .days: return calendar.date(byAdding: .day, value: -amount, to: anchor)
            case .weeks: return calendar.date(byAdding: .day, value: -7 * amount, to: anchor)
            }
        case .at(let daysBefore, let hour, let minute):
            guard let day = calendar.date(byAdding: .day, value: -daysBefore, to: calendar.startOfDay(for: anchor)) else { return nil }
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        case .absolute(let date):
            return date
        }
    }

    /// Equal distances compare equal: 60 minutes and 1 hour are one reminder.
    private var identityKey: [Int] {
        switch self {
        case .before(let amount, let unit): [0, amount * unit.minutes]
        case .at(let daysBefore, let hour, let minute): [1, daysBefore, hour, minute]
        case .absolute(let date): [2, Int(date.timeIntervalSince1970.rounded())]
        }
    }

    /// The value inside the allowed ranges: amount 0…999, days before 0…365, a valid time of day.
    private var clamped: ReminderOffset {
        switch self {
        case .before(let amount, let unit):
            .before(amount: min(max(amount, 0), Self.maximumAmount), unit: unit)
        case .at(let daysBefore, let hour, let minute):
            .at(daysBefore: min(max(daysBefore, 0), Self.maximumDaysBefore), hour: min(max(hour, 0), 23), minute: min(max(minute, 0), 59))
        case .absolute:
            self
        }
    }

    /// Reference entry for sorting: a timed entry at noon UTC, or the start of the day for all-day entries.
    private func sortKey(isAllDay: Bool) -> (group: Int, value: TimeInterval) {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let anchor = utc.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: isAllDay ? 0 : 12)) ?? Date(timeIntervalSince1970: 0)
        if case .absolute(let date) = self { return (1, date.timeIntervalSince1970) }
        return (0, fireDate(anchor: anchor, isAllDay: isAllDay, calendar: utc)?.timeIntervalSince1970 ?? 0)
    }

    /// The list as it is stored and planned: values inside their ranges, duplicates removed (also equal distances),
    /// hour and minute distances dropped for entries without a time of day, earliest reminder first.
    public static func normalized(_ list: [ReminderOffset], isAllDay: Bool) -> [ReminderOffset] {
        var seen = Set<[Int]>()
        let unique = list.map(\.clamped).filter { offset in
            if isAllDay, case .before(_, let unit) = offset, unit.needsTimeOfDay { return false }
            return seen.insert(offset.identityKey).inserted
        }
        // A stable sort: reminders with the same moment keep the order they were given in.
        return unique.enumerated().sorted { lhs, rhs in
            let (left, right) = (lhs.element.sortKey(isAllDay: isAllDay), rhs.element.sortKey(isAllDay: isAllDay))
            return (left.group, left.value, lhs.offset) < (right.group, right.value, rhs.offset)
        }.map(\.element)
    }

    /// The distance of `minutes` in its largest whole unit: 120 is 2 hours, 2880 is 2 days, 10080 is 1 week.
    public static func largestUnit(minutes: Int) -> ReminderOffset {
        let value = max(minutes, 0)
        for unit in [ReminderUnit.weeks, .days, .hours] where value > 0 && value % unit.minutes == 0 {
            return .before(amount: value / unit.minutes, unit: unit)
        }
        return .before(amount: value, unit: .minutes)
    }
}
