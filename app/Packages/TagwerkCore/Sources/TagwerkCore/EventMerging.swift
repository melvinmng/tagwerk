import Foundation

/// Collapses events that appear in several calendars with the same title, start, end and all-day flag
/// into one (design §13.11). A linked copy wins, otherwise the first; the other calendars are kept in
/// `mergedCalendarIDs`. Events of the same calendar are never merged. Order follows the input.
public func mergingDuplicates(_ events: [CalendarEvent], links: [String: TaskID]) -> [CalendarEvent] {
    struct Key: Hashable {
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
    }
    var groups: [Key: [CalendarEvent]] = [:]
    var order: [Key] = []
    for event in events {
        let key = Key(title: normalizedTitle(event.title), start: event.start, end: event.end, isAllDay: event.isAllDay)
        if groups[key] == nil { order.append(key) }
        groups[key, default: []].append(event)
    }
    return order.flatMap { key -> [CalendarEvent] in
        let group = groups[key] ?? []
        var result: [CalendarEvent] = []
        var remaining = group
        while !remaining.isEmpty {
            // One representative per set of distinct calendars; same-calendar copies stay separate.
            var calendars = Set<String>()
            var batch: [CalendarEvent] = []
            remaining.removeAll { event in
                guard !calendars.contains(event.calendarID) else { return false }
                calendars.insert(event.calendarID)
                batch.append(event)
                return true
            }
            var kept = batch.first { links[$0.id] != nil } ?? batch.reduce(batch[0]) { best, next in informationScore(next) > informationScore(best) ? next : best }
            kept.mergedCalendarIDs = batch.filter { $0.id != kept.id }.map(\.calendarID)
            result.append(kept)
        }
        return result
    }
}

/// How much an event tells: notes, location, link; placeholder titles ("Busy", "Away", …) count against it.
func informationScore(_ event: CalendarEvent) -> Int {
    var score = 0
    if !(event.notes ?? "").isEmpty { score += 2 }
    if !(event.location ?? "").isEmpty { score += 2 }
    if event.url != nil { score += 1 }
    if placeholderTitles.contains(normalizedTitle(event.title)) { score -= 3 }
    return score
}

/// Titles that mirrored or shared calendars use instead of the real one (design §13, merge suggestions in 2b-2).
public let placeholderTitles: Set<String> = ["busy", "away", "free", "tentative", "beschäftigt", "abwesend", "frei",
                                             "vorläufig", "out of office", "privat"]
