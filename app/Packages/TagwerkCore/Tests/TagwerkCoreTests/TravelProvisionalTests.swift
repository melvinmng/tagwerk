import Foundation
import Testing
@testable import TagwerkCore

/// Provisional travel blocks (no network) and manual overrides in the travel segments of a day.
struct TravelProvisionalTests {
    let calendar = makeCalendar()
    let day = PlanDay(year: 2026, month: 11, day: 19)
    let home = TravelPlace(text: "Musterstraße 1, Berlin")

    private func event(_ id: String, _ from: Int, _ to: Int, location: String?, busy: Bool = true, allDay: Bool = false) -> CalendarEvent {
        var result = CalendarEvent(id: id, externalID: nil, calendarID: "work", title: id,
                                   start: instant(2026, 11, 19, from / 60, from % 60), end: instant(2026, 11, 19, to / 60, to % 60),
                                   isAllDay: allDay, url: nil, isBusy: busy, version: "1")
        result.location = location
        return result
    }

    private func segments(_ events: [CalendarEvent], minutes: [String: Int] = [:], provisional: [String: Int] = [:],
                          overrides: [String: TravelOverrideMode] = [:]) -> [TravelSegment] {
        let legs = TravelRules.legs(events: events, on: day, home: home, calendar: calendar)
        return TravelRules.segments(legs: legs, minutes: minutes, provisionalMinutes: provisional, overrides: overrides,
                                    events: events, on: day, calendar: calendar)
    }

    // MARK: Fallback value

    @Test func provisionalMinutes_withoutAnyKnownValue_isThirty() {
        #expect(TravelRules.defaultProvisionalMinutes == 30)
        #expect(TravelRules.provisionalMinutes(lastKnownToDestination: nil) == 30)
    }

    @Test func provisionalMinutes_usesTheLastKnownValueToTheDestination() {
        #expect(TravelRules.provisionalMinutes(lastKnownToDestination: 20) == 20)
    }

    @Test func provisionalMinutes_ignoresValuesThatAreNoTrip() {
        // 0 means "under 3 minutes" for another starting point; it says nothing about this trip.
        #expect(TravelRules.provisionalMinutes(lastKnownToDestination: 0) == 30)
        #expect(TravelRules.provisionalMinutes(lastKnownToDestination: TravelPlausibility.maximumTravelMinutes + 5) == 30)
    }

    // MARK: Provisional segments

    @Test func provisionalMinutes_makeAMarkedSegment() throws {
        let segment = try #require(segments([event("a", 600, 660, location: "Büro, Berlin")], provisional: ["a": 30]).first)
        #expect(segment.range == 570..<600)
        #expect(segment.minutes == 30)
        #expect(segment.source == .provisional)
        #expect(segment.origin == .home)
    }

