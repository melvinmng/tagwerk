import Foundation

/// What the user decided for the travel time before an event: leave it to the app, switch it off or set it by hand.
public enum TravelOverrideMode: Hashable, Sendable {
    /// Apple Maps decides (the default); an explicit value so that "only this one: automatic" can beat a series override.
    case automatic
    /// No travel block.
    case none
    /// A fixed duration in minutes, in 5-minute steps (see `TravelOverrideRules.clampedFixedMinutes`).
    case fixed(minutes: Int)

    /// Name in the database and in backups.
    public var storedName: String {
        switch self {
        case .automatic: "automatic"
        case .none: "none"
        case .fixed: "fixed"
        }
    }

    /// The minutes in the database; 0 unless the mode is `fixed`.
    public var storedMinutes: Int {
        if case .fixed(let minutes) = self { return minutes }
        return 0
    }

    /// Reads a stored value. An unknown name reads as `automatic`, so a backup of a later version never breaks the plan.
    public init(storedName: String, minutes: Int) {
        switch storedName {
        case "none": self = .none
        case "fixed": self = .fixed(minutes: TravelOverrideRules.clampedFixedMinutes(minutes))
        default: self = .automatic
        }
    }
}

/// Where the trip to an event starts, when the user decided it by hand (PL14c).
public enum TravelStart: String, Sendable, Codable, CaseIterable {
    /// Always from home, also right after another event.
    case home
    /// From the last event with a place that has ended, whatever the gap is.
    case previousEvent
}

/// What the user chose for one event: the mode and, for the automatic mode, optionally the transport and the start.
public struct TravelChoice: Hashable, Sendable {
    public var mode: TravelOverrideMode
    /// `nil` uses the setting "Verkehrsmittel".
    public var transport: TravelTransport?
    /// `nil` applies the rule (previous event, or home after a gap of more than three hours).
    public var start: TravelStart?

    public init(mode: TravelOverrideMode = .automatic, transport: TravelTransport? = nil, start: TravelStart? = nil) {
        self.mode = mode
        self.transport = transport
        self.start = start
    }

    /// Nothing was chosen: the plan behaves as without an override.
    public var isDefault: Bool { mode == .automatic && transport == nil && start == nil }
}

/// A decision for one occurrence of an event, or for a series from one occurrence on.
public struct TravelOverride: Hashable, Sendable {
    /// The occurrence ID, or the series identifier when `seriesFrom` is set.
    public var eventKey: String
    /// Set for "this and all following": the start of the occurrence it was made on.
    public var seriesFrom: Date?
    public var mode: TravelOverrideMode
    public var transport: TravelTransport?
    public var start: TravelStart?

    public init(eventKey: String, seriesFrom: Date?, mode: TravelOverrideMode, transport: TravelTransport? = nil,
                start: TravelStart? = nil) {
        self.eventKey = eventKey
        self.seriesFrom = seriesFrom
        self.mode = mode
        self.transport = transport
        self.start = start
    }

    /// The decision this entry carries.
    public var choice: TravelChoice { TravelChoice(mode: mode, transport: transport, start: start) }

    /// Unique per occurrence or per series start; the same scheme as the other marks on calendar events.
    public var key: String {
        eventKey + (seriesFrom.map { "|from \(Int($0.timeIntervalSince1970))" } ?? "")
    }
}

/// Rules for the manual travel time (F2): which override applies to an event and how a change is stored.
public enum TravelOverrideRules {
    /// A fixed travel time is set in steps of this many minutes.
    public static let stepMinutes = 5
    public static let minimumFixedMinutes = 5
    /// As long as a computed trip may be (`TravelPlausibility.maximumTravelMinutes`), so a manual block is never longer.
    public static let maximumFixedMinutes = TravelPlausibility.maximumTravelMinutes

    /// The nearest multiple of 5 within 5…180.
    public static func clampedFixedMinutes(_ minutes: Int) -> Int {
        let stepped = Int((Double(minutes) / Double(stepMinutes)).rounded(.toNearestOrAwayFromZero)) * stepMinutes
        return min(maximumFixedMinutes, max(minimumFixedMinutes, stepped))
    }

    /// The decision that applies to an occurrence: its own entry first, then the series entry with the latest start that
    /// is not after the occurrence, otherwise the default. The entry counts as a whole: an own entry does not inherit
    /// the transport of the series. `seriesID` is the identifier shared by all occurrences (the event's own ID for an
    /// event that does not repeat).
    public static func choice(eventID: String, seriesID: String, start: Date, overrides: [TravelOverride]) -> TravelChoice {
        if let own = overrides.first(where: { $0.seriesFrom == nil && $0.eventKey == eventID }) { return own.choice }
        return overrides
            .compactMap { override -> (Date, TravelChoice)? in
                guard let from = override.seriesFrom, override.eventKey == seriesID, from <= start else { return nil }
                return (from, override.choice)
            }
            .max { $0.0 < $1.0 }?.1 ?? TravelChoice()
    }

    /// The mode of the decision that applies to an occurrence; `automatic` without one.
    public static func mode(eventID: String, seriesID: String, start: Date, overrides: [TravelOverride]) -> TravelOverrideMode {
        choice(eventID: eventID, seriesID: seriesID, start: start, overrides: overrides).mode
    }

    /// The overrides after the user decided `choice` for an occurrence (`series: false`) or for the series from this
    /// occurrence on (`series: true`). An entry of the same key is replaced. The default choice leaves no entry behind
    /// unless another override would still apply, so "only this one: default" can beat a series override. Overrides of
    /// later occurrences stay as they are, like the other marks on calendar events.
    public static func updated(_ overrides: [TravelOverride], eventID: String, seriesID: String, start: Date,
                               choice: TravelChoice, series: Bool) -> [TravelOverride] {
        let normalisedChoice = TravelChoice(mode: normalised(choice.mode), transport: choice.transport, start: choice.start)
        let entry = TravelOverride(eventKey: series ? seriesID : eventID, seriesFrom: series ? start : nil,
                                   mode: normalisedChoice.mode, transport: normalisedChoice.transport, start: normalisedChoice.start)
        var result = overrides.filter { $0.key != entry.key }
        if entry.choice.isDefault,
           Self.choice(eventID: eventID, seriesID: seriesID, start: start, overrides: result).isDefault {
            return result
        }
        result.append(entry)
        return result
    }

    /// Like `updated(…choice:…)` for a decision that only sets the mode.
    public static func updated(_ overrides: [TravelOverride], eventID: String, seriesID: String, start: Date,
                               mode: TravelOverrideMode, series: Bool) -> [TravelOverride] {
        updated(overrides, eventID: eventID, seriesID: seriesID, start: start, choice: TravelChoice(mode: mode), series: series)
    }

    private static func normalised(_ mode: TravelOverrideMode) -> TravelOverrideMode {
        if case .fixed(let minutes) = mode { return .fixed(minutes: clampedFixedMinutes(minutes)) }
        return mode
    }
}
