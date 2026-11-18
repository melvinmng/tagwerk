import Foundation

/// What Tagwerk remembers about a calendar event it marked or linked, so it can find the event again after the
/// source changed its identifier or time (plan deadline-marking, "Wiederfinden").
public struct EventReference: Sendable, Hashable {
    /// `CalendarEvent.id` when it was remembered (the occurrence ID for series).
    public var eventKey: String
    /// `calendarItemExternalIdentifier`: the same for all occurrences of a series, may repeat across accounts.
    public var externalID: String?
    public var calendarID: String
    public var title: String
    public var start: Date

    public init(eventKey: String, externalID: String?, calendarID: String, title: String, start: Date) {
        self.eventKey = eventKey
        self.externalID = externalID
        self.calendarID = calendarID
        self.title = title
        self.start = start
    }
}

/// The result of looking for a remembered event among the events read.
public enum EventReferenceMatch: Sendable, Hashable {
    /// Same event: same ID, or same server identifier, calendar and start (only the local ID changed).
    case exact(CalendarEvent)
    /// The only event with the same server identifier in the calendar, not a series: the source moved it.
    case moved(CalendarEvent)
    /// The only event with the same title in the calendar within 14 days: a suggestion, never applied silently.
    case candidate(CalendarEvent)
    /// The calendar was read over the remembered start and the event is not there.
    case missing
    /// The calendar was not read, or not over the remembered start: nothing can be said.
    case unknown
}

/// Days around the remembered start in which an event with the same title counts as a candidate.
public let eventReferenceTitleWindowDays = 14

/// Looks for `reference` among `events` in this order: same ID; same server identifier, calendar and start; the
/// only event with the same server identifier in the calendar that is not part of a series; the only event with the
/// same title in the calendar within 14 days (candidate). `missing` only when the calendar is in
/// `readCalendarIDs` and `window` contains the remembered start, otherwise `unknown`. `matchesExternalID == false`
/// skips the server identifier steps (for feeds that hand out new identifiers on every refresh).
public func resolveEventReference(_ reference: EventReference, in events: [CalendarEvent], readCalendarIDs: Set<String>,
                                  window: DateInterval, matchesExternalID: Bool = true) -> EventReferenceMatch {
    guard readCalendarIDs.contains(reference.calendarID) else { return .unknown }
    let sameCalendar = events.filter { $0.calendarID == reference.calendarID }
    if let same = sameCalendar.first(where: { $0.id == reference.eventKey }) { return .exact(same) }

    if matchesExternalID, let externalID = reference.externalID, !externalID.isEmpty {
        var seen = Set<String>()
        let sameServerID = sameCalendar.filter { $0.externalID == externalID && seen.insert($0.id).inserted }
        if let sameStart = sameServerID.first(where: { $0.start == reference.start }) { return .exact(sameStart) }
        if sameServerID.count == 1, let only = sameServerID.first, !only.isRecurring { return .moved(only) }
    }

    let title = normalizedTitle(reference.title)
    let span = TimeInterval(eventReferenceTitleWindowDays * 86_400)
    var seen = Set<String>()
    let sameTitle = sameCalendar.filter { event in
        normalizedTitle(event.title) == title && abs(event.start.timeIntervalSince(reference.start)) <= span
            && seen.insert(event.id).inserted
    }
    if sameTitle.count == 1, let only = sameTitle.first { return .candidate(only) }
    return window.contains(reference.start) ? .missing : .unknown
}

// MARK: Preparation (DV1)

/// Time and number of preparation events that still lie ahead of a deadline.
public struct PreparationSummary: Sendable, Hashable {
    public let minutes: Int
    public let count: Int

    public init(minutes: Int, count: Int) {
        self.minutes = minutes
        self.count = count
    }
}

/// Events that have not ended at `now` and start before `deadline`, each counted once; all-day events count as an
/// event without minutes.
public func preparationSummary(_ events: [CalendarEvent], now: Date, deadline: Date) -> PreparationSummary {
    var seen = Set<String>()
    let upcoming = events.filter { $0.end > now && $0.start < deadline && seen.insert($0.id).inserted }
    let minutes = upcoming.filter { !$0.isAllDay }.reduce(0) { $0 + max(0, Int($1.end.timeIntervalSince($1.start) / 60)) }
    return PreparationSummary(minutes: minutes, count: upcoming.count)
}

// MARK: Keyword suggestions (DL3)

/// Word stems that suggest an exam or a submission; compounds match at the start or end of a word.
let deadlineKeywordStems = ["klausur", "prüfung", "abgabe", "abgabefrist", "frist", "deadline", "exam", "examination",
                            "submission"]
/// Stems that point to preparation rather than the deadline itself ("Klausurvorbereitung", "Lerngruppe").
let deadlinePreparationStems = ["vorbereitung", "lernen", "lerngruppe", "lernblock", "tutorium", "einsicht", "übung",
                                "preparation", "prep", "study", "review", "tutorial"]

/// A title that looks like an exam or a submission (detected locally, without AI).
public func looksLikeDeadline(_ title: String) -> Bool {
    let words = title.precomposedStringWithCanonicalMapping.lowercased().split { !$0.isLetter }.map(String.init)
    if words.contains(where: { word in deadlinePreparationStems.contains { word.contains($0) } }) { return false }
    return words.contains { word in deadlineKeywordStems.contains { word.hasPrefix($0) || word.hasSuffix($0) } }
}

/// Events whose title looks like a deadline, without the excluded events (marked, dismissed) and calendars
/// (deadline calendars), each once, ordered by start.
public func deadlineSuggestions(events: [CalendarEvent], excludingEventIDs: Set<String>,
                                excludingCalendarIDs: Set<String>) -> [CalendarEvent] {
    var seen = Set<String>()
    return events
        .filter { event in
            !excludingEventIDs.contains(event.id) && !excludingCalendarIDs.contains(event.calendarID)
                && looksLikeDeadline(event.title) && seen.insert(event.id).inserted
        }
        .sorted { $0.start < $1.start }
}
