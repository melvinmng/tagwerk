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

/// A decision for one occurrence of an event, or for a series from one occurrence on.
public struct TravelOverride: Hashable, Sendable {
    /// The occurrence ID, or the series identifier when `seriesFrom` is set.
    public var eventKey: String
    /// Set for "this and all following": the start of the occurrence it was made on.
    public var seriesFrom: Date?
    public var mode: TravelOverrideMode

    public init(eventKey: String, seriesFrom: Date?, mode: TravelOverrideMode) {
        self.eventKey = eventKey
        self.seriesFrom = seriesFrom
        self.mode = mode
    }

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

    /// The override that applies to an occurrence: its own first, then the series override with the latest start that
    /// is not after the occurrence, otherwise `automatic`. `seriesID` is the identifier shared by all occurrences
    /// (the event's own ID for an event that does not repeat).
    public static func mode(eventID: String, seriesID: String, start: Date, overrides: [TravelOverride]) -> TravelOverrideMode {
        if let own = overrides.first(where: { $0.seriesFrom == nil && $0.eventKey == eventID }) { return own.mode }
        return overrides
            .compactMap { override -> (Date, TravelOverrideMode)? in
                guard let from = override.seriesFrom, override.eventKey == seriesID, from <= start else { return nil }
                return (from, override.mode)
            }
            .max { $0.0 < $1.0 }?.1 ?? .automatic
    }

    /// The overrides after the user set `mode` for an occurrence (`series: false`) or for the series from this
    /// occurrence on (`series: true`). An entry of the same key is replaced. `automatic` leaves no entry behind unless
    /// another override would still apply, so "only this one: automatic" can beat a series override. Overrides of
    /// later occurrences stay as they are, like the other marks on calendar events.
    public static func updated(_ overrides: [TravelOverride], eventID: String, seriesID: String, start: Date,
                               mode: TravelOverrideMode, series: Bool) -> [TravelOverride] {
        let entry = TravelOverride(eventKey: series ? seriesID : eventID, seriesFrom: series ? start : nil,
                                   mode: normalised(mode))
        var result = overrides.filter { $0.key != entry.key }
        if entry.mode == .automatic,
           Self.mode(eventID: eventID, seriesID: seriesID, start: start, overrides: result) == .automatic {
            return result
        }
        result.append(entry)
        return result
    }

    private static func normalised(_ mode: TravelOverrideMode) -> TravelOverrideMode {
        if case .fixed(let minutes) = mode { return .fixed(minutes: clampedFixedMinutes(minutes)) }
        return mode
    }
}
