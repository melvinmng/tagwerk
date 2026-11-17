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

/// A placeholder event ("Busy", "Away", …) at the same time as a real event in another calendar; Tagwerk
/// suggests showing only the real one (design §13.15 M1, detected locally without AI).
public struct MergeSuggestion: Sendable, Hashable, Identifiable {
    public var id: String { placeholderID + "→" + keptID }
    public let placeholderID: String
    public let keptID: String
    public let placeholderTitle: String
    public let placeholderCalendarID: String

    public init(placeholderID: String, keptID: String, placeholderTitle: String, placeholderCalendarID: String) {
        self.placeholderID = placeholderID
        self.keptID = keptID
        self.placeholderTitle = placeholderTitle
        self.placeholderCalendarID = placeholderCalendarID
    }
}

public func isPlaceholderTitle(_ title: String) -> Bool {
    placeholderTitles.contains(normalizedTitle(title))
}

/// Events that may be the same: a placeholder ("Busy" …) next to a real event, or identical titles, each in
/// another calendar with the same start, end and all-day flag. Nothing is merged without the user's answer
/// (design §13.15 M1, user decision 2026-11-18). The copy with more information is kept; calendars in
/// `excluding` (deadline calendars) never take part.
public func mergeSuggestions(_ events: [CalendarEvent], excluding: Set<String> = []) -> [MergeSuggestion] {
    let candidates = events.filter { !excluding.contains($0.calendarID) }
    var result: [MergeSuggestion] = []
    var hidden = Set<String>()
    for event in candidates where !hidden.contains(event.id) {
        let sameTime = candidates.filter { other in
            other.id != event.id && other.calendarID != event.calendarID && !hidden.contains(other.id)
                && other.start == event.start && other.end == event.end && other.isAllDay == event.isAllDay
        }
        if isPlaceholderTitle(event.title) {
            guard let kept = sameTime.first(where: { !isPlaceholderTitle($0.title) }) else { continue }
            hidden.insert(event.id)
            result.append(MergeSuggestion(placeholderID: event.id, keptID: kept.id, placeholderTitle: event.title,
                                          placeholderCalendarID: event.calendarID))
        } else if let twin = sameTime.first(where: { normalizedTitle($0.title) == normalizedTitle(event.title) }) {
            // Keep the copy with more information; on a tie the earlier event.
            let (kept, other) = informationScore(twin) > informationScore(event) ? (twin, event) : (event, twin)
            hidden.insert(other.id)
            result.append(MergeSuggestion(placeholderID: other.id, keptID: kept.id, placeholderTitle: other.title,
                                          placeholderCalendarID: other.calendarID))
        }
    }
    return result
}
