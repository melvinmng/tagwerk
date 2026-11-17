import Foundation
import RemindersKit
import SwiftData
import TagwerkCore

/// Lunch break that differs from the setting on one date (design §13.15 L1); 0 minutes = no break.
/// Schema rule: later attributes must be optional or have a default value.
@Model
final class DayLunchRecord {
    @Attribute(.unique) var dayKey: String
    var startMinutes: Int
    var minutes: Int

    init(day: PlanDay, startMinutes: Int, minutes: Int) {
        self.dayKey = DayOverrideRecord.key(day)
        self.startMinutes = startMinutes
        self.minutes = minutes
    }
}

/// "Frei" or "Belegt" set in Tagwerk for one occurrence or a series from a date on (design §13.15 F1);
/// it wins over the calendar's own availability and never changes the calendar.
@Model
final class EventAvailabilityMark {
    @Attribute(.unique) var key: String
    /// Occurrence ID, or the series identifier when `seriesFrom` is set.
    var eventKey: String
    var seriesFrom: Date?
    var isFree: Bool

    init(eventKey: String, seriesFrom: Date?, isFree: Bool) {
        self.key = eventKey + (seriesFrom.map { "|from \(Int($0.timeIntervalSince1970))" } ?? "")
        self.eventKey = eventKey
        self.seriesFrom = seriesFrom
        self.isFree = isFree
    }
}

/// Accepted merge of a placeholder event ("Busy" …) into a real one, or a rule "always for this title and
/// calendar"; dismissed suggestions are stored too (design §13.15 M1).
@Model
final class EventMergeDecision {
    @Attribute(.unique) var key: String
    var placeholderEventID: String?
    var ruleTitle: String?
    var ruleCalendarID: String?
    var isMerged: Bool

    init(key: String, placeholderEventID: String?, ruleTitle: String?, ruleCalendarID: String?, isMerged: Bool) {
        self.key = key
        self.placeholderEventID = placeholderEventID
        self.ruleTitle = ruleTitle
        self.ruleCalendarID = ruleCalendarID
        self.isMerged = isMerged
    }
}

/// One row of the calendar diagnostics (next 7 days).
struct CalendarDiagnostic: Identifiable, Equatable {
    var id: String { calendarID }
    let calendarID: String
    let title: String
    let kind: CalendarKind
    /// Tagwerk reads this calendar (selected, plan or deadline calendar).
    let isRead: Bool
    let isDeadlineCalendar: Bool
    let events: Int
    let shown: Int
    /// Identical events shown through a copy in another calendar.
    let hiddenByMerge: Int
    /// Placeholder events hidden by a "Zusammenfassen" decision.
    let hiddenByPlaceholderDecision: Int
    /// All-day events of deadline calendars, shown as deadlines.
    let shownAsDeadline: Int
}

/// Tagwerk's own marks on calendar events: lunch per day, availability and merge decisions.
@MainActor
final class EventMarkStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Lunch

    func lunch(on day: PlanDay) -> (startMinutes: Int, minutes: Int)? {
        lunchRecord(day).map { ($0.startMinutes, $0.minutes) }
    }

    func setLunch(startMinutes: Int, minutes: Int, on day: PlanDay) {
        if let record = lunchRecord(day) {
            record.startMinutes = startMinutes
            record.minutes = minutes
        } else {
            context.insert(DayLunchRecord(day: day, startMinutes: startMinutes, minutes: minutes))
        }
        try? context.save()
    }

    func clearLunch(on day: PlanDay) {
        if let record = lunchRecord(day) { context.delete(record) }
        try? context.save()
    }

    private func lunchRecord(_ day: PlanDay) -> DayLunchRecord? {
        let key = DayOverrideRecord.key(day)
        var descriptor = FetchDescriptor<DayLunchRecord>(predicate: #Predicate { $0.dayKey == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: Availability

    /// `nil` when Tagwerk has no mark for the event; an occurrence mark wins over a series mark.
    func isFree(_ event: CalendarEvent, marks: [EventAvailabilityMark]) -> Bool? {
        if let own = marks.first(where: { $0.seriesFrom == nil && $0.eventKey == event.id }) { return own.isFree }
        let series = CalendarBlockRules.parseOccurrenceID(event.id).0
        return marks.filter { $0.seriesFrom != nil && $0.eventKey == series && $0.seriesFrom! <= event.start }
            .max { $0.seriesFrom! < $1.seriesFrom! }?.isFree
    }

    func allMarks() -> [EventAvailabilityMark] {
        (try? context.fetch(FetchDescriptor<EventAvailabilityMark>())) ?? []
    }

    /// Marks one occurrence, or (`series`) the whole series from this occurrence on.
    func mark(_ event: CalendarEvent, isFree: Bool, series: Bool) {
        let eventKey = series ? CalendarBlockRules.parseOccurrenceID(event.id).0 : event.id
        let mark = EventAvailabilityMark(eventKey: eventKey, seriesFrom: series ? event.start : nil, isFree: isFree)
        let key = mark.key
        for old in (try? context.fetch(FetchDescriptor<EventAvailabilityMark>(predicate: #Predicate { $0.key == key }))) ?? [] {
            context.delete(old)
        }
        context.insert(mark)
        try? context.save()
    }

    // MARK: Merge decisions

    func mergeDecisions() -> [EventMergeDecision] {
        (try? context.fetch(FetchDescriptor<EventMergeDecision>())) ?? []
    }

    func decide(_ suggestion: MergeSuggestion, merge: Bool, always: Bool) {
        let decision = always
            ? EventMergeDecision(key: "rule:\(normalizedKey(suggestion.placeholderTitle))|\(suggestion.placeholderCalendarID)",
                                 placeholderEventID: nil, ruleTitle: normalizedKey(suggestion.placeholderTitle),
                                 ruleCalendarID: suggestion.placeholderCalendarID, isMerged: merge)
            : EventMergeDecision(key: "event:\(suggestion.placeholderID)", placeholderEventID: suggestion.placeholderID,
                                 ruleTitle: nil, ruleCalendarID: nil, isMerged: merge)
        let key = decision.key
        for old in (try? context.fetch(FetchDescriptor<EventMergeDecision>(predicate: #Predicate { $0.key == key }))) ?? [] {
            context.delete(old)
        }
        context.insert(decision)
        try? context.save()
    }

    /// "Künftig immer" rules and one-off merges, for the settings list.
    func deleteMergeDecision(key: String) {
        for decision in mergeDecisions() where decision.key == key { context.delete(decision) }
        try? context.save()
    }

    func clearMergeDecisions() {
        for decision in mergeDecisions() { context.delete(decision) }
        try? context.save()
    }

    /// `true` merged, `false` kept separate, `nil` undecided.
    func decision(for suggestion: MergeSuggestion, in decisions: [EventMergeDecision]) -> Bool? {
        if let own = decisions.first(where: { $0.placeholderEventID == suggestion.placeholderID }) { return own.isMerged }
        return decisions.first {
            $0.ruleTitle == normalizedKey(suggestion.placeholderTitle) && $0.ruleCalendarID == suggestion.placeholderCalendarID
        }?.isMerged
    }

    private func normalizedKey(_ title: String) -> String {
        title.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
