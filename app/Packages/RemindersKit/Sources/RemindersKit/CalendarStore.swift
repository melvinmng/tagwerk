import Foundation
import TagwerkCore

/// A time block to write into the plan calendar.
public struct BlockDraft: Sendable, Equatable {
    public var title: String
    public var start: Date
    public var end: Date
    public var taskID: TaskID

    public init(title: String, start: Date, end: Date, taskID: TaskID) {
        self.title = title
        self.start = start
        self.end = end
        self.taskID = taskID
    }
}

/// Which occurrences of a series a change affects (maps to `EKSpan`).
public enum EventSpan: Sendable, Hashable {
    case thisEvent, futureEvents
}

/// The editable fields of a calendar event.
public struct EventDraft: Sendable, Equatable {
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendarID: String
    public var notes: String?
    public var location: String?
    public var url: URL?

    public init(title: String, start: Date, end: Date, isAllDay: Bool, calendarID: String, notes: String?,
                location: String?, url: URL?) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarID = calendarID
        self.notes = notes
        self.location = location
        self.url = url
    }

    public init(_ event: CalendarEvent) {
        self.init(title: event.title, start: event.start, end: event.end, isAllDay: event.isAllDay,
                  calendarID: event.calendarID, notes: event.notes, location: event.location, url: event.url)
    }
}

/// Read access to calendar events and write access to every writable calendar (design §13.10).
@MainActor
public protocol CalendarStore: AnyObject {
    func events(in interval: DateInterval, calendarIDs: Set<String>?) -> [CalendarEvent]
    func event(id: String) -> CalendarEvent?
    /// The plan calendar if it still exists and is writable.
    func planCalendar(id: String?) -> ListInfo?
    func createPlanCalendar(named: String) throws -> ListInfo
    /// Event calendars that allow changes.
    func writableCalendars() -> [ListInfo]
    func createBlock(_ draft: BlockDraft, in calendarID: String) throws -> CalendarEvent
    func createEvent(_ draft: EventDraft) throws -> CalendarEvent
    /// Throws a conflict when `expectedVersion` is stale, `.notFound` when gone, and refuses read-only events.
    func updateEvent(id: String, with draft: EventDraft, span: EventSpan, expectedVersion: String?) throws -> CalendarEvent
    func deleteEvent(id: String, span: EventSpan, expectedVersion: String?) throws
}

public extension CalendarStore {
    /// Moves one occurrence of a time block, keeping its other fields.
    func moveBlock(id: String, to start: Date, end: Date, expectedVersion: String?) throws -> CalendarEvent {
        guard let current = event(id: id) else { throw TaskWriteError.notFound }
        var draft = EventDraft(current)
        draft.start = start
        draft.end = end
        return try updateEvent(id: id, with: draft, span: .thisEvent, expectedVersion: expectedVersion)
    }

    func deleteBlock(id: String, expectedVersion: String?) throws {
        try deleteEvent(id: id, span: .thisEvent, expectedVersion: expectedVersion)
    }
}

/// Pure rules shared by the EventKit implementation and tests.
public enum CalendarBlockRules {
    public static let blockNotes = "Geplant mit Tagwerk"

    public static func checkVersion(of event: CalendarEvent, expected: String?) throws {
        if let expected, expected != event.version {
            throw TaskWriteError.failed("Der Termin wurde inzwischen geändert.")
        }
    }

    public static func checkEditable(_ event: CalendarEvent) throws {
        if !event.isEditable || event.isInvitation {
            throw TaskWriteError.failed("Dieser Termin kann in Tagwerk nicht geändert werden.")
        }
    }

    /// Recurring events get one ID per occurrence: "<eventIdentifier>|<occurrence seconds>".
    public static func occurrenceID(eventIdentifier: String, occurrence: Date, isRecurring: Bool) -> String {
        isRecurring ? "\(eventIdentifier)|\(Int(occurrence.timeIntervalSince1970))" : eventIdentifier
    }

    public static func parseOccurrenceID(_ id: String) -> (String, Date?) {
        guard let separator = id.lastIndex(of: "|"), let seconds = Int(id[id.index(after: separator)...]) else {
            return (id, nil)
        }
        return (String(id[..<separator]), Date(timeIntervalSince1970: TimeInterval(seconds)))
    }
}
