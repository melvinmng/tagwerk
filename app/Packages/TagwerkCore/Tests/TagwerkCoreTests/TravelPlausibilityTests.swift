import Foundation
import Testing
@testable import TagwerkCore

struct TravelPlausibilityTests {
    let home = TravelPlace(text: "Musterstraße 1, Berlin", latitude: 52.52, longitude: 13.405)
    let berlinCampus = TravelCoordinate(latitude: 52.51, longitude: 13.33)
    let munich = TravelCoordinate(latitude: 48.137, longitude: 11.575)

    // MARK: Distance

    @Test func distance_betweenBerlinAndMunich_isAboutFiveHundredEightyKilometres() {
        let berlin = TravelCoordinate(latitude: 52.52, longitude: 13.405)
        let kilometres = TravelPlausibility.distanceMeters(from: berlin, to: munich) / 1000
        #expect(kilometres > 495 && kilometres < 510)
    }

    @Test func distance_betweenEqualPoints_isZero() {
        #expect(TravelPlausibility.distanceMeters(from: munich, to: munich) == 0)
    }

    // MARK: Reference point

    @Test func reference_prefersHomeCoordinates() {
        let other = TravelPlace(text: "Campus", latitude: 50.0, longitude: 8.0)
        #expect(TravelPlausibility.referencePoint(home: home, otherEnd: other) == TravelCoordinate(latitude: 52.52, longitude: 13.405))
    }

    @Test func reference_fallsBackToTheOtherEndWhenHomeHasNoCoordinates() {
        let textOnlyHome = TravelPlace(text: "Musterstraße 1, Berlin")
        let other = TravelPlace(text: "Campus", latitude: 50.0, longitude: 8.0)
        #expect(TravelPlausibility.referencePoint(home: textOnlyHome, otherEnd: other) == TravelCoordinate(latitude: 50.0, longitude: 8.0))
        #expect(TravelPlausibility.referencePoint(home: nil, otherEnd: other) == TravelCoordinate(latitude: 50.0, longitude: 8.0))
    }

    @Test func reference_isNilWithoutAnyCoordinates() {
        #expect(TravelPlausibility.referencePoint(home: nil, otherEnd: TravelPlace(text: "Mensa")) == nil)
        #expect(TravelPlausibility.referencePoint(home: TravelPlace(text: "Zuhause"), otherEnd: TravelPlace(text: "Mensa")) == nil)
        #expect(TravelPlausibility.referencePoint(home: nil, otherEnd: nil) == nil)
    }

    // MARK: Plausible lookup

    @Test func lookup_nearTheReference_isAccepted() {
        let reference = TravelCoordinate(latitude: 52.52, longitude: 13.405)
        #expect(TravelPlausibility.isPlausibleLookup(berlinCampus, near: reference))
    }

    @Test func lookup_farFromTheReference_isRejected() {
        let reference = TravelCoordinate(latitude: 52.52, longitude: 13.405)
        #expect(!TravelPlausibility.isPlausibleLookup(munich, near: reference))
    }

    @Test func lookup_withoutReference_isRejected() {
        #expect(!TravelPlausibility.isPlausibleLookup(berlinCampus, near: nil))
    }

    @Test func lookup_limitIsFiftyKilometres() {
        let reference = TravelCoordinate(latitude: 52.0, longitude: 13.0)
        // One degree of latitude is about 111.2 km: 0.4° is inside the limit, 0.5° is outside.
        #expect(TravelPlausibility.isPlausibleLookup(TravelCoordinate(latitude: 52.4, longitude: 13.0), near: reference))
        #expect(!TravelPlausibility.isPlausibleLookup(TravelCoordinate(latitude: 52.5, longitude: 13.0), near: reference))
    }

    // MARK: Travel time bound

    @Test func travelTime_upToThreeHours_isPlausible() {
        #expect(TravelPlausibility.isPlausibleTravelTime(minutes: 0))
        #expect(TravelPlausibility.isPlausibleTravelTime(minutes: 180))
        #expect(!TravelPlausibility.isPlausibleTravelTime(minutes: 185))
    }

    @Test func segments_dropTripsLongerThanThreeHours() {
        let calendar = makeCalendar()
        let day = PlanDay(year: 2026, month: 11, day: 19)
        var event = CalendarEvent(id: "e1", externalID: nil, calendarID: "work", title: "e1",
                                  start: instant(2026, 11, 19, 14, 0), end: instant(2026, 11, 19, 15, 0),
                                  isAllDay: false, url: nil, isBusy: true, version: "1")
        event.location = "Campus"
        let leg = TravelLeg(eventID: "e1", origin: .home, from: home, to: TravelPlace(text: "Campus"), arrival: event.start)
        #expect(TravelRules.segments(legs: [leg], minutes: ["e1": 180], events: [event], on: day, calendar: calendar).count == 1)
        #expect(TravelRules.segments(legs: [leg], minutes: ["e1": 185], events: [event], on: day, calendar: calendar).isEmpty)
    }
}
