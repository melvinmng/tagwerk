import Foundation
import RemindersKit
import SwiftData
import TagwerkCore

/// A calendar event the user marked as a deadline (plan deadline-marking, DL2). Lives in Tagwerk only; the
/// calendar is never written. Schema rule: later attributes must be optional or have a default value.
@Model
final class EventDeadlineMark {
    /// Occurrence ID when marked (`CalendarEvent.id`), or the series identifier when `isSeries`.
    @Attribute(.unique) var eventKey: String
    /// `calendarItemExternalIdentifier` of the event, used to find it again after the local ID changed.
    var externalID: String?
    var calendarID: String = ""
    var title: String = ""
    /// Start of the marked occurrence; for a series the occurrence it was marked on.
    var start: Date = Date.distantPast
    var isAllDay: Bool = false
    /// All occurrences of the series are deadlines ("Alle Termine der Serie").
    var isSeries: Bool = false
    /// Series only: start of the latest occurrence seen, so a running series is never pruned.
    var lastSeen: Date?
    var createdAt: Date = Date.now

    init(eventKey: String, externalID: String?, calendarID: String, title: String, start: Date, isAllDay: Bool,
         isSeries: Bool, createdAt: Date = .now) {
        self.eventKey = eventKey
        self.externalID = externalID
        self.calendarID = calendarID
        self.title = title
        self.start = start
        self.isAllDay = isAllDay
        self.isSeries = isSeries
        self.createdAt = createdAt
    }

    var reference: EventReference {
        EventReference(eventKey: eventKey, externalID: externalID, calendarID: calendarID, title: title, start: start)
    }

    /// Prune date: 30 days after the remembered date (the latest seen occurrence for a series).
    var lastDate: Date { isSeries ? max(lastSeen ?? start, start) : start }
}

/// A calendar event that belongs to the preparation of a deadline (plan deadline-marking, DV1).
@Model
final class DeadlineEventLink {
    /// `deadlineKey` and `eventKey` joined by a unit separator; never parsed.
    @Attribute(.unique) var key: String
    /// `ImportantDeadline.preparationKey`: "event:<event ID>", "task:<task key>" or "epic:<issue ID>".
    var deadlineKey: String = ""
    /// Occurrence ID, or the series identifier when `isSeries`.
    var eventKey: String = ""
    /// All occurrences from `start` until the deadline ("Alle bis zur Deadline").
    var isSeries: Bool = false
    var externalID: String?
    var calendarID: String = ""
    var title: String = ""
    var start: Date = Date.distantPast
    /// Title and moment of the deadline, for the mark at the linked event and the end of a series link.
    var deadlineTitle: String = ""
    var until: Date = Date.distantFuture
    var createdAt: Date = Date.now

    init(deadlineKey: String, eventKey: String, isSeries: Bool, externalID: String?, calendarID: String, title: String,
         start: Date, deadlineTitle: String, until: Date, createdAt: Date = .now) {
        self.key = Self.key(deadlineKey: deadlineKey, eventKey: eventKey)
        self.deadlineKey = deadlineKey
        self.eventKey = eventKey
        self.isSeries = isSeries
        self.externalID = externalID
        self.calendarID = calendarID
        self.title = title
        self.start = start
        self.deadlineTitle = deadlineTitle
        self.until = until
        self.createdAt = createdAt
    }

    static func key(deadlineKey: String, eventKey: String) -> String { deadlineKey + "\u{1F}" + eventKey }

    var reference: EventReference {
        EventReference(eventKey: eventKey, externalID: externalID, calendarID: calendarID, title: title, start: start)
    }

    /// Whether `event` is (an occurrence of) the linked event before the deadline.
    func covers(_ event: CalendarEvent) -> Bool {
        guard isSeries else { return event.id == eventKey }
        return event.calendarID == calendarID && seriesIdentifier(of: event.id) == eventKey
            && event.start >= start && event.start < until
    }
}

/// A suggestion of the keyword card (DL3) the user answered with "Nein"; asked once per event.
@Model
final class DeadlineSuggestionDismissal {
    @Attribute(.unique) var eventKey: String
    var start: Date = Date.distantPast

    init(eventKey: String, start: Date) {
        self.eventKey = eventKey
        self.start = start
    }
}

/// The series part of an occurrence ID ("<identifier>|<seconds>"); plain IDs stay as they are.
func seriesIdentifier(of eventID: String) -> String {
    CalendarBlockRules.parseOccurrenceID(eventID).0
}