    @Test func knownMinutes_winOverProvisionalOnes() throws {
        let segment = try #require(segments([event("a", 600, 660, location: "Büro, Berlin")], minutes: ["a": 20],
                                            provisional: ["a": 30]).first)
        #expect(segment.minutes == 20)
        #expect(segment.source == .automatic)
    }

    @Test func provisionalSegment_isTightLikeARealOne() throws {
        let events = [event("a", 540, 600, location: "Büro, Berlin"), event("b", 620, 680, location: "Kunde, Potsdam")]
        let segment = try #require(segments(events, provisional: ["b": 30]).last)
        #expect(segment.range == 590..<620)
        #expect(segment.isTight)
        #expect(segment.source == .provisional)
    }

    @Test func implausibleProvisionalMinutes_haveNoSegment() {
        #expect(segments([event("a", 600, 660, location: "Büro, Berlin")], provisional: ["a": 185]).isEmpty)
        #expect(segments([event("a", 600, 660, location: "Büro, Berlin")], provisional: ["a": 0]).isEmpty)
    }

    @Test func automaticSegments_areNotProvisional() throws {
        let segment = try #require(segments([event("a", 600, 660, location: "Büro, Berlin")], minutes: ["a": 25]).first)
        #expect(segment.source == .automatic)
    }

    // MARK: Overrides

    @Test func overrideNone_removesTheSegment() {
        let events = [event("a", 600, 660, location: "Büro, Berlin")]
        #expect(segments(events, minutes: ["a": 25], overrides: ["a": .none]).isEmpty)
        #expect(segments(events, provisional: ["a": 30], overrides: ["a": .none]).isEmpty)
    }

    @Test func overrideFixed_replacesTheAutomaticValue() throws {
        let events = [event("a", 600, 660, location: "Büro, Berlin")]
        let segment = try #require(segments(events, minutes: ["a": 25], overrides: ["a": .fixed(minutes: 40)]).first)
        #expect(segment.range == 560..<600)
        #expect(segment.minutes == 40)
        #expect(segment.source == .manual)
        #expect(segment.origin == .home)
    }

    @Test func overrideFixed_worksWithoutAnyAutomaticValue() throws {
        let events = [event("a", 600, 660, location: "Büro, Berlin")]
        let segment = try #require(segments(events, overrides: ["a": .fixed(minutes: 15)]).first)
        #expect(segment.minutes == 15)
        #expect(segment.source == .manual)
    }

    @Test func overrideAutomatic_changesNothing() throws {
        let events = [event("a", 600, 660, location: "Büro, Berlin")]
        let segment = try #require(segments(events, minutes: ["a": 25], overrides: ["a": .automatic]).first)
        #expect(segment.minutes == 25)
        #expect(segment.source == .automatic)
    }

    @Test func overrideFixed_forAnEventWithoutPlace_startsAtHome() throws {
        let segment = try #require(segments([event("a", 600, 660, location: nil)], overrides: ["a": .fixed(minutes: 20)]).first)
        #expect(segment.range == 580..<600)
        #expect(segment.origin == .home)
        #expect(segment.source == .manual)
    }

    @Test func overrideFixed_forAnOnlineEvent_isHonoured() throws {
        let segment = try #require(segments([event("a", 600, 660, location: "Zoom")], overrides: ["a": .fixed(minutes: 10)]).first)
        #expect(segment.minutes == 10)
    }

    @Test func overrideFixed_withoutHomeAddress_stillWorks() throws {
        // No home place means no automatic trip, but a manual value needs none.
        let events = [event("a", 600, 660, location: "Büro, Berlin")]
        let legs = TravelRules.legs(events: events, on: day, home: nil, calendar: calendar)
        #expect(legs.isEmpty)
        let found = TravelRules.segments(legs: legs, minutes: [:], overrides: ["a": .fixed(minutes: 25)], events: events,
                                         on: day, calendar: calendar)
        #expect(found.map(\.minutes) == [25])
    }

    @Test func overrideFixed_afterAnotherPlace_startsThere_andIsTight() throws {
        let events = [event("a", 540, 600, location: "Büro, Berlin"), event("b", 620, 680, location: nil)]
        let segment = try #require(segments(events, overrides: ["b": .fixed(minutes: 35)]).first { $0.eventID == "b" })
        #expect(segment.origin == .previousEvent(id: "a"))
        #expect(segment.range == 585..<620)
        #expect(segment.isTight)
    }

    @Test func overrideFixed_afterALongGap_startsAtHome() throws {
        let events = [event("a", 540, 600, location: "Büro, Berlin"), event("b", 900, 960, location: nil)]
        let segment = try #require(segments(events, overrides: ["b": .fixed(minutes: 20)]).first { $0.eventID == "b" })
        #expect(segment.origin == .home)
    }

    @Test func overrideFixed_isIgnoredForAllDayFreeAndOtherDayEvents() {
        let allDay = event("allDay", 0, 1440, location: nil, allDay: true)
        let free = event("free", 600, 660, location: nil, busy: false)
        var otherDay = event("other", 600, 660, location: nil)
        otherDay.start = instant(2026, 11, 20, 10)
        otherDay.end = instant(2026, 11, 20, 11)
        let overrides: [String: TravelOverrideMode] = ["allDay": .fixed(minutes: 10), "free": .fixed(minutes: 10), "other": .fixed(minutes: 10)]
        #expect(segments([allDay, free, otherDay], overrides: overrides).isEmpty)
    }

    @Test func overrideFixed_isBoundedLikeTheEditor() throws {
        let events = [event("a", 600, 660, location: nil)]
        #expect(try #require(segments(events, overrides: ["a": .fixed(minutes: 500)]).first).minutes == 180)
    }

    @Test func overrideFixed_isCutAtMidnight() throws {
        let segment = try #require(segments([event("a", 10, 60, location: nil)], overrides: ["a": .fixed(minutes: 45)]).first)
        #expect(segment.range == 0..<10)
        #expect(segment.minutes == 10)
    }

    @Test func segments_areOrderedByEventStart() {
        let events = [event("late", 840, 900, location: "Kunde, Potsdam"), event("early", 540, 600, location: nil),
                      event("middle", 700, 760, location: "Büro, Berlin")]
        let found = segments(events, minutes: ["late": 60, "middle": 20], overrides: ["early": .fixed(minutes: 15)])
        #expect(found.map(\.eventID) == ["early", "middle", "late"])
    }
}
