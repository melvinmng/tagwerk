import Foundation

/// A reminder list of one entry that replaces the default (plan P4, assumptions A2 and A8).
public struct ReminderOverride: Hashable, Sendable {
    /// Which occurrences of the entry the list applies to.
    public enum Scope: Hashable, Sendable {
        /// The entry in every case (a task without a repetition, a reminder, an issue).
        case always
        /// A repeating task for as long as its due date is this one ("only this one").
        case onlyDue(DueDate)
        /// One occurrence of a series, by its occurrence identifier.
        case occurrence(String)
        /// A series from this day on ("this and all following").
        case seriesFrom(PlanDay)
    }

    /// Where the reminders live.
    public enum Storage: String, Hashable, Sendable {
        /// Tagwerk notifications.
        case tagwerk
        /// EventKit alarms written by Tagwerk; Tagwerk plans no notifications of its own for the entry.
        case eventKit
    }

    public var itemKey: String
    public var scope: Scope
    public var storage: Storage
    public var offsets: [ReminderOffset]

    public init(itemKey: String, scope: Scope, storage: Storage = .tagwerk, offsets: [ReminderOffset]) {
        self.itemKey = itemKey
        self.scope = scope
        self.storage = storage
        self.offsets = offsets
    }

    /// Key of a task's overrides.
    public static func key(task: TaskID) -> String { "task:\(task.key)" }

    /// Key of the overrides of a deadline series; `baseID` is the identifier of the series without the occurrence part.
    public static func key(deadlineSeries baseID: String) -> String { "deadline:\(baseID)" }
}

/// The reminders an entry gets after applying its overrides.
public struct ResolvedReminders: Hashable, Sendable {
    public var offsets: [ReminderOffset]
    public var storage: ReminderOverride.Storage
    /// True when an override decided, false for the default.
    public var isCustom: Bool
}

public enum ReminderOverrideResolution {
    /// Picks the reminders for one entry. Precedence: this occurrence, then "only this due date" while the due date is
    /// unchanged, then the series override from the latest day that is not after `day`, then the entry-wide one, then
    /// `defaults`.
    public static func resolve(itemKey: String, occurrenceID: String? = nil, day: PlanDay? = nil, due: DueDate? = nil,
                               isAllDay: Bool, overrides: [String: [ReminderOverride]],
                               defaults: [ReminderOffset]) -> ResolvedReminders {
        let candidates = overrides[itemKey] ?? []
        let chosen = candidates.first { if case .occurrence(let id) = $0.scope { return id == occurrenceID } else { return false } }
            ?? candidates.first { if case .onlyDue(let value) = $0.scope { return value == due } else { return false } }
            ?? candidates.compactMap { override -> (PlanDay, ReminderOverride)? in
                guard case .seriesFrom(let start) = override.scope, let day, start <= day else { return nil }
                return (start, override)
            }.max { $0.0 < $1.0 }?.1
            ?? candidates.first { $0.scope == .always }
        guard let chosen else {
            return ResolvedReminders(offsets: ReminderOffset.normalized(defaults, isAllDay: isAllDay), storage: .tagwerk, isCustom: false)
        }
        return ResolvedReminders(offsets: ReminderOffset.normalized(chosen.offsets, isAllDay: isAllDay), storage: chosen.storage,
                                 isCustom: true)
    }
}
