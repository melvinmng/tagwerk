import Foundation
import Testing
@testable import TagwerkCore

struct TravelRulesTests {
    let calendar = makeCalendar()
    let day = PlanDay(year: 2026, month: 11, day: 19)
    let home = TravelPlace(text: "Musterstraße 1, Berlin")

    private func event(_ id: String, _ from: Int, _ to: Int, location: String?, busy: Bool = true, allDay: Bool = false,
                       latitude: Double? = nil, longitude: Double? = nil) -> CalendarEvent {
        var result = CalendarEvent(id: id, externalID: nil, calendarID: "work", title: id,
                                   start: instant(2026, 11, 19, from / 60, from % 60), end: instant(2026, 11, 19, to / 60, to % 60),
                                   isAllDay: allDay, url: nil, isBusy: busy, version: "1")
        result.location = location
        result.latitude = latitude
        result.longitude = longitude
        return result
    }

    private func legs(_ events: [CalendarEvent], home: TravelPlace? = nil) -> [TravelLeg] {
        TravelRules.legs(events: events, on: day, home: home ?? self.home, calendar: calendar)
    }

    // MARK: Which events get a leg

    @Test func onlineLocation_hasNoLeg() {
        for text in ["Zoom", "zoom meeting", "Microsoft Teams-Besprechung", "Webex", "Google Meet", "Online", "FaceTime", "Online-Meeting", "virtuell"] {
            #expect(legs([event("a", 600, 660, location: text)]).isEmpty, "\(text) is no physical place")
        }
    }

    @Test func urlLocation_hasNoLeg() {
        #expect(legs([event("a", 600, 660, location: "https://example.com/room/42")]).isEmpty)
        #expect(legs([event("a", 600, 660, location: "www.example.com")]).isEmpty)
        #expect(legs([event("a", 600, 660, location: "   ")]).isEmpty)
        #expect(legs([event("a", 600, 660, location: nil)]).isEmpty)
    }

    @Test func physicalLocations_areRecognised() {
        #expect(TravelRules.isPhysicalLocation("Hauptstraße 5, 10115 Berlin"))
        #expect(TravelRules.isPhysicalLocation("Campus Nord, Raum 2.14"))
        #expect(!TravelRules.isPhysicalLocation("Teams"))
    }

    @Test func placesWithOnlineInTheName_arePhysical() {
        #expect(TravelRules.isPhysicalLocation("Online Business Center"))
        #expect(TravelRules.isPhysicalLocation("Online-Shop GmbH, Hauptstr. 1"))
        #expect(TravelRules.isPhysicalLocation("Virtual Reality Lab, Raum 3"))
        #expect(TravelRules.isPhysicalLocation("Teamsitzung, Raum 4"))
        #expect(TravelRules.isPhysicalLocation("Zoomstraße 7, Berlin"))
        #expect(TravelRules.isPhysicalLocation("Skypark Büro"))
        #expect(TravelRules.isPhysicalLocation("Hauptstr. 1/2, Berlin"))
        #expect(TravelRules.isPhysicalLocation("Raum 2.14/3"))
    }

    @Test func onlineMeetings_areNotPhysical() {
        // Web addresses.
        #expect(!TravelRules.isPhysicalLocation("https://meet.example.com/abc"))
        #expect(!TravelRules.isPhysicalLocation("www.example.com/room"))
        #expect(!TravelRules.isPhysicalLocation("  WWW.Example.com "))
        #expect(!TravelRules.isPhysicalLocation("meet.google.com/abc-defg-hij"))
        #expect(!TravelRules.isPhysicalLocation("Raum 3, www.example.com"))
        // Known meeting services as whole words.
        for service in ["Zoom", "Microsoft Teams", "Webex-Meeting", "FaceTime", "Google Meet", "google  meet", "Skype", "Jitsi",
                        "Besprechung über Zoom (ID 123)", "Teams-Anruf"] {
            #expect(!TravelRules.isPhysicalLocation(service), "\(service)")
        }
        // The whole text names an online event.
        for text in ["online", "Online", "  Online-Meeting ", "Online meeting", "virtuell", "Virtuell", "virtual", "VIRTUAL"] {
            #expect(!TravelRules.isPhysicalLocation(text), "\(text)")
        }
        #expect(!TravelRules.isPhysicalLocation(""))
        #expect(!TravelRules.isPhysicalLocation("  \n"))
    }

