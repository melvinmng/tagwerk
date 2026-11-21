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

/// One trip of a day: to an event, or from an event back home.
public struct TravelLeg: Sendable, Hashable, Identifiable {
    public enum Origin: Sendable, Hashable {
        case previousEvent(id: String)
        case home
    }

    public enum Direction: Sendable, Hashable { case toEvent, returnHome }

    public var eventID: String
    public var direction: Direction
    /// Where the trip starts. For the way home: the event itself.
    public var origin: Origin
    public var from: TravelPlace
    public var to: TravelPlace
    /// Transport chosen for this event; `nil` uses the setting.
    public var transport: TravelTransport?
    /// `toEvent`: the start of the event. `returnHome`: the end of the event, when the trip starts.
    public var arrival: Date

    /// Unique per trip: the way home of an event has its own ID, so both fit into one dictionary.
    public var id: String { direction == .toEvent ? eventID : eventID + TravelSegment.returnSuffix }

    public init(eventID: String, origin: Origin, from: TravelPlace, to: TravelPlace, arrival: Date,
                direction: Direction = .toEvent, transport: TravelTransport? = nil) {
        self.eventID = eventID
        self.direction = direction
        self.origin = origin
        self.from = from
        self.to = to
        self.transport = transport
        self.arrival = arrival
    }
}

/// The travel time before an event, or after it on the way home, as a block of the day.
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

    /// Appended to the event ID for the way home.
    public static let returnSuffix = "#return"

    public var id: String { direction == .toEvent ? eventID : eventID + Self.returnSuffix }
    /// The event the trip leads to, or leaves from (`returnHome`).
    public var eventID: String
    public var direction: TravelLeg.Direction
    /// Minutes of the day: `toEvent` ends at the start of the event, `returnHome` begins at its end.
    public var range: Range<Int>
    public var minutes: Int
    public var origin: TravelLeg.Origin
    /// Transport chosen for this event; `nil` uses the setting.
    public var transport: TravelTransport?
    /// Minutes the trip starts before the previous event ends; 0 when it does not.
    public var overlapMinutes: Int
    public var source: Source

    /// The trip starts before the previous event ends.
    public var isTight: Bool { overlapMinutes > 0 }

    public init(eventID: String, range: Range<Int>, minutes: Int, origin: TravelLeg.Origin, overlapMinutes: Int = 0,
                source: Source = .automatic, direction: TravelLeg.Direction = .toEvent, transport: TravelTransport? = nil) {
        self.eventID = eventID
        self.direction = direction
        self.range = range
        self.minutes = minutes
        self.origin = origin
        self.transport = transport
        self.overlapMinutes = overlapMinutes
        self.source = source
    }
}

/// Rules for the travel time before events with a place. Which trips exist is decided here; how long they take
/// comes from outside (Apple Maps) and arrives as `minutes`.
public enum TravelRules {
    /// A longer gap between two events means the trip starts at home.
    public static let homeGapMinutes = 180

    /// Meeting services that name an online meeting. Whole words only, so "Teamsitzung" is not "Teams".
    private static let onlineServiceWords: Set<String> = ["zoom", "teams", "webex", "facetime", "skype", "jitsi"]

    /// Texts that are online only when they are the whole location. As a part of a name they say nothing:
    /// "Online Business Center" or "Online-Shop GmbH, Hauptstr. 1" are places.
    private static let onlineOnlyTexts: Set<String> = ["online", "online-meeting", "online meeting", "virtuell", "virtual"]

    /// A place someone can travel to: not empty, and not recognisably online. Online is a web address (also without a scheme), a known meeting
    /// service as a whole word, or a location that consists only of "online" / "virtuell" (see `onlineOnlyTexts`).
    public static func isPhysicalLocation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        if lower.contains("://") || onlineOnlyTexts.contains(lower) { return false }
        // A web address without a scheme: "www.example.com", "meet.example.com/room" (a dotted host with letters at the end,
        // followed by a slash). "Hauptstr. 1" and "Raum 2.14" are no addresses.
        let tokens = lower.split(whereSeparator: \.isWhitespace)
        if tokens.contains(where: { $0.hasPrefix("www.") || $0.range(of: #"^[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}(:\d+)?/"#, options: .regularExpression) != nil }) {
            return false
        }
        let words = lower.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if words.contains(where: onlineServiceWords.contains) { return false }
        for index in words.indices.dropLast() where words[index] == "google" && words[index + 1] == "meet" { return false }
        return true
    }

    /// The trips of `day`: for every busy, timed event with a physical place, from the previous such event of the
    /// day that has ended by then, or from home when there is none or the gap is longer than `homeGapMinutes`.
    /// No trip without a starting point, and none between two equal places.
    ///
    /// `choices` (by event ID) set the transport and the start per event: `home` starts at home even right after
    /// another event, `previousEvent` starts at the last event that has ended whatever the gap is (without one the rule
    /// applies). An event with the mode `none` has no trip at all. With `includesReturn` (and a home address) the way
    /// home follows the last event of the day and every event that no other follows within `homeGapMinutes`.
    public static func legs(events: [CalendarEvent], on day: PlanDay, home: TravelPlace?, calendar: Calendar,
                            choices: [String: TravelChoice] = [:], includesReturn: Bool = false) -> [TravelLeg] {
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
            let choice = choices[current.event.id] ?? TravelChoice()
            if choice.mode == .none { continue }
            let earlier = places[..<index].filter { $0.event.end <= current.event.start }
            let previous = earlier.max { $0.event.end != $1.event.end ? $0.event.end < $1.event.end : $0.event.start < $1.event.start }
            let origin: TravelLeg.Origin
            let from: TravelPlace
            let startsAtPrevious: Bool
            switch choice.start {
            case .home: startsAtPrevious = false
            case .previousEvent: startsAtPrevious = previous != nil
            case nil:
                startsAtPrevious = previous.map {
                    current.event.start.timeIntervalSince($0.event.end) <= TimeInterval(homeGapMinutes * 60)
                } ?? false
            }
            if startsAtPrevious, let previous {
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
                                    arrival: current.event.start, transport: choice.transport))
        }

