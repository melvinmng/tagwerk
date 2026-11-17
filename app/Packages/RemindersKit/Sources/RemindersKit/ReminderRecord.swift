import Foundation
import TagwerkCore

/// Plain snapshot of a reminder, decoupled from EventKit so that logic can be tested without it.
public struct ReminderRecord: Sendable, Equatable {
    public var id: String
    public var title: String
    public var notes: String?
    public var due: DueDate?
    /// EventKit priority: 0 = none, 1 = highest, 9 = lowest.
    public var ekPriority: Int
    public var isCompleted: Bool
    public var listID: String
    public var lastModified: Date?
    /// Repetition of the reminder, if any (read-only; Tagwerk never edits it).
    public var recurrence: Recurrence?

    public init(id: String, title: String, notes: String?, due: DueDate?, ekPriority: Int,
                isCompleted: Bool, listID: String, lastModified: Date?, recurrence: Recurrence? = nil) {
        self.recurrence = recurrence
        self.id = id
        self.title = title
        self.notes = notes
        self.due = due
        self.ekPriority = ekPriority
        self.isCompleted = isCompleted
        self.listID = listID
        self.lastModified = lastModified
    }
}

/// Kind of a calendar or reminder list, used for default selection.
public enum CalendarKind: Sendable, Equatable {
    case local, calDAV, exchange, subscription, birthday, other
}

/// A reminder list or an event calendar.
public struct ListInfo: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let colorHex: String?
    public let kind: CalendarKind

    public init(id: String, title: String, colorHex: String?, kind: CalendarKind) {
        self.id = id
        self.title = title
        self.colorHex = colorHex
        self.kind = kind
    }
}

/// Authorization state for reminders or events.
public enum AccessState: Sendable, Equatable {
    case notDetermined, fullAccess, writeOnly, denied, restricted
}
