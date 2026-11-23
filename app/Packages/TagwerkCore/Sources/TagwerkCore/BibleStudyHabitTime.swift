import Foundation

/// The time of day at which a Bible Study reminder could be offered, learned from the start times of the completed sessions
/// (BS8, BE1c). The learned time is only ever a suggestion: nothing changes until the user accepts it.
///
/// **The thresholds below are starting values set without any measurement** (mockup 2026-11-20, "Annahme, nicht belegt"). They
/// are named constants in this one place and should be checked after a few weeks of use.
public enum BibleStudyHabitTime {
    /// How far back the sessions count, in weeks.
    public static let weeks = 8
    /// Fewest sessions of a group before a suggestion is made.
    public static let minimumSessions = 5
    /// Length of the window that must hold the start times, in minutes.
    public static let windowMinutes = 60
    /// Share of the sessions of a group that must lie within one window.
    public static let minimumShare = 2.0 / 3.0
    /// A suggestion that differs less than this from the time already set for every day of the group is not made.
    public static let minimumDifferenceMinutes = 20
    /// "Nicht jetzt" keeps the suggestion away for this many days.
    public static let snoozeDays = 28
    /// The suggested time is rounded to this many minutes.
    public static let roundingMinutes = 5

    /// Weekdays (Monday to Friday) and weekend (Saturday, Sunday) are looked at apart.
    public enum Group: Sendable, Equatable, CaseIterable {
        case weekdays, weekend

        /// The weekdays of the group, numbered like `Calendar` (1 = Sunday).
        public var weekdays: Set<Int> {
            switch self {
            case .weekdays: [2, 3, 4, 5, 6]
            case .weekend: [7, 1]
            }
        }
    }

    public struct Suggestion: Sendable, Equatable {
        public let group: Group
        /// The middle of the span of the start times inside the window, rounded to five minutes, in minutes since midnight.
        public let minutes: Int
        /// How many of the `sessions` began inside the window.
        public let sessionsInWindow: Int
        /// All sessions of the group in the last `weeks` weeks.
        public let sessions: Int
        /// The earliest and the latest start time inside the window, in minutes since midnight.
        public let windowStart: Int
        public let windowEnd: Int

        public init(group: Group, minutes: Int, sessionsInWindow: Int, sessions: Int, windowStart: Int, windowEnd: Int) {
            self.group = group
            self.minutes = minutes
            self.sessionsInWindow = sessionsInWindow
            self.sessions = sessions
            self.windowStart = windowStart
            self.windowEnd = windowEnd
        }

        /// A stable name of this suggestion ("weekdays-405"): the time is rounded, so the same habit keeps the same key.
        public var key: String { "\(group == .weekdays ? "weekdays" : "weekend")-\(minutes)" }
    }

    /// At most one suggestion per group from the start times of the last `weeks` weeks. None when fewer than `minimumSessions`
    /// started in the group, when less than `minimumShare` of them lie within one `windowMinutes` window, when the time differs
    /// by less than `minimumDifferenceMinutes` from the time already set for all days of the group, or while snoozed. Minutes
    /// are counted on one day, so a window never joins the end of a day with the start of the next.
    public static func suggestions(startTimes: [Date], existing: [BibleStudyReminderTime], snoozedUntil: Date?, now: Date,
                                   calendar: Calendar) -> [Suggestion] {
        if let snoozedUntil, snoozedUntil > now { return [] }
        guard let since = calendar.date(byAdding: .day, value: -7 * weeks, to: now) else { return [] }
        var minutesByGroup: [Group: [Int]] = [:]
        for date in startTimes where date > since && date <= now {
            let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
            guard let weekday = parts.weekday, let hour = parts.hour, let minute = parts.minute else { continue }
            let group: Group = Group.weekdays.weekdays.contains(weekday) ? .weekdays : .weekend
            minutesByGroup[group, default: []].append(hour * 60 + minute)
        }
        return Group.allCases.compactMap { group in
            guard let minutes = minutesByGroup[group]?.sorted(), minutes.count >= minimumSessions,
                  let cluster = densestWindow(in: minutes) else { return nil }
            guard Double(cluster.count) / Double(minutes.count) >= minimumShare else { return nil }
            let middle = Double(cluster.first + cluster.last) / 2
            let rounded = Int((middle / Double(roundingMinutes)).rounded()) * roundingMinutes
            if isClose(rounded, to: existing, in: group) { return nil }
            return Suggestion(group: group, minutes: rounded, sessionsInWindow: cluster.count, sessions: minutes.count,
                              windowStart: cluster.first, windowEnd: cluster.last)
        }
    }

    /// The window of `windowMinutes` that holds the most of the sorted `minutes`, the earliest one on a tie, as the first and
    /// last start time inside it and their count.
    private static func densestWindow(in minutes: [Int]) -> (first: Int, last: Int, count: Int)? {
        var best: (first: Int, last: Int, count: Int)?
        for (index, start) in minutes.enumerated() {
            let inside = minutes[index...].prefix { $0 - start <= windowMinutes }
            if best == nil || inside.count > best!.count, let last = inside.last { best = (start, last, inside.count) }
        }
        return best
    }

    /// Whether every day of the group already has a reminder time less than `minimumDifferenceMinutes` away from `minutes`.
    private static func isClose(_ minutes: Int, to existing: [BibleStudyReminderTime], in group: Group) -> Bool {
        group.weekdays.allSatisfy { weekday in
            BibleStudyReminderTimes.minutes(on: weekday, in: existing).map { abs($0 - minutes) < minimumDifferenceMinutes } ?? false
        }
    }
}
