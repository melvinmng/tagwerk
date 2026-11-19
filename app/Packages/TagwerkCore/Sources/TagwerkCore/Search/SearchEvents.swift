import Foundation

/// Period the search reads events from.
public enum SearchWindow {
    /// Start of today minus six months up to start of today plus twelve months.
    public static func initial(now: Date, calendar: Calendar) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .month, value: -6, to: today) ?? today
        let end = calendar.date(byAdding: .month, value: 12, to: today) ?? today
        return DateInterval(start: start, end: end)
    }

    /// The year before `start`.
    public static func extended(before start: Date, calendar: Calendar) -> DateInterval {
        let earlier = calendar.date(byAdding: .year, value: -1, to: start) ?? start
        return DateInterval(start: earlier, end: start)
    }

    /// The "Ältere Termine durchsuchen" row stays while the last fetched year had events and is younger than ten years.
    public static func canExtend(lastYearWasEmpty: Bool, start: Date, now: Date, calendar: Calendar) -> Bool {
        guard !lastYearWasEmpty else { return false }
        let today = calendar.startOfDay(for: now)
        guard let limit = calendar.date(byAdding: .year, value: -10, to: today) else { return false }
        return start > limit
    }
}

/// Mirrors the ID rules of `CalendarBlockRules` (RemindersKit), which this package cannot call.
public enum SearchEventID {
    /// "<identifier>" without "#<calendarID>" scope and "|<seconds>" occurrence suffix.
    public static func base(_ id: String) -> String {
        var identifier = id
        if let separator = id.lastIndex(of: "|"), Int(id[id.index(after: separator)...]) != nil {
            identifier = String(id[..<separator])
        }
        if let separator = identifier.lastIndex(of: "#") {
            identifier = String(identifier[..<separator])
        }
        return identifier
    }
}

public enum SearchEvents {
    /// Drops time blocks (plan calendar + task link URL) and merges duplicates like "Planen" when `merge` is on.
    public static func prepare(_ raw: [CalendarEvent], planCalendarID: String?, merge: Bool) -> [CalendarEvent] {
        let events = raw.filter { event in
            guard let planCalendarID, event.calendarID == planCalendarID, let url = event.url else { return true }
            return TaskLinkURL.parse(url) == nil
        }
        return merge ? mergingDuplicates(events, links: [:]) : events
    }
}

public enum SeriesRhythm: Sendable, Equatable {
    case daily, weekly, biweekly, monthly
}

/// One event row of the search; a series collapses into the row of its next occurrence.
public struct EventRow: Sendable, Equatable, Identifiable {
    public var id: String { event.id }
    public let event: CalendarEvent
    /// Further matching occurrences in the window; 0 for single events and past rows.
    public let moreOccurrences: Int
    /// Start of the last matching occurrence in the window; `nil` without further occurrences.
    public let lastOccurrence: Date?
    public let rhythm: SeriesRhythm?

    public init(event: CalendarEvent, moreOccurrences: Int = 0, lastOccurrence: Date? = nil, rhythm: SeriesRhythm? = nil) {
        self.event = event
        self.moreOccurrences = moreOccurrences
        self.lastOccurrence = lastOccurrence
        self.rhythm = rhythm
    }
}

public enum EventSeriesGrouping {
    private struct SeriesKey: Hashable {
        let base: String
        let calendarID: String
    }

    /// Upcoming: next first, one row per series. Past (end before now): latest first, only the latest occurrence per series.
    public static func rows(_ events: [CalendarEvent], now: Date, calendar: Calendar) -> (upcoming: [EventRow], past: [EventRow]) {
        let pastEvents = events.filter { isPast($0, now: now, calendar: calendar) }
        let upcomingEvents = events.filter { !isPast($0, now: now, calendar: calendar) }

        let upcoming = grouped(upcomingEvents).map { group -> EventRow in
            let sorted = group.sorted { $0.start < $1.start }
            guard sorted.count > 1, let last = sorted.last else { return EventRow(event: sorted[0]) }
            return EventRow(event: sorted[0], moreOccurrences: sorted.count - 1, lastOccurrence: last.start,
                            rhythm: rhythm(of: sorted.map(\.start), calendar: calendar))
        }
        let past = grouped(pastEvents).compactMap { group in
            group.max { $0.start < $1.start }.map { EventRow(event: $0) }
        }
        return (upcoming.sorted { ($0.event.start, $0.event.id) < ($1.event.start, $1.event.id) },
                past.sorted { ($0.event.start, $0.event.id) > ($1.event.start, $1.event.id) })
    }

    /// An event is past when it ended before now; an all-day event of today is upcoming.
    public static func isPast(_ event: CalendarEvent, now: Date, calendar: Calendar) -> Bool {
        if event.isAllDay { return event.end <= calendar.startOfDay(for: now) }
        return event.end < now
    }

    /// Occurrences of one series (recurring, same base ID, same calendar) form a group; everything else stays alone.
    private static func grouped(_ events: [CalendarEvent]) -> [[CalendarEvent]] {
        var series: [SeriesKey: Int] = [:]
        var groups: [[CalendarEvent]] = []
        for event in events {
            guard event.isRecurring else {
                groups.append([event])
                continue
            }
            let key = SeriesKey(base: SearchEventID.base(event.id), calendarID: event.calendarID)
            if let index = series[key] {
                groups[index].append(event)
            } else {
                series[key] = groups.count
                groups.append([event])
            }
        }
        return groups
    }

    private static func rhythm(of starts: [Date], calendar: Calendar) -> SeriesRhythm? {
        guard starts.count > 1 else { return nil }
        let days = starts.map { calendar.startOfDay(for: $0) }
        let gaps = zip(days, days.dropFirst()).map { calendar.dateComponents([.day], from: $0, to: $1).day ?? 0 }
        if gaps.allSatisfy({ $0 == 1 }) { return .daily }
        if gaps.allSatisfy({ $0 == 7 }) { return .weekly }
        if gaps.allSatisfy({ $0 == 14 }) { return .biweekly }
        let isMonthly = zip(days, days.dropFirst()).allSatisfy { earlier, later in
            calendar.date(byAdding: .month, value: 1, to: earlier) == later
                && calendar.component(.day, from: earlier) == calendar.component(.day, from: later)
        }
        return isMonthly ? .monthly : nil
    }
}

/// Finds the event of a fresh day fetch that a search hit stands for. The IDs of an 18-month fetch can differ
/// from those of a day fetch (`CalendarBlockRules.uniqueIDs` depends on the events of one fetch), so the hit is
/// matched by base ID, start and calendar.
public enum SearchEventResolver {
    /// Same base ID and same start, in the hit's calendar or in a calendar either side was merged from.
    /// The hit's own calendar wins when several copies match.
    public static func resolve(_ hit: CalendarEvent, among dayEvents: [CalendarEvent]) -> CalendarEvent? {
        let base = SearchEventID.base(hit.id)
        let candidates = dayEvents.filter { event in
            guard event.start == hit.start, SearchEventID.base(event.id) == base else { return false }
            return event.calendarID == hit.calendarID
                || hit.mergedCalendarIDs.contains(event.calendarID)
                || event.mergedCalendarIDs.contains(hit.calendarID)
        }
        return candidates.first { $0.calendarID == hit.calendarID } ?? candidates.first
    }
}
