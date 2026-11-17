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

    func moveBlock(id: String, to start: Date, end: Date, expectedVersion: String?) throws -> CalendarEvent {
        guard let index = storedEvents.firstIndex(where: { $0.id == id }) else { throw TaskWriteError.notFound }
        try CalendarBlockRules.checkVersion(of: storedEvents[index], expected: expectedVersion)
        storedEvents[index].start = start
        storedEvents[index].end = end
        counter += 1
        storedEvents[index].version = "v\(counter)"
        return storedEvents[index]
    }

    func deleteBlock(id: String, expectedVersion: String?) throws {
        guard let index = storedEvents.firstIndex(where: { $0.id == id }) else { throw TaskWriteError.notFound }
        try CalendarBlockRules.checkVersion(of: storedEvents[index], expected: expectedVersion)
        storedEvents.remove(at: index)
    }
}