    @Test func allDayAndFreeEvents_areIgnored() {
        let events = [event("allDay", 0, 1440, location: "Büro, Berlin", allDay: true),
                      event("free", 600, 660, location: "Büro, Berlin", busy: false)]
        #expect(legs(events).isEmpty)
        // They are no starting point either: the next event starts at home.
        let next = legs(events + [event("meeting", 780, 840, location: "Kunde, Hamburg")])
        #expect(next.count == 1)
        #expect(next.first?.origin == .home)
    }

    // MARK: Starting point

    @Test func firstEvent_startsAtHome() throws {
        let leg = try #require(legs([event("a", 600, 660, location: "Büro, Berlin")]).first)
        #expect(leg.origin == .home)
        #expect(leg.eventID == "a")
        #expect(leg.from == home)
        #expect(leg.to.text == "Büro, Berlin")
        #expect(leg.arrival == instant(2026, 11, 19, 10, 0))
    }

    @Test func firstEvent_withoutHome_hasNoLeg() {
        let events = [event("a", 600, 660, location: "Büro, Berlin")]
        #expect(TravelRules.legs(events: events, on: day, home: nil, calendar: calendar).isEmpty)
    }

    @Test func followingEvent_startsAtPreviousLocation() throws {
        let events = [event("a", 540, 600, location: "Büro, Berlin"), event("b", 630, 690, location: "Kunde, Potsdam")]
        let found = legs(events)
        #expect(found.count == 2)
        let second = try #require(found.last)
        #expect(second.origin == .previousEvent(id: "a"))
        #expect(second.from.text == "Büro, Berlin")
        #expect(second.to.text == "Kunde, Potsdam")
    }

    @Test func previousEventWithoutPlace_isSkipped() throws {
        // An online meeting in between does not move anyone: the trip starts at the last real place.
        let events = [event("a", 540, 600, location: "Büro, Berlin"), event("zoom", 600, 630, location: "Zoom"),
                      event("b", 660, 720, location: "Kunde, Potsdam")]
        let leg = try #require(legs(events).last)
        #expect(leg.origin == .previousEvent(id: "a"))
    }

    @Test func longGap_startsAtHome() throws {
        // The gap is 4 hours: longer than `homeGapMinutes`.
        let events = [event("a", 540, 600, location: "Büro, Berlin"), event("b", 840, 900, location: "Kunde, Potsdam")]
        let leg = try #require(legs(events).last)
        #expect(leg.origin == .home)
        // Exactly at the limit the previous place still counts.
        let atLimit = [event("a", 540, 600, location: "Büro, Berlin"), event("b", 780, 840, location: "Kunde, Potsdam")]
        #expect(try #require(legs(atLimit).last).origin == .previousEvent(id: "a"))
    }

    @Test func longGap_withoutHome_hasNoLeg() {
        let events = [event("a", 540, 600, location: "Büro, Berlin"), event("b", 840, 900, location: "Kunde, Potsdam")]
        let found = TravelRules.legs(events: events, on: day, home: nil, calendar: calendar)
        #expect(found.map(\.eventID) == [])
    }

    @Test func overlappingPreviousEvent_isNoStartingPoint() throws {
        // "a" is still running when "b" starts, so it cannot be left behind: the trip starts at home.
        let events = [event("a", 540, 660, location: "Büro, Berlin"), event("b", 630, 690, location: "Kunde, Potsdam")]
        let leg = try #require(legs(events).last)
        #expect(leg.eventID == "b")
        #expect(leg.origin == .home)
    }

    @Test func sameLocation_hasNoLeg() {
        let events = [event("a", 540, 600, location: "Büro, Berlin"), event("b", 630, 690, location: "  büro,  berlin ")]
        #expect(legs(events).map(\.eventID) == ["a"])
    }

    @Test func eventAtHome_fromHome_hasNoLeg() {
        #expect(legs([event("a", 600, 660, location: "musterstraße 1, berlin")]).isEmpty)
        // After another place the way home counts.
        let events = [event("a", 540, 600, location: "Büro, Berlin"), event("b", 630, 690, location: "Musterstraße 1, Berlin")]
        #expect(legs(events).map(\.eventID) == ["a", "b"])
    }

