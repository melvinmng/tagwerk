import Foundation

/// How the way to an event is travelled.
public enum TravelTransport: String, Sendable, CaseIterable, Codable {
    case automobile, transit, walking, cycling
}

/// A place for a trip: the text as typed, with coordinates when the calendar app resolved the address.
public struct TravelPlace: Sendable, Hashable, Codable {
    /// As typed in the event or in the settings.
    public var text: String
    /// From the event's structured location, if any.
    public var latitude: Double?
    public var longitude: Double?
    /// Stable key for the cache: rounded coordinates when known, else the normalised text.
    public var key: String

    public init(text: String, latitude: Double? = nil, longitude: Double? = nil) {
        self.text = text
        self.latitude = latitude
        self.longitude = longitude
        if let latitude, let longitude {
            // Four decimals are about 11 m: the same building from two calendars gets one key.
            self.key = String(format: "geo:%.4f,%.4f", latitude, longitude)
        } else {
            self.key = "text:" + Self.normalised(text)
        }
    }

    /// Lower case, without accents, whitespace collapsed.
    static func normalised(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// One trip to an event: where from, where to, and when to arrive.
public struct TravelLeg: Sendable, Hashable {
    public enum Origin: Sendable, Hashable {
        case previousEvent(id: String)
        case home
    }

    public var eventID: String
    public var origin: Origin
    public var from: TravelPlace
    public var to: TravelPlace
    /// The start of the event.
    public var arrival: Date

    public init(eventID: String, origin: Origin, from: TravelPlace, to: TravelPlace, arrival: Date) {
        self.eventID = eventID
        self.origin = origin
        self.from = from
        self.to = to
        self.arrival = arrival
    }
}

/// The travel time before an event as a block of the day.
public struct TravelSegment: Sendable, Hashable, Identifiable {
    /// Where the minutes come from.
    public enum Source: Sendable, Hashable {
        /// Apple Maps (or its last stored answer).
        case automatic
        /// An estimate while no value can be fetched (no network): the last known time to the same place, else 30 minutes.
        case provisional
        /// Set by hand for this event.
        case manual
    }

    public var id: String { eventID }
    public var eventID: String
    /// Minutes of the day, ending at the start of the event.
    public var range: Range<Int>
    public var minutes: Int
    public var origin: TravelLeg.Origin
    /// The trip starts before the previous event ends.
    public var isTight: Bool
    public var source: Source

    public init(eventID: String, range: Range<Int>, minutes: Int, origin: TravelLeg.Origin, isTight: Bool,
                source: Source = .automatic) {
        self.eventID = eventID
        self.range = range
        self.minutes = minutes
        self.origin = origin
        self.isTight = isTight
        self.source = source
    }
}

/// Rules for the travel time before events with a place. Which trips exist is decided here; how long they take
/// comes from outside (Apple Maps) and arrives as `minutes`.
public enum TravelRules {
    /// A longer gap between two events means the trip starts at home.
    public static let homeGapMinutes = 180

    /// Words that name an online meeting. Whole words only, so "Teamsitzung" is not "Teams".
    private static let onlineWords: Set<String> = ["zoom", "teams", "webex", "online", "facetime"]

    /// A place someone can travel to: not empty, no web address, no online meeting.
    public static func isPhysicalLocation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        if lower.contains("://") || lower.hasPrefix("www.") { return false }
        let words = lower.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if words.contains(where: onlineWords.contains) { return false }
        for index in words.indices.dropLast() where words[index] == "google" && words[index + 1] == "meet" { return false }
        return true
    }

    /// The trips of `day`: for every busy, timed event with a physical place, from the previous such event of the
    /// day that has ended by then, or from home when there is none or the gap is longer than `homeGapMinutes`.
    /// No trip without a starting point, and none between two equal places.
    public static func legs(events: [CalendarEvent], on day: PlanDay, home: TravelPlace?, calendar: Calendar) -> [TravelLeg] {
        let dayStart = day.startDate(in: calendar)
        let dayEnd = day.adding(days: 1, calendar: calendar).startDate(in: calendar)
        let places: [(event: CalendarEvent, place: TravelPlace)] = events
            .filter { !$0.isAllDay && $0.isBusy && $0.start >= dayStart && $0.start < dayEnd }
            .compactMap { event in
                guard let text = event.location, isPhysicalLocation(text) else { return nil }
                return (event, TravelPlace(text: text, latitude: event.latitude, longitude: event.longitude))
            }
            .sorted { $0.event.start != $1.event.start ? $0.event.start < $1.event.start : $0.event.id < $1.event.id }

        var result: [TravelLeg] = []
        for (index, current) in places.enumerated() {
            let earlier = places[..<index].filter { $0.event.end <= current.event.start }
            let previous = earlier.max { $0.event.end != $1.event.end ? $0.event.end < $1.event.end : $0.event.start < $1.event.start }
            let origin: TravelLeg.Origin
            let from: TravelPlace
            if let previous, current.event.start.timeIntervalSince(previous.event.end) <= TimeInterval(homeGapMinutes * 60) {
                origin = .previousEvent(id: previous.event.id)
                from = previous.place
            } else if let home {
                origin = .home
                from = home
            } else {
                continue
            }
            guard from.key != current.place.key else { continue }
            result.append(TravelLeg(eventID: current.event.id, origin: origin, from: from, to: current.place,
                                    arrival: current.event.start))
        }
        return result
    }

    /// Time assumed for a trip that cannot be looked up and has no earlier value to the same place.
    public static let defaultProvisionalMinutes = 30

    /// The estimate for a trip without a value: the last known time to the same destination (from any starting point),
    /// else `defaultProvisionalMinutes`. A time of 0 ("under 3 minutes", possibly from a nearby starting point) or one
    /// above `TravelPlausibility.maximumTravelMinutes` says nothing about this trip.
    public static func provisionalMinutes(lastKnownToDestination: Int?) -> Int {
        guard let known = lastKnownToDestination, known > 0, TravelPlausibility.isPlausibleTravelTime(minutes: known) else {
            return defaultProvisionalMinutes
        }
        return known
    }

    /// The travel blocks of `day`: `(start − minutes)..<start`, cut at midnight, in the order of the events.
    ///
    /// Per event, in this order:
    /// 1. An override decides first: `none` gives no block, `fixed` a block of that length (also without a trip, for an
    ///    event without a place or without a home address).
    /// 2. Otherwise the time in `minutes` (Apple Maps, event ID → minutes).
    /// 3. Otherwise the estimate in `provisionalMinutes` (the trip could not be looked up, no network).
    /// 4. Otherwise no block.
    ///
    /// A time of 0, or longer than `TravelPlausibility.maximumTravelMinutes`, gives no block, except a manual one, which
    /// is bounded to that maximum instead.
    public static func segments(legs: [TravelLeg], minutes: [String: Int], provisionalMinutes: [String: Int] = [:],
                                overrides: [String: TravelOverrideMode] = [:], events: [CalendarEvent],
                                on day: PlanDay, calendar: Calendar) -> [TravelSegment] {
        let dayStart = day.startDate(in: calendar)
        let dayEnd = day.adding(days: 1, calendar: calendar).startDate(in: calendar)
        let byID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        func segment(eventID: String, arrival: Date, travel: Int, origin: TravelLeg.Origin, source: TravelSegment.Source) -> TravelSegment? {
            let start = Int(arrival.timeIntervalSince(dayStart) / 60)
            let from = max(0, start - travel)
            guard from < start else { return nil }
            var isTight = false
            if case .previousEvent(let id) = origin, let previous = byID[id] {
                isTight = Int(previous.end.timeIntervalSince(dayStart) / 60) > from
            }
            return TravelSegment(eventID: eventID, range: from..<start, minutes: start - from, origin: origin, isTight: isTight, source: source)
        }

        var result: [TravelSegment] = []
        var handled = Set<String>()
        for leg in legs where handled.insert(leg.eventID).inserted {
            let travel: Int
            let source: TravelSegment.Source
            switch overrides[leg.eventID] ?? .automatic {
            case .none:
                continue
            case .fixed(let fixed):
                travel = TravelOverrideRules.clampedFixedMinutes(fixed)
                source = .manual
            case .automatic:
                if let known = minutes[leg.eventID] {
                    travel = known
                    source = .automatic
                } else if let estimate = provisionalMinutes[leg.eventID] {
                    travel = estimate
                    source = .provisional
                } else {
                    continue
                }
                guard travel > 0, TravelPlausibility.isPlausibleTravelTime(minutes: travel) else { continue }
            }
            if let found = segment(eventID: leg.eventID, arrival: leg.arrival, travel: travel, origin: leg.origin, source: source) {
                result.append(found)
            }
        }

        // A manual time needs no trip: events without a place, online events and events without a home address.
        let places = events.filter { event in
            !event.isAllDay && event.isBusy && event.start >= dayStart && event.start < dayEnd
                && event.location.map(isPhysicalLocation) == true
        }
        for event in events where !event.isAllDay && event.isBusy && event.start >= dayStart && event.start < dayEnd {
            guard case .fixed(let fixed)? = overrides[event.id], handled.insert(event.id).inserted else { continue }
            let earlier = places.filter { $0.id != event.id && $0.end <= event.start }
            let previous = earlier.max { $0.end != $1.end ? $0.end < $1.end : $0.start < $1.start }
            let origin: TravelLeg.Origin
            if let previous, event.start.timeIntervalSince(previous.end) <= TimeInterval(homeGapMinutes * 60) {
                origin = .previousEvent(id: previous.id)
            } else {
                origin = .home
            }
            if let found = segment(eventID: event.id, arrival: event.start, travel: TravelOverrideRules.clampedFixedMinutes(fixed),
                                   origin: origin, source: .manual) {
                result.append(found)
            }
        }
        return result.sorted { $0.range.upperBound != $1.range.upperBound ? $0.range.upperBound < $1.range.upperBound : $0.eventID < $1.eventID }
    }

    /// Rounds an estimated travel time up to 5 minutes; 0 when under 3 minutes.
    public static func roundedMinutes(seconds: Double) -> Int {
        guard seconds >= 180 else { return 0 }
        return Int((seconds / 300).rounded(.up)) * 5
    }
}
