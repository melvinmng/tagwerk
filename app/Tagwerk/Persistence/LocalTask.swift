import Foundation
import SwiftData
import TagwerkCore

/// A task that exists only in Tagwerk.
/// Schema rule: later attributes must be optional or have a default value (data survives reinstalls).
@Model
final class LocalTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String?
    var dueYear: Int?
    var dueMonth: Int?
    var dueDay: Int?
    var dueHour: Int?
    var dueMinute: Int?
    var priorityRaw: Int?
    var estimateMinutes: Int?
    var isCompleted: Bool
    /// Incremented on every change; serves as the task version for conflict checks.
    var revision: Int
    var createdAt: Date
    /// When the task was ticked off (phase 4, weekly review); `nil` while open and for tasks completed before phase 4.
    var completedAt: Date?
    /// The repetition as JSON (`Recurrence`); `nil` for single tasks. Its `start` is ignored when reading:
    /// the series starts at the due date (plan 2026-11-18, stage 2).
    var recurrenceData: Data?

    init(id: UUID = UUID(), title: String, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.isCompleted = false
        self.revision = 1
        self.createdAt = createdAt
    }

    var due: DueDate? {
        get {
            guard let dueYear, let dueMonth, let dueDay else { return nil }
            return DueDate(year: dueYear, month: dueMonth, day: dueDay, hour: dueHour, minute: dueMinute)
        }
        set {
            dueYear = newValue?.year
            dueMonth = newValue?.month
            dueDay = newValue?.day
            dueHour = newValue?.hour
            dueMinute = newValue?.minute
        }
    }

    var priority: Priority? {
        get { priorityRaw.flatMap(Priority.init(rawValue:)) }
        set { priorityRaw = newValue?.rawValue }
    }

    /// The stored repetition, starting at the current due date; `nil` without a due date.
    var recurrence: Recurrence? {
        get {
            guard let recurrenceData, let due,
                  var recurrence = try? JSONDecoder().decode(Recurrence.self, from: recurrenceData) else { return nil }
            recurrence.start = PlanDay(due)
            return recurrence
        }
        set { recurrenceData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }
}

/// One occurrence of a repeating local task ticked off in Tagwerk while the task moved on to its next
/// occurrence (the last occurrence completes the task and counts through `LocalTask.completedAt`).
/// Feeds the weekly review and holds the state before the completion for "Rückgängig".
@Model
final class LocalOccurrenceCompletion {
    var taskID: UUID
    var completedAt: Date
    var previousDueYear: Int
    var previousDueMonth: Int
    var previousDueDay: Int
    var previousDueHour: Int?
    var previousDueMinute: Int?
    var previousCount: Int?
    /// Revision of the task right after the completion; undo applies only while the task is unchanged since.
    var revision: Int

    init(taskID: UUID, completedAt: Date, previousDue: DueDate, previousCount: Int?, revision: Int) {
        self.taskID = taskID
        self.completedAt = completedAt
        self.previousDueYear = previousDue.year
        self.previousDueMonth = previousDue.month
        self.previousDueDay = previousDue.day
        self.previousDueHour = previousDue.hour
        self.previousDueMinute = previousDue.minute
        self.previousCount = previousCount
        self.revision = revision
    }

    var previousDue: DueDate {
        DueDate(year: previousDueYear, month: previousDueMonth, day: previousDueDay,
                hour: previousDueHour, minute: previousDueMinute)
    }
}