/// A mark whose event Tagwerk could not find again: `candidate` is the only event with the same title nearby
/// ("übernehmen"), `nil` when the event is no longer in the calendar.
struct OrphanedMark: Identifiable, Equatable {
    var id: String { eventKey }
    let eventKey: String
    let title: String
    let calendarID: String
    let start: Date
    let isAllDay: Bool
    let candidate: CalendarEvent?
}

/// What resolving the marks against the events read found.
struct DeadlineMarkResolution: Equatable {
    /// IDs of the read events that are marked deadlines (occurrence IDs, series included).
    var markedIDs: Set<String> = []
    var orphans: [OrphanedMark] = []
}

/// The deadline a linked preparation event belongs to (the mark "→ Klausur Statistik · in 8 Tagen").
struct PreparationTarget: Equatable {
    let deadlineKey: String
    let title: String
    let until: Date
}

/// Tagwerk's deadline marks, preparation links and dismissed keyword suggestions.
@MainActor
final class DeadlineMarkStore {
    /// Marks and links are pruned this long after their date; before that they are never deleted silently.
    static let retentionDays = 30

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Marks

    func marks() -> [EventDeadlineMark] {
        (try? context.fetch(FetchDescriptor<EventDeadlineMark>(sortBy: [SortDescriptor(\.start)]))) ?? []
    }

    /// Marks one occurrence, or (`series`) every occurrence of the event's series. Marking again updates the record.
    func mark(_ event: CalendarEvent, series: Bool) {
        let key = series ? seriesIdentifier(of: event.id) : event.id
        let record = mark(key: key) ?? {
            let new = EventDeadlineMark(eventKey: key, externalID: event.externalID, calendarID: event.calendarID,
                                        title: event.title, start: event.start, isAllDay: event.isAllDay, isSeries: series)
            context.insert(new)
            return new
        }()
        record.externalID = event.externalID
        record.calendarID = event.calendarID
        record.title = event.title
        record.start = event.start
        record.isAllDay = event.isAllDay
        record.isSeries = series
        if series { record.lastSeen = event.start }
        try? context.save()
    }

    /// The mark that makes `event` a deadline: its own, else one for its whole series.
    func mark(for event: CalendarEvent) -> EventDeadlineMark? {
        if let own = mark(key: event.id), !own.isSeries { return own }
        let series = seriesIdentifier(of: event.id)
        guard let record = mark(key: series), record.isSeries, record.calendarID == event.calendarID else { return nil }
        return record
    }

    func isMarked(_ event: CalendarEvent) -> Bool { mark(for: event) != nil }

    /// The IDs of `events` that are marked (single occurrences and every occurrence of marked series).
    func markedIDs(in events: [CalendarEvent]) -> Set<String> {
        let all = marks()
        let single = Set(all.filter { !$0.isSeries }.map(\.eventKey))
        let series = Set(all.filter(\.isSeries).map { "\($0.calendarID)\u{1F}\($0.eventKey)" })
        return Set(events.filter { event in
            single.contains(event.id) || series.contains("\(event.calendarID)\u{1F}\(seriesIdentifier(of: event.id))")
        }.map(\.id))
    }

    /// Removes the mark of `event` (or of its series) and the links to the deadlines it made.
    func unmark(_ event: CalendarEvent) {
        guard let record = mark(for: event) else { return }
        delete(record)
    }

    /// Removes a mark by its key ("Entfernen" on an orphaned row).
    func unmark(key: String) {
        guard let record = mark(key: key) else { return }
        delete(record)
    }

    private func delete(_ record: EventDeadlineMark) {
        for link in links(ofMark: record) { context.delete(link) }
        context.delete(record)
        try? context.save()
    }

    /// Preparation links to the deadlines a mark makes (every occurrence for a series).
    private func links(ofMark record: EventDeadlineMark) -> [DeadlineEventLink] {
        let prefix = "event:" + record.eventKey
        return allLinks().filter { $0.deadlineKey == prefix || (record.isSeries && $0.deadlineKey.hasPrefix(prefix + "|")) }
    }

    /// How many preparation links removing the mark of `event` would dissolve.
    func linkCount(forMarkOf event: CalendarEvent) -> Int {
        mark(for: event).map { links(ofMark: $0).count } ?? 0
    }

    /// "übernehmen": the mark moves to the suggested event.
    func adopt(_ orphan: OrphanedMark, candidate: CalendarEvent) {
        guard let record = mark(key: orphan.eventKey) else { return }
        follow(record, to: candidate)
        try? context.save()
    }

