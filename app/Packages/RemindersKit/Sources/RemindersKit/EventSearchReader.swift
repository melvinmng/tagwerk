import EventKit
import Foundation
import TagwerkCore

/// Reads the events of a period for the search, away from the main thread.
public protocol EventSearching: Sendable {
    /// Events of `interval` in the given calendars; `nil` reads all calendars, an empty selection reads none.
    func events(in interval: DateInterval, calendarIDs: Set<String>?) async -> [CalendarEvent]
}

/// Event reader with its own, read-only `EKEventStore`. The store of `EventKitGateway` must not leave the
/// main actor, and a fetch over 18 months would block the interface there. A second store shares the
/// authorization of the app; every call queries the store anew.
public actor EventSearchReader: EventSearching {
    private let store = EKEventStore()

    public init() {}

    public func events(in interval: DateInterval, calendarIDs: Set<String>?) async -> [CalendarEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        var calendars: [EKCalendar]?
        if let calendarIDs {
            let selected = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
            if selected.isEmpty { return [] }
            calendars = selected
        }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: calendars)
        return CalendarBlockRules.uniqueIDs(store.events(matching: predicate).map(EventKitGateway.calendarEvent))
    }
}
