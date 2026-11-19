import Foundation

/// The kinds of entries that get reminders.
public enum ReminderKind: String, Codable, CaseIterable, Hashable, Sendable {
    case task, deadline, event
}

/// The reminders an entry gets when it has no list of its own (plan P4, assumptions A2, A5 and A6). Every kind has one
/// list for entries with a time of day and one for entries without a time or all-day entries.
public struct ReminderDefaults: Codable, Hashable, Sendable {
    public var timed: [ReminderKind: [ReminderOffset]]
    public var allDay: [ReminderKind: [ReminderOffset]]

    public init(timed: [ReminderKind: [ReminderOffset]] = [:], allDay: [ReminderKind: [ReminderOffset]] = [:]) {
        self.timed = timed
        self.allDay = allDay
    }

    /// The normalized list for a kind; empty when none is set.
    public func offsets(for kind: ReminderKind, isAllDay: Bool) -> [ReminderOffset] {
        ReminderOffset.normalized((isAllDay ? allDay : timed)[kind] ?? [], isAllDay: isAllDay)
    }

    /// Replaces the list of a kind; stored normalized.
    public mutating func set(_ offsets: [ReminderOffset], for kind: ReminderKind, isAllDay: Bool) {
        let normalized = ReminderOffset.normalized(offsets, isAllDay: isAllDay)
        if isAllDay { allDay[kind] = normalized } else { timed[kind] = normalized }
    }

    /// The defaults that behave like the fixed rules before reminders became flexible: tasks and deadlines with a time
    /// remind one lead time before, tasks without a time at `dateOnlyHour` on their day, all-day deadlines at
    /// `allDayEventHour` on the evening before; events remind nothing.
    public static func legacy(leadTimeMinutes: Int, dateOnlyHour: Int = 9, allDayEventHour: Int = 18) -> ReminderDefaults {
        let lead = ReminderOffset.largestUnit(minutes: leadTimeMinutes)
        return ReminderDefaults(
            timed: [.task: [lead], .deadline: [lead], .event: []],
            allDay: [.task: [.at(daysBefore: 0, hour: dateOnlyHour, minute: 0)],
                     .deadline: [.at(daysBefore: 1, hour: allDayEventHour, minute: 0)], .event: []])
    }

    /// Reads stored defaults; without data or with unreadable data the legacy rules apply.
    public static func decode(_ data: Data?, leadTimeMinutes: Int) -> ReminderDefaults {
        guard let data, let decoded = try? JSONDecoder().decode(ReminderDefaults.self, from: data) else {
            return legacy(leadTimeMinutes: leadTimeMinutes)
        }
        return decoded
    }

    public func encoded() -> Data {
        // A fixed key order keeps the stored value, and with it the settings hash, stable between runs.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}
