import Foundation
import SwiftData
import TagwerkCore

/// The travel time of one occurrence of an event, or of a series from one occurrence on, set by hand in Tagwerk (F2):
/// "Automatisch" (the explicit default, so "only this one" can beat a series), "Keine" or a fixed number of minutes.
/// It wins over the automatic value, works without network and never changes the calendar.
/// Schema rule: later attributes must be optional or have a default value.
@Model
final class EventTravelOverride {
    @Attribute(.unique) var key: String
    /// Occurrence ID, or the series identifier when `seriesFrom` is set.
    var eventKey: String
    var seriesFrom: Date?
    /// `TravelOverrideMode.storedName`.
    var modeName: String
    /// Only for the mode "fixed".
    var minutes: Int
    /// `TravelTransport` raw value chosen for this event; `nil` uses the setting.
    var transportRaw: String? = nil
    /// `TravelStart` raw value; `nil` applies the rule.
    var startRaw: String? = nil

    init(_ value: TravelOverride) {
        key = value.key
        eventKey = value.eventKey
        seriesFrom = value.seriesFrom
        modeName = value.mode.storedName
        minutes = value.mode.storedMinutes
        transportRaw = value.transport?.rawValue
        startRaw = value.start?.rawValue
    }

    var asOverride: TravelOverride {
        // An unknown raw value (a later version) reads as "not chosen", so a newer file never breaks the plan.
        TravelOverride(eventKey: eventKey, seriesFrom: seriesFrom, mode: TravelOverrideMode(storedName: modeName, minutes: minutes),
                       transport: transportRaw.flatMap(TravelTransport.init(rawValue:)),
                       start: startRaw.flatMap(TravelStart.init(rawValue:)))
    }
}

/// Reads and writes the manual travel times; the rules live in `TravelOverrideRules`.
@MainActor
final class TravelOverrideStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func all() -> [TravelOverride] {
        records().map(\.asOverride)
    }

    /// Sets the mode for one occurrence, or (`series`) for the series from this occurrence on; see
    /// `TravelOverrideRules.updated` for what stays and what goes.
    func set(_ mode: TravelOverrideMode, eventID: String, seriesID: String, start: Date, series: Bool) {
        set(TravelChoice(mode: mode), eventID: eventID, seriesID: seriesID, start: start, series: series)
    }

    /// Sets the decision (mode, transport, start) for one occurrence or the series from it on.
    func set(_ choice: TravelChoice, eventID: String, seriesID: String, start: Date, series: Bool) {
        let stored = records()
        let updated = TravelOverrideRules.updated(stored.map(\.asOverride), eventID: eventID, seriesID: seriesID, start: start,
                                                  choice: choice, series: series)
        let wanted = Dictionary(updated.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
        var present = Set<String>()
        for record in stored {
            if let value = wanted[record.key], present.insert(record.key).inserted {
                record.modeName = value.mode.storedName
                record.minutes = value.mode.storedMinutes
                record.transportRaw = value.transport?.rawValue
                record.startRaw = value.start?.rawValue
            } else {
                context.delete(record)
            }
        }
        for (key, value) in wanted where !present.contains(key) { context.insert(EventTravelOverride(value)) }
        try? context.save()
    }

    private func records() -> [EventTravelOverride] {
        (try? context.fetch(FetchDescriptor<EventTravelOverride>())) ?? []
    }
}