    private func mark(key: String) -> EventDeadlineMark? {
        var descriptor = FetchDescriptor<EventDeadlineMark>(predicate: #Predicate { $0.eventKey == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: Finding marks again

    /// Finds every mark among `events` (read from `readCalendarIDs` over `window`), follows events whose local ID or
    /// time changed and reports the ones that are gone or only have a candidate. Nothing is deleted here.
    func resolve(events: [CalendarEvent], readCalendarIDs: Set<String>, window: DateInterval,
                 matchesExternalID: Bool = true, now: Date) -> DeadlineMarkResolution {
        var resolution = DeadlineMarkResolution()
        var changed = false
        for record in marks() {
            if record.isSeries {
                let occurrences = events.filter { $0.calendarID == record.calendarID && seriesIdentifier(of: $0.id) == record.eventKey }
                if let latest = occurrences.map(\.start).max() {
                    if (record.lastSeen ?? .distantPast) < latest { record.lastSeen = latest; changed = true }
                    continue
                }
                // The series got a new local identifier: follow the first recurring event with the same server ID.
                if matchesExternalID, let externalID = record.externalID, !externalID.isEmpty,
                   let renamed = events.first(where: { $0.calendarID == record.calendarID && $0.externalID == externalID && $0.isRecurring }) {
                    rewriteDeadlineKeys(from: record.eventKey, to: seriesIdentifier(of: renamed.id), series: true)
                    record.eventKey = seriesIdentifier(of: renamed.id)
                    record.lastSeen = events.filter { seriesIdentifier(of: $0.id) == record.eventKey }.map(\.start).max()
                    changed = true
                }
                continue
            }
            switch resolveEventReference(record.reference, in: events, readCalendarIDs: readCalendarIDs, window: window,
                                         matchesExternalID: matchesExternalID) {
            case .exact(let event), .moved(let event):
                if event.id != record.eventKey || event.start != record.start || event.title != record.title
                    || event.isAllDay != record.isAllDay {
                    follow(record, to: event)
                    changed = true
                }
            case .candidate(let event):
                resolution.orphans.append(orphan(record, candidate: event))
            case .missing:
                resolution.orphans.append(orphan(record, candidate: nil))
            case .unknown:
                break
            }
        }
        for link in allLinks() where !link.isSeries {
            switch resolveEventReference(link.reference, in: events, readCalendarIDs: readCalendarIDs, window: window,
                                         matchesExternalID: matchesExternalID) {
            case .exact(let event), .moved(let event):
                if event.id != link.eventKey || event.start != link.start {
                    relink(link, deadlineKey: link.deadlineKey, eventKey: event.id)
                    link.start = event.start
                    changed = true
                }
            default:
                break
            }
        }
        if changed { try? context.save() }
        resolution.markedIDs = markedIDs(in: events)
        return resolution
    }

    private func orphan(_ record: EventDeadlineMark, candidate: CalendarEvent?) -> OrphanedMark {
        OrphanedMark(eventKey: record.eventKey, title: record.title, calendarID: record.calendarID, start: record.start,
                     isAllDay: record.isAllDay, candidate: candidate)
    }

    /// Moves a single-occurrence mark to `event` and keeps the links to its deadline.
    private func follow(_ record: EventDeadlineMark, to event: CalendarEvent) {
        if event.id != record.eventKey, mark(key: event.id) == nil {
            rewriteDeadlineKeys(from: record.eventKey, to: event.id, series: false)
            record.eventKey = event.id
        }
        record.start = event.start
        record.title = event.title
        record.isAllDay = event.isAllDay
        record.calendarID = event.calendarID
        record.externalID = event.externalID ?? record.externalID
        for link in allLinks() where link.deadlineKey == "event:" + record.eventKey {
            link.until = event.start
            link.deadlineTitle = event.title
        }
    }

    private func rewriteDeadlineKeys(from old: String, to new: String, series: Bool) {
        for link in allLinks() {
            if link.deadlineKey == "event:" + old {
                relink(link, deadlineKey: "event:" + new, eventKey: link.eventKey)
            } else if series, link.deadlineKey.hasPrefix("event:" + old + "|") {
                let occurrence = link.deadlineKey.dropFirst(("event:" + old).count)
                relink(link, deadlineKey: "event:" + new + occurrence, eventKey: link.eventKey)
            }
        }
    }

    private func relink(_ link: DeadlineEventLink, deadlineKey: String, eventKey: String) {
        link.deadlineKey = deadlineKey
        link.eventKey = eventKey
        link.key = DeadlineEventLink.key(deadlineKey: deadlineKey, eventKey: eventKey)
    }

    // MARK: Preparation links

    func allLinks() -> [DeadlineEventLink] {
        (try? context.fetch(FetchDescriptor<DeadlineEventLink>(sortBy: [SortDescriptor(\.start)]))) ?? []
    }

    func links(forDeadline key: String) -> [DeadlineEventLink] {
        allLinks().filter { $0.deadlineKey == key }
    }

    func linkCount(forDeadline key: String) -> Int { links(forDeadline: key).count }

    /// Links `event` (or, with `series`, its occurrences from this one until the deadline) to the deadline `key`.
    func link(_ event: CalendarEvent, toDeadline key: String, title: String, until: Date, series: Bool) {
        let eventKey = series ? seriesIdentifier(of: event.id) : event.id
        let linkKey = DeadlineEventLink.key(deadlineKey: key, eventKey: eventKey)
        var descriptor = FetchDescriptor<DeadlineEventLink>(predicate: #Predicate { $0.key == linkKey })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.start = min(existing.start, event.start)
            existing.deadlineTitle = title
            existing.until = until
        } else {
            context.insert(DeadlineEventLink(deadlineKey: key, eventKey: eventKey, isSeries: series, externalID: event.externalID,
                                             calendarID: event.calendarID, title: event.title, start: event.start,
                                             deadlineTitle: title, until: until))
        }
        try? context.save()
    }

    func unlink(key: String) {
        for link in allLinks() where link.key == key { context.delete(link) }
        try? context.save()
    }

    /// The events among `events` linked to the deadline `key`, ordered by start.
    func linkedEvents(forDeadline key: String, among events: [CalendarEvent]) -> [CalendarEvent] {
        let links = links(forDeadline: key)
        var seen = Set<String>()
        return events.filter { event in links.contains { $0.covers(event) } && seen.insert(event.id).inserted }
            .sorted { $0.start < $1.start }
    }

    /// The deadline `event` prepares for; the nearest one when it belongs to several.
    func preparationTarget(for event: CalendarEvent) -> PreparationTarget? {
        preparationTargets(for: [event])[event.id]
    }

    /// Event ID → the deadline it prepares for, for every linked event among `events` (one fetch).
    func preparationTargets(for events: [CalendarEvent]) -> [String: PreparationTarget] {
        let links = allLinks()
        guard !links.isEmpty else { return [:] }
        var result: [String: PreparationTarget] = [:]
        for event in events {
            guard let nearest = links.filter({ $0.covers(event) }).min(by: { $0.until < $1.until }) else { continue }
            result[event.id] = PreparationTarget(deadlineKey: nearest.deadlineKey, title: nearest.deadlineTitle, until: nearest.until)
        }
        return result
    }

    /// The link that makes `event` part of the preparation for `deadlineKey` (for "Zuordnung lösen").
    func link(for event: CalendarEvent, deadlineKey: String) -> DeadlineEventLink? {
        links(forDeadline: deadlineKey).first { $0.covers(event) }
    }

    /// Keeps title and moment of a deadline current on its links (P1 due dates and event times can change).
    func refreshDeadline(key: String, title: String, until: Date) {
        var changed = false
        for link in links(forDeadline: key) where link.deadlineTitle != title || link.until != until {
            link.deadlineTitle = title
            link.until = until
            changed = true
        }
        if changed { try? context.save() }
    }

    // MARK: Keyword suggestions (DL3)

    func dismissSuggestion(_ event: CalendarEvent) {
        let key = event.id
        var descriptor = FetchDescriptor<DeadlineSuggestionDismissal>(predicate: #Predicate { $0.eventKey == key })
        descriptor.fetchLimit = 1
        if (try? context.fetch(descriptor).first) == nil {
            context.insert(DeadlineSuggestionDismissal(eventKey: key, start: event.start))
            try? context.save()
        }
    }

    func dismissedSuggestionIDs() -> Set<String> {
        Set(((try? context.fetch(FetchDescriptor<DeadlineSuggestionDismissal>())) ?? []).map(\.eventKey))
    }

    // MARK: Pruning

    /// Deletes marks, links and dismissals whose date lies more than 30 days back (decision 9).
    func prune(now: Date) {
        let limit = now.addingTimeInterval(-TimeInterval(Self.retentionDays * 86_400))
        var changed = false
        for record in marks() where record.lastDate < limit {
            context.delete(record)
            changed = true
        }
        for link in allLinks() where max(link.start, link.until) < limit {
            context.delete(link)
            changed = true
        }
        for dismissal in (try? context.fetch(FetchDescriptor<DeadlineSuggestionDismissal>())) ?? [] where dismissal.start < limit {
            context.delete(dismissal)
            changed = true
        }
        if changed { try? context.save() }
    }
}
