import Foundation
import RemindersKit
import TagwerkCore

/// In-memory calendar; tests can change versions to simulate edits in the Calendar app.
@MainActor
final class FakeCalendarStore: CalendarStore {
    var storedEvents: [CalendarEvent] = []
    var calendars: [ListInfo] = [ListInfo(id: "plan", title: "Tagwerk", colorHex: nil, kind: .calDAV)]
    private var counter = 0

    func events(in interval: DateInterval, calendarIDs: Set<String>?) -> [CalendarEvent] {
        storedEvents.filter { $0.end > interval.start && $0.start < interval.end && (calendarIDs?.contains($0.calendarID) ?? true) }
    }

    func event(id: String) -> CalendarEvent? { storedEvents.first { $0.id == id } }

    func planCalendar(id: String?) -> ListInfo? { calendars.first { $0.id == id } }

    func createPlanCalendar(named: String) throws -> ListInfo {
        let info = ListInfo(id: "new-plan", title: named, colorHex: nil, kind: .calDAV)
        calendars.append(info)
        return info
    }

    func createBlock(_ draft: BlockDraft, in calendarID: String) throws -> CalendarEvent {
        counter += 1
        let event = CalendarEvent(id: "block-\(counter)", externalID: nil, calendarID: calendarID, title: draft.title,
                                  start: draft.start, end: draft.end, isAllDay: false, url: TaskLinkURL.make(draft.taskID),
                                  isBusy: true, version: "v\(counter)")
        storedEvents.append(event)
        return event
    }

    func writableCalendars() -> [ListInfo] { calendars }

    func eventCalendars() -> [ListInfo] { calendars }

    func createEvent(_ draft: EventDraft) throws -> CalendarEvent {
        counter += 1
        var event = CalendarEvent(id: "event-\(counter)", externalID: nil, calendarID: draft.calendarID, title: draft.title,
                                  start: draft.start, end: draft.end, isAllDay: draft.isAllDay, url: draft.url,
                                  isBusy: true, version: "v\(counter)")
        event.notes = draft.notes
        event.location = draft.location
        storedEvents.append(event)
        return event
    }

    /// `.futureEvents` applies the title and the time shift to every later occurrence of the same series ("<id>|<seconds>").
    func updateEvent(id: String, with draft: EventDraft, span: EventSpan, expectedVersion: String?) throws -> CalendarEvent {
        guard let index = storedEvents.firstIndex(where: { $0.id == id }) else { throw TaskWriteError.notFound }
        let current = storedEvents[index]
        try CalendarBlockRules.checkEditable(current)
        try CalendarBlockRules.checkVersion(of: current, expected: expectedVersion)
        let shift = draft.start.timeIntervalSince(current.start)
        let length = draft.end.timeIntervalSince(draft.start)
        let series = CalendarBlockRules.parseOccurrenceID(id).0
        for position in storedEvents.indices {
            let other = storedEvents[position]
            let affected = position == index
                || (span == .futureEvents && current.isRecurring
                    && CalendarBlockRules.parseOccurrenceID(other.id).0 == series && other.start > current.start)
            guard affected else { continue }
            counter += 1
            storedEvents[position].title = draft.title
            storedEvents[position].start = other.start.addingTimeInterval(shift)
            storedEvents[position].end = storedEvents[position].start.addingTimeInterval(length)
            storedEvents[position].isAllDay = draft.isAllDay
            storedEvents[position].url = draft.url
            storedEvents[position].notes = draft.notes
            storedEvents[position].version = "v\(counter)"
        }
        return storedEvents[index]
    }

    func deleteEvent(id: String, span: EventSpan, expectedVersion: String?) throws {
        guard let index = storedEvents.firstIndex(where: { $0.id == id }) else { throw TaskWriteError.notFound }
        let current = storedEvents[index]
        try CalendarBlockRules.checkEditable(current)
        try CalendarBlockRules.checkVersion(of: current, expected: expectedVersion)
        let series = CalendarBlockRules.parseOccurrenceID(id).0
        storedEvents.removeAll { other in
            other.id == id || (span == .futureEvents && current.isRecurring
                               && CalendarBlockRules.parseOccurrenceID(other.id).0 == series && other.start > current.start)
        }
    }
}
