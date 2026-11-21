import Foundation
import RemindersKit
import TagwerkCore

/// Travel time before events with a place (#168): the trips of a day, their cached times and the background lookup.
extension PlanningModel {
    /// The trips of `day` for the events given; empty while the setting is off or no time service exists.
    func travelLegs(for day: PlanDay, events: [CalendarEvent]) -> [TravelLeg] {
        guard settings.travelTimeEnabled, travelTimes != nil else { return [] }
        return TravelRules.legs(events: events, on: day, home: settings.homePlace, calendar: calendar,
                                choices: travelChoices(for: events), includesReturn: settings.travelShowsReturn)
    }

    /// The travel blocks of `day`. Manual times (F2) come first and need neither the network nor the cache; the others
    /// come from the times already in the cache (any age) and, for trips that could not be asked because the device
    /// is offline, from provisional estimates. A trip without any of them has no block yet; it appears after
    /// `refreshTravelTimes()`. Empty while the setting "Fahrzeit berücksichtigen" is off.
    func travelSegments(for day: PlanDay, events: [CalendarEvent]) -> [TravelSegment] {
        guard settings.travelTimeEnabled else { return [] }
        let choices = travelChoices(for: events)
        let overrides = choices.compactMapValues { $0.mode == .automatic ? nil : $0.mode }
        let legs = TravelRules.legs(events: events, on: day, home: settings.homePlace, calendar: calendar, choices: choices,
                                    includesReturn: settings.travelShowsReturn)
        var resolved = ResolvedTravelTimes()
        if let travelTimes {
            resolved = travelTimes.resolvedTimes(for: legs.filter { overrides[$0.eventID] == nil }, transport: settings.travelTransport)
        }
        guard !resolved.minutes.isEmpty || !resolved.provisionalMinutes.isEmpty || !overrides.isEmpty else { return [] }
        return TravelRules.segments(legs: legs, minutes: resolved.minutes, provisionalMinutes: resolved.provisionalMinutes,
                                    overrides: overrides, events: events, on: day, calendar: calendar)
    }

    /// Looks up the missing or old travel times of the shown days and reloads once when the plan changed because of it
    /// (a new value, a trip that turned provisional). A second call finds nothing to do and returns `false`, so there is
    /// no loop. Trips with a manual time are not asked.
    @discardableResult
    func refreshTravelTimes() async -> Bool {
        // The month does not show travel time; looking up a whole month would only cost requests.
        guard let travelTimes, settings.travelTimeEnabled, scope != .month else { return false }
        let legs = days.flatMap { plan -> [TravelLeg] in
            let events = plan.events + plan.blocks
            let overrides = travelOverrideModes(for: events)
            return travelLegs(for: plan.day, events: events).filter { overrides[$0.eventID] == nil }
        }
        guard !legs.isEmpty else { return false }
        guard await travelTimes.fetchMissing(legs: legs, transport: settings.travelTransport, home: settings.homePlace) else { return false }
        await reload()
        return true
    }

    // MARK: Manual travel time (F2)

    /// The identifier shared by all occurrences of a series; the event's own ID for an event that does not repeat.
    private func travelSeriesID(of event: CalendarEvent) -> String {
        event.isRecurring ? CalendarBlockRules.parseOccurrenceID(event.id).0 : event.id
    }

    /// What the user decided for this event: mode, transport and start; the default without a decision.
    func travelChoice(for event: CalendarEvent) -> TravelChoice {
        TravelOverrideRules.choice(eventID: event.id, seriesID: travelSeriesID(of: event), start: event.start,
                                   overrides: TravelOverrideStore(context: marks.modelContext).all())
    }

    /// What the user decided for the travel time of this event; `automatic` without a decision.
    func travelOverrideMode(for event: CalendarEvent) -> TravelOverrideMode {
        travelChoice(for: event).mode
    }

    /// The decisions for these events by event ID; events without any decision (the default) are left out.
    func travelChoices(for events: [CalendarEvent]) -> [String: TravelChoice] {
        let stored = TravelOverrideStore(context: marks.modelContext).all()
        guard !stored.isEmpty else { return [:] }
        var result: [String: TravelChoice] = [:]
        for event in events where result[event.id] == nil {
            let choice = TravelOverrideRules.choice(eventID: event.id, seriesID: travelSeriesID(of: event), start: event.start,
                                                    overrides: stored)
            if !choice.isDefault { result[event.id] = choice }
        }
        return result
    }

    /// The modes decided for these events by event ID; events without a decision (`automatic`) are left out.
    func travelOverrideModes(for events: [CalendarEvent]) -> [String: TravelOverrideMode] {
        travelChoices(for: events).compactMapValues { $0.mode == .automatic ? nil : $0.mode }
    }

    /// Sets the travel time of an event by hand; `series` applies to this and all following occurrences of a repeating event.
    func setTravelOverride(_ mode: TravelOverrideMode, for event: CalendarEvent, series: Bool) async {
        TravelOverrideStore(context: marks.modelContext).set(mode, eventID: event.id, seriesID: travelSeriesID(of: event),
                                                             start: event.start, series: series && event.isRecurring)
        await reload()
    }

    // MARK: Route (PL11b)

    /// The two ends of the trip a segment stands for: for the way there the origin (home or the previous event) and the
    /// event's place, for the way home the event's place and home. `nil` when an end is unknown (no home address, no place).
    func travelPlaces(of segment: TravelSegment, event: CalendarEvent) -> (from: TravelPlace, to: TravelPlace)? {
        func place(of event: CalendarEvent) -> TravelPlace? {
            event.location.map { TravelPlace(text: $0, latitude: event.latitude, longitude: event.longitude) }
        }
        guard let eventPlace = place(of: event) else { return nil }
        if segment.direction == .returnHome {
            return settings.homePlace.map { (eventPlace, $0) }
        }
        switch segment.origin {
        case .home:
            return settings.homePlace.map { ($0, eventPlace) }
        case .previousEvent(let id):
            let previous = days.lazy.flatMap { $0.events + $0.blocks }.first { $0.id == id }
            return previous.flatMap(place(of:)).map { ($0, eventPlace) }
        }
    }
}
