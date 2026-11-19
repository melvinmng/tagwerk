import Foundation
import TagwerkCore

/// Travel time before events with a place (#168): the trips of a day, their cached times and the background lookup.
extension PlanningModel {
    /// The trips of `day` for the events given; empty while the setting is off or no time service exists.
    func travelLegs(for day: PlanDay, events: [CalendarEvent]) -> [TravelLeg] {
        guard settings.travelTimeEnabled, travelTimes != nil else { return [] }
        return TravelRules.legs(events: events, on: day, home: settings.homePlace, calendar: calendar)
    }

    /// The travel blocks of `day`, from the times already in the cache. Trips without a value have no block
    /// (offline, not loaded yet); they appear after `refreshTravelTimes()`.
    func travelSegments(for day: PlanDay, events: [CalendarEvent]) -> [TravelSegment] {
        guard let travelTimes else { return [] }
        let legs = travelLegs(for: day, events: events)
        guard !legs.isEmpty else { return [] }
        let minutes = travelTimes.cachedMinutes(for: legs, transport: settings.travelTransport)
        return TravelRules.segments(legs: legs, minutes: minutes, events: events, on: day, calendar: calendar)
    }

    /// Looks up the missing travel times of the shown days and reloads once when new values arrived. A second call
    /// finds everything in the cache and returns `false`, so there is no loop.
    @discardableResult
    func refreshTravelTimes() async -> Bool {
        // The month does not show travel time; looking up a whole month would only cost requests.
        guard let travelTimes, settings.travelTimeEnabled, scope != .month else { return false }
        let legs = days.flatMap { plan in travelLegs(for: plan.day, events: plan.events + plan.blocks) }
        guard !legs.isEmpty else { return false }
        guard await travelTimes.fetchMissing(legs: legs, transport: settings.travelTransport) else { return false }
        await reload()
        return true
    }
}
