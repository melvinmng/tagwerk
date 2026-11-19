import Foundation
import SwiftData
import TagwerkCore

/// Effort of a repeating task valid from a day on ("Alle" = from this day). `reminderID` holds the task key.
/// Schema rule: later attributes must be optional or have a default value.
@Model
final class RecurringEffortValue {
    var reminderID: String
    var fromYear: Int
    var fromMonth: Int
    var fromDay: Int
    var minutes: Int

    init(reminderID: String, from day: PlanDay, minutes: Int) {
        self.reminderID = reminderID
        self.fromYear = day.year
        self.fromMonth = day.month
        self.fromDay = day.day
        self.minutes = minutes
    }

    var from: PlanDay { PlanDay(year: fromYear, month: fromMonth, day: fromDay) }
}

/// Effort for a single occurrence ("Nur dieser Tag"); 0 removes the effort on that day.
@Model
final class RecurringEffortOverride {
    @Attribute(.unique) var key: String
    var reminderID: String
    var year: Int
    var month: Int
    var day: Int
    var minutes: Int

    init(reminderID: String, day: PlanDay, minutes: Int) {
        self.key = Self.key(reminderID, day)
        self.reminderID = reminderID
        self.year = day.year
        self.month = day.month
        self.day = day.day
        self.minutes = minutes
    }

    static func key(_ reminderID: String, _ day: PlanDay) -> String {
        "\(reminderID)|\(String(format: "%04d-%02d-%02d", day.year, day.month, day.day))"
    }

    var planDay: PlanDay { PlanDay(year: year, month: month, day: day) }
}

/// An occurrence completed in Tagwerk; its effort no longer reserves time on that day (design §13.3).
@Model
final class RecurringOccurrenceDone {
    @Attribute(.unique) var key: String
    var reminderID: String

    init(reminderID: String, day: PlanDay) {
        self.key = RecurringEffortOverride.key(reminderID, day)
        self.reminderID = reminderID
    }

    /// The day from the key ("<id>|YYYY-MM-DD").
    var planDay: PlanDay? {
        guard let separator = key.lastIndex(of: "|") else { return nil }
        let parts = key[key.index(after: separator)...].split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return PlanDay(year: parts[0], month: parts[1], day: parts[2])
    }
}

/// A repeating task whose effort is reserved on the days of its occurrences: a reminder with a rule or a
/// local task with a repetition (plan 2026-11-18, stage 2).
struct RecurringSeries: Hashable {
    let id: TaskID
    let title: String
    let recurrence: Recurrence
}

/// Efforts of repeating tasks, keyed by `TaskID.key` (stored in the `reminderID` attributes, whose names stay
/// for the existing stores). Entries written before local tasks could repeat hold the bare reminder ID; they
/// are rewritten to the key once when the store opens.
@MainActor
final class RecurringEffortStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        migrateBareReminderIDs()
    }

    /// Effort on `day`: a day override wins, otherwise the latest value valid from a day ≤ `day`.
    func minutes(for task: TaskID, on day: PlanDay) -> Int? {
        let key = RecurringEffortOverride.key(task.key, day)
        var overrideDescriptor = FetchDescriptor<RecurringEffortOverride>(predicate: #Predicate { $0.key == key })
        overrideDescriptor.fetchLimit = 1
        if let override = try? context.fetch(overrideDescriptor).first { return override.minutes }
        return values(task).filter { $0.from <= day }.max { $0.from < $1.from }?.minutes
    }

    /// New base value from `day` on; earlier days keep theirs. `nil` stores 0 (no effort from then on).
    func setForAll(_ minutes: Int?, task: TaskID, from day: PlanDay) {
        for value in values(task) where value.from == day { context.delete(value) }
        context.insert(RecurringEffortValue(reminderID: task.key, from: day, minutes: minutes ?? 0))
        try? context.save()
    }

    func setForDay(_ minutes: Int, task: TaskID, day: PlanDay) {
        let key = RecurringEffortOverride.key(task.key, day)
        var descriptor = FetchDescriptor<RecurringEffortOverride>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.minutes = minutes
        } else {
            context.insert(RecurringEffortOverride(reminderID: task.key, day: day, minutes: minutes))
        }
        try? context.save()
    }

    func markDone(task: TaskID, day: PlanDay) {
        guard !isDone(task: task, day: day) else { return }
        context.insert(RecurringOccurrenceDone(reminderID: task.key, day: day))
        try? context.save()
    }

    func unmarkDone(task: TaskID, day: PlanDay) {
        let key = RecurringEffortOverride.key(task.key, day)
        for record in (try? context.fetch(FetchDescriptor<RecurringOccurrenceDone>(predicate: #Predicate { $0.key == key }))) ?? [] {
            context.delete(record)
        }
        try? context.save()
    }

    func isDone(task: TaskID, day: PlanDay) -> Bool {
        let key = RecurringEffortOverride.key(task.key, day)
        var descriptor = FetchDescriptor<RecurringOccurrenceDone>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    /// Minutes reserved on `day` by all series that occur on it, without completed occurrences.
    func reservedMinutes(on day: PlanDay, series: [RecurringSeries], calendar: Calendar) -> Int {
        series.reduce(0) { total, item in
            guard !isDone(task: item.id, day: day),
                  !occurrences(of: item.recurrence, in: day...day, calendar: calendar).isEmpty else { return total }
            return total + (minutes(for: item.id, on: day) ?? 0)
        }
    }

    private func values(_ task: TaskID) -> [RecurringEffortValue] {
        let key = task.key
        return (try? context.fetch(FetchDescriptor<RecurringEffortValue>(predicate: #Predicate { $0.reminderID == key }))) ?? []
    }

    /// Rewrites entries keyed by a bare reminder ID (no source prefix) to the reminder's task key. Idempotent:
    /// a key always parses as a `TaskID`, a bare EventKit identifier never does.
    private func migrateBareReminderIDs() {
        func taskKey(_ stored: String) -> String? {
            TaskID(key: stored) == nil ? TaskID(source: .reminders, rawValue: stored).key : nil
        }
        var changed = false
        for value in (try? context.fetch(FetchDescriptor<RecurringEffortValue>())) ?? [] {
            guard let key = taskKey(value.reminderID) else { continue }
            value.reminderID = key
            changed = true
        }
        for override in (try? context.fetch(FetchDescriptor<RecurringEffortOverride>())) ?? [] {
            guard let key = taskKey(override.reminderID) else { continue }
            override.reminderID = key
            override.key = RecurringEffortOverride.key(key, override.planDay)
            changed = true
        }
        for done in (try? context.fetch(FetchDescriptor<RecurringOccurrenceDone>())) ?? [] {
            guard let key = taskKey(done.reminderID), let day = done.planDay else { continue }
            done.reminderID = key
            done.key = RecurringEffortOverride.key(key, day)
            changed = true
        }
        if changed { try? context.save() }
    }
}