        if includesReturn, let home {
            for (index, current) in places.enumerated() {
                let choice = choices[current.event.id] ?? TravelChoice()
                guard choice.mode != .none, current.place.key != home.key else { continue }
                let others = places.enumerated().filter { $0.offset != index }.map(\.element)
                // Another event is still running when this one ends: the way home starts after that one.
                let stillBusy = others.contains { other in
                    other.event.start < current.event.end
                        && (other.event.end > current.event.end
                            || (other.event.end == current.event.end && other.event.id > current.event.id))
                }
                guard !stillBusy else { continue }
                let next = others.filter { $0.event.start >= current.event.end }.min { $0.event.start < $1.event.start }
                if let next, next.event.start.timeIntervalSince(current.event.end) <= TimeInterval(homeGapMinutes * 60) { continue }
                result.append(TravelLeg(eventID: current.event.id, origin: .previousEvent(id: current.event.id),
                                        from: current.place, to: home, arrival: current.event.end,
                                        direction: .returnHome, transport: choice.transport))
            }
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

    /// The travel blocks of `day`: `(start − minutes)..<start`, cut at midnight, in the order of the events; the way
    /// home (`returnHome`) runs `end..<(end + minutes)` from the end of the event, cut at midnight.
    ///
    /// Per trip, in this order:
    /// 1. An override decides first: `none` gives no block, `fixed` a block of that length (also without a trip, for an
    ///    event without a place or without a home address). The way home uses the same fixed length.
    /// 2. Otherwise the time in `minutes` (Apple Maps, trip ID → minutes; the way home has the ID `<event ID>#return`).
    /// 3. Otherwise the estimate in `provisionalMinutes` (the trip could not be looked up, no network).
    /// 4. Otherwise no block.
    ///
    /// A time of 0, or longer than `TravelPlausibility.maximumTravelMinutes`, gives no block, except a manual one, which
    /// is bounded to that maximum instead. `overlapMinutes` is how long before the previous event ends the trip starts.
    public static func segments(legs: [TravelLeg], minutes: [String: Int], provisionalMinutes: [String: Int] = [:],
                                overrides: [String: TravelOverrideMode] = [:], events: [CalendarEvent],
                                on day: PlanDay, calendar: Calendar) -> [TravelSegment] {
        let dayStart = day.startDate(in: calendar)
        let dayEnd = day.adding(days: 1, calendar: calendar).startDate(in: calendar)
        let byID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        func segment(eventID: String, time: Date, travel: Int, origin: TravelLeg.Origin, source: TravelSegment.Source,
                     direction: TravelLeg.Direction = .toEvent, transport: TravelTransport? = nil) -> TravelSegment? {
            let minute = Int(time.timeIntervalSince(dayStart) / 60)
            switch direction {
            case .toEvent:
                let from = max(0, minute - travel)
                guard from < minute else { return nil }
                var overlap = 0
                if case .previousEvent(let id) = origin, let previous = byID[id] {
                    overlap = max(0, Int(previous.end.timeIntervalSince(dayStart) / 60) - from)
                }
                return TravelSegment(eventID: eventID, range: from..<minute, minutes: minute - from, origin: origin,
                                     overlapMinutes: overlap, source: source, transport: transport)
            case .returnHome:
                let until = min(24 * 60, minute + travel)
                guard minute >= 0, minute < until else { return nil }
                return TravelSegment(eventID: eventID, range: minute..<until, minutes: until - minute, origin: origin,
                                     source: source, direction: .returnHome, transport: transport)
            }
        }

        var result: [TravelSegment] = []
        var handled = Set<String>()
        for leg in legs where handled.insert(leg.id).inserted {
            let travel: Int
            let source: TravelSegment.Source
            switch overrides[leg.eventID] ?? .automatic {
            case .none:
                continue
            case .fixed(let fixed):
                travel = TravelOverrideRules.clampedFixedMinutes(fixed)
                source = .manual
            case .automatic:
                if let known = minutes[leg.id] {
                    travel = known
                    source = .automatic
                } else if let estimate = provisionalMinutes[leg.id] {
                    travel = estimate
                    source = .provisional
                } else {
                    continue
                }
                guard travel > 0, TravelPlausibility.isPlausibleTravelTime(minutes: travel) else { continue }
            }
            if let found = segment(eventID: leg.eventID, time: leg.arrival, travel: travel, origin: leg.origin, source: source,
                                   direction: leg.direction, transport: leg.transport) {
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
            if let found = segment(eventID: event.id, time: event.start, travel: TravelOverrideRules.clampedFixedMinutes(fixed),
                                   origin: origin, source: .manual) {
                result.append(found)
            }
        }
        return result.sorted { $0.range.upperBound != $1.range.upperBound ? $0.range.upperBound < $1.range.upperBound : $0.id < $1.id }
    }

    /// Rounds an estimated travel time up to 5 minutes; 0 when under 3 minutes.
    public static func roundedMinutes(seconds: Double) -> Int {
        guard seconds >= 180 else { return 0 }
        return Int((seconds / 300).rounded(.up)) * 5
    }
}