    @Test func eventsOfOtherDays_areIgnored() {
        let other = CalendarEvent(id: "x", externalID: nil, calendarID: "work", title: "x", start: instant(2026, 11, 20, 10),
                                  end: instant(2026, 11, 20, 11), isAllDay: false, url: nil, isBusy: true, version: "1")
        var located = other
        located.location = "Büro, Berlin"
        #expect(legs([located]).isEmpty)
    }

    // MARK: Segments

    private func segments(_ events: [CalendarEvent], minutes: [String: Int]) -> [TravelSegment] {
        TravelRules.segments(legs: legs(events), minutes: minutes, events: events, on: day, calendar: calendar)
    }

    @Test func segment_endsAtEventStart() throws {
        let segment = try #require(segments([event("a", 600, 660, location: "Büro, Berlin")], minutes: ["a": 25]).first)
        #expect(segment.range == 575..<600)
        #expect(segment.minutes == 25)
        #expect(segment.eventID == "a")
        #expect(segment.origin == .home)
        #expect(!segment.isTight)
    }

    @Test func segment_isTightWhenOverlappingPreviousEvent() throws {
        // Previous event ends 10:00, next starts 10:20, the trip takes 35 minutes: it would start at 09:45.
        let events = [event("a", 540, 600, location: "Büro, Berlin"), event("b", 620, 680, location: "Kunde, Potsdam")]
        let segment = try #require(segments(events, minutes: ["b": 35]).last)
        #expect(segment.range == 585..<620)
        #expect(segment.isTight)
        // With enough time in between it is not tight.
        let relaxed = try #require(segments(events, minutes: ["b": 15]).last)
        #expect(!relaxed.isTight)
    }

    @Test func segment_isCutAtMidnight() throws {
        let segment = try #require(segments([event("a", 10, 60, location: "Büro, Berlin")], minutes: ["a": 45]).first)
        #expect(segment.range == 0..<10)
        #expect(segment.minutes == 10)
    }

    @Test func missingMinutes_hasNoSegment() {
        let events = [event("a", 540, 600, location: "Büro, Berlin"), event("b", 630, 690, location: "Kunde, Potsdam")]
        let found = segments(events, minutes: ["b": 20])
        #expect(found.map(\.eventID) == ["b"])
        #expect(segments(events, minutes: [:]).isEmpty)
        #expect(segments(events, minutes: ["a": 0, "b": 0]).isEmpty)
    }

    // MARK: Places and rounding

    @Test func placeKey_prefersRoundedCoordinates() {
        let near = TravelPlace(text: "Büro", latitude: 52.520_008, longitude: 13.404_954)
        let alsoNear = TravelPlace(text: "Bürogebäude A", latitude: 52.520_012, longitude: 13.404_970)
        #expect(near.key == alsoNear.key)
        #expect(near.key != TravelPlace(text: "Büro", latitude: 52.53, longitude: 13.40).key)
        #expect(near.key.hasPrefix("geo:"))
    }

    @Test func placeKey_normalisesText() {
        #expect(TravelPlace(text: "  Hauptstraße 5,\n Berlin ").key == TravelPlace(text: "hauptstraße 5, berlin").key)
        #expect(TravelPlace(text: "Café Süd").key == TravelPlace(text: "cafe sud").key)
        #expect(TravelPlace(text: "Büro").key != TravelPlace(text: "Büro 2").key)
    }

    @Test func roundedMinutes_roundsUpToFive() {
        #expect(TravelRules.roundedMinutes(seconds: 0) == 0)
        #expect(TravelRules.roundedMinutes(seconds: 179) == 0)
        #expect(TravelRules.roundedMinutes(seconds: 180) == 5)
        #expect(TravelRules.roundedMinutes(seconds: 300) == 5)
        #expect(TravelRules.roundedMinutes(seconds: 301) == 10)
        #expect(TravelRules.roundedMinutes(seconds: 1_480) == 25)
        #expect(TravelRules.roundedMinutes(seconds: -5) == 0)
    }

    @Test func transport_roundTripsThroughRawValue() {
        for transport in TravelTransport.allCases { #expect(TravelTransport(rawValue: transport.rawValue) == transport) }
        #expect(TravelTransport.allCases.count == 4)
    }
}
