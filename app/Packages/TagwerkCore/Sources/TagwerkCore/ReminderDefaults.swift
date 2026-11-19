import Foundation

/// The kinds of entries that get reminders, in the order of the settings page. Every task source has its own kind, so
/// the default reminders of GitHub issues, Apple reminders and local tasks can differ.
public enum ReminderKind: String, Codable, CaseIterable, Hashable, Sendable {
    /// Events of the calendars (Apple Calendar), applied when an event is created in Tagwerk.
    case event
    case appleReminder, githubIssue, localTask
    case deadline

    /// The kind of a task from this source.
    public static func forTask(source: TaskSource) -> ReminderKind {
        switch source {
        case .reminders: .appleReminder
        case .github: .githubIssue
        case .local: .localTask
        }
    }

    /// The kinds of tasks.
    static let taskKinds: [ReminderKind] = [.appleReminder, .githubIssue, .localTask]

    /// Key of the one list for all tasks, as stored before every source got its own kind.
    fileprivate static let formerTaskKey = "task"
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

    private enum CodingKeys: String, CodingKey { case timed, allDay }

    /// Keyed by the raw value of the kind, so the stored JSON is an object with a stable key order. The former list
    /// "task" applies to every task kind that has no list of its own, so data from before the split behaves as before.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func read(_ key: CodingKeys) throws -> [ReminderKind: [ReminderOffset]] {
            let raw = try container.decodeIfPresent([String: [ReminderOffset]].self, forKey: key) ?? [:]
            var lists = Dictionary(raw.compactMap { entry in ReminderKind(rawValue: entry.key).map { ($0, entry.value) } },
                                   uniquingKeysWith: { first, _ in first })
            if let former = raw[ReminderKind.formerTaskKey] {
                for kind in ReminderKind.taskKinds where lists[kind] == nil { lists[kind] = former }
            }
            return lists
        }
        timed = try read(.timed)
        allDay = try read(.allDay)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Dictionary(uniqueKeysWithValues: timed.map { ($0.key.rawValue, $0.value) }), forKey: .timed)
        try container.encode(Dictionary(uniqueKeysWithValues: allDay.map { ($0.key.rawValue, $0.value) }), forKey: .allDay)
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
    /// remind one lead time before (in hours or minutes, so the moment is the same as with the former fixed rule), tasks without a time at `dateOnlyHour` on their day, all-day deadlines at
    /// `allDayEventHour` on the evening before; events remind nothing.
    public static func legacy(leadTimeMinutes: Int, dateOnlyHour: Int = 9, allDayEventHour: Int = 18) -> ReminderDefaults {
        // At most hours: the old rule subtracted absolute minutes, while days count calendar days and would differ by an
        // hour on a day with a daylight-saving change.
        let minutes = max(leadTimeMinutes, 0)
        let lead: ReminderOffset = minutes > 0 && minutes % 60 == 0 ? .before(amount: minutes / 60, unit: .hours)
            : .before(amount: minutes, unit: .minutes)
        return ReminderDefaults(
            timed: tasks([lead]).merging([.deadline: [lead], .event: []]) { first, _ in first },
            allDay: tasks([.at(daysBefore: 0, hour: dateOnlyHour, minute: 0)])
                .merging([.deadline: [.at(daysBefore: 1, hour: allDayEventHour, minute: 0)], .event: []]) { first, _ in first })
    }

    /// The same list for every task kind.
    private static func tasks(_ offsets: [ReminderOffset]) -> [ReminderKind: [ReminderOffset]] {
        Dictionary(uniqueKeysWithValues: ReminderKind.taskKinds.map { ($0, offsets) })
    }

    /// Reads stored defaults; without data or with unreadable data the legacy rules apply.
    public static func decode(_ data: Data?, leadTimeMinutes: Int) -> ReminderDefaults {
        guard let data, let decoded = try? JSONDecoder().decode(ReminderDefaults.self, from: data) else {
            return legacy(leadTimeMinutes: leadTimeMinutes)
        }
        return decoded
    }

    public func encoded() -> Data {
        // Sorted keys keep the stored value, and with it the settings hash, identical for equal defaults.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}
