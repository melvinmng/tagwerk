import Foundation
import TagwerkCore

/// Pure conversions between reminder snapshots and tasks.
public enum ReminderMapping {
    /// EK 1 → P1, 2–4 → P2, 5 → P3, 6–8 → P4, 9 → P5, anything else → none.
    public static func priority(fromEK value: Int) -> Priority? {
        switch value {
        case 1: .p1
        case 2...4: .p2
        case 5: .p3
        case 6...8: .p4
        case 9: .p5
        default: nil
        }
    }

    /// P1 → 1, P2 → 3, P3 → 5, P4 → 7, P5 → 9, none → 0.
    public static func ekPriority(from priority: Priority?) -> Int {
        switch priority {
        case .p1: 1
        case .p2: 3
        case .p3: 5
        case .p4: 7
        case .p5: 9
        case nil: 0
        }
    }

    public static func taskItem(_ record: ReminderRecord, list: ListInfo) -> TaskItem {
        TaskItem(
            id: TaskID(source: .reminders, rawValue: record.id),
            title: record.title,
            notes: record.notes,
            due: record.due,
            priority: priority(fromEK: record.ekPriority),
            estimateMinutes: nil,
            isCompleted: record.isCompleted,
            container: TaskContainer(id: list.id, name: list.title, colorHex: list.colorHex),
            url: nil,
            version: record.lastModified.map { String($0.timeIntervalSince1970) } ?? "0",
            editableFields: [.title, .notes, .due, .priority, .container]
        )
    }

    /// Returns `record` with exactly the `.set` fields of `edit` applied. Priority is only
    /// rewritten when the edit sets it, so lossy mapping never changes untouched reminders.
    public static func applying(_ edit: TaskEdit, to record: ReminderRecord) -> ReminderRecord {
        var result = record
        if case .set(let title) = edit.title { result.title = title }
        if case .set(let notes) = edit.notes { result.notes = notes }
        if case .set(let due) = edit.due { result.due = due }
        if case .set(let priority) = edit.priority { result.ekPriority = ekPriority(from: priority) }
        if case .set(let listID) = edit.containerID { result.listID = listID }
        if case .set(let completed) = edit.isCompleted { result.isCompleted = completed }
        return result
    }

    // MARK: Alarms

    /// Reminders alert through alarms, not through the due date. When a timed due date moves,
    /// absolute alarms that fired exactly at the old due moment move with it; other alarms stay.
    public static func movedAlarmDates(_ alarms: [Date], from oldDue: Date?, to newDue: Date?) -> [Date] {
        guard let oldDue, let newDue else { return alarms }
        return alarms.map { $0 == oldDue ? newDue : $0 }
    }

    /// Alarm for a new reminder: at the due time, none for a date without time.
    public static func alarmDate(for due: DueDate?, calendar: Calendar) -> Date? {
        guard let due, due.hasTime else { return nil }
        return due.startDate(in: calendar)
    }
}
