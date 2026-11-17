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

/// Read access to calendar events and write access to the plan calendar only.
@MainActor
public protocol CalendarStore: AnyObject {
    func events(in interval: DateInterval, calendarIDs: Set<String>?) -> [CalendarEvent]
    func event(id: String) -> CalendarEvent?
    /// The plan calendar if it still exists and is writable.
    func planCalendar(id: String?) -> ListInfo?
    func createPlanCalendar(named: String) throws -> ListInfo
    func createBlock(_ draft: BlockDraft, in calendarID: String) throws -> CalendarEvent
    /// Moves one occurrence; throws `.conflict` when `expectedVersion` is stale, `.notFound` when gone.
    func moveBlock(id: String, to start: Date, end: Date, expectedVersion: String?) throws -> CalendarEvent
    func deleteBlock(id: String, expectedVersion: String?) throws
}

/// Pure rules shared by the EventKit implementation and tests.
public enum CalendarBlockRules {
    public static let blockNotes = "Geplant mit Tagwerk"

    public static func checkVersion(of event: CalendarEvent, expected: String?) throws {
        if let expected, expected != event.version {
            throw TaskWriteError.failed("Der Termin wurde inzwischen geändert.")
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
