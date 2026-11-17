import Foundation
import RemindersKit
import SwiftData
import TagwerkCore

/// Effort of a recurring reminder valid from a day on ("Alle" = from this day).
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
}

@MainActor
final class RecurringEffortStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Effort on `day`: a day override wins, otherwise the latest value valid from a day ≤ `day`.
    func minutes(for reminderID: String, on day: PlanDay) -> Int? {
        let key = RecurringEffortOverride.key(reminderID, day)
        var overrideDescriptor = FetchDescriptor<RecurringEffortOverride>(predicate: #Predicate { $0.key == key })
        overrideDescriptor.fetchLimit = 1
        if let override = try? context.fetch(overrideDescriptor).first { return override.minutes }
        return values(reminderID).filter { $0.from <= day }.max { $0.from < $1.from }?.minutes
    }

    /// New base value from `day` on; earlier days keep theirs. `nil` stores 0 (no effort from then on).
    func setForAll(_ minutes: Int?, reminderID: String, from day: PlanDay) {
        for value in values(reminderID) where value.from == day { context.delete(value) }
        context.insert(RecurringEffortValue(reminderID: reminderID, from: day, minutes: minutes ?? 0))
        try? context.save()
    }

    func setForDay(_ minutes: Int, reminderID: String, day: PlanDay) {
        let key = RecurringEffortOverride.key(reminderID, day)
        var descriptor = FetchDescriptor<RecurringEffortOverride>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.minutes = minutes
        } else {
            context.insert(RecurringEffortOverride(reminderID: reminderID, day: day, minutes: minutes))
        }
        try? context.save()
    }

    func markDone(reminderID: String, day: PlanDay) {
        guard !isDone(reminderID: reminderID, day: day) else { return }
        context.insert(RecurringOccurrenceDone(reminderID: reminderID, day: day))
        try? context.save()
    }

    func unmarkDone(reminderID: String, day: PlanDay) {
        let key = RecurringEffortOverride.key(reminderID, day)
        for record in (try? context.fetch(FetchDescriptor<RecurringOccurrenceDone>(predicate: #Predicate { $0.key == key }))) ?? [] {
            context.delete(record)
        }
        try? context.save()
    }

    func isDone(reminderID: String, day: PlanDay) -> Bool {
        let key = RecurringEffortOverride.key(reminderID, day)
        var descriptor = FetchDescriptor<RecurringOccurrenceDone>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    /// Minutes reserved on `day` by all recurring reminders that occur on it, without completed occurrences.
    func reservedMinutes(on day: PlanDay, reminders: [ReminderRecord], calendar: Calendar) -> Int {
        reminders.reduce(0) { total, reminder in
            guard let recurrence = reminder.recurrence, !isDone(reminderID: reminder.id, day: day),
                  !occurrences(of: recurrence, in: day...day, calendar: calendar).isEmpty else { return total }
            return total + (minutes(for: reminder.id, on: day) ?? 0)
        }
    }

    private func values(_ reminderID: String) -> [RecurringEffortValue] {
        (try? context.fetch(FetchDescriptor<RecurringEffortValue>(predicate: #Predicate { $0.reminderID == reminderID }))) ?? []
    }
}
