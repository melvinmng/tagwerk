import Foundation

/// A calendar event as Tagwerk sees it. For recurring events, `id` identifies one occurrence.
public struct CalendarEvent: Sendable, Hashable, Identifiable {
    public let id: String
    public let externalID: String?
    public let calendarID: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var url: URL?
    /// False for events marked "free" and for declined invitations.
    public var isBusy: Bool
    public var version: String
    /// Other calendars that hold the same event (merged display, design §13.11).
    public var mergedCalendarIDs: [String] = []

    public init(id: String, externalID: String?, calendarID: String, title: String, start: Date, end: Date,
                isAllDay: Bool, url: URL?, isBusy: Bool, version: String) {
        self.id = id
        self.externalID = externalID
        self.calendarID = calendarID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.url = url
        self.isBusy = isBusy
        self.version = version
    }
}
