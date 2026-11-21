import MapKit
import Testing
import TagwerkCore
@testable import Tagwerk

struct TravelRouteTests {
    @Test func directionsMode_mapsEveryTransport() {
        #expect(TravelRoute.directionsMode(for: .automobile) == MKLaunchOptionsDirectionsModeDriving)
        #expect(TravelRoute.directionsMode(for: .transit) == MKLaunchOptionsDirectionsModeTransit)
        #expect(TravelRoute.directionsMode(for: .walking) == MKLaunchOptionsDirectionsModeWalking)
        #expect(TravelRoute.directionsMode(for: .cycling) == MKLaunchOptionsDirectionsModeCycling)
        // Every transport has its own mode, none falls back to the default silently.
        let modes = Set(TravelTransport.allCases.map(TravelRoute.directionsMode(for:)))
        #expect(modes.count == TravelTransport.allCases.count)
        #expect(!modes.contains(MKLaunchOptionsDirectionsModeDefault))
    }

    @Test func mapsURL_namesStartDestinationAndMode() throws {
        let from = TravelPlace(text: "Musterstraße 1, Berlin")
        let to = TravelPlace(text: "Praxis Dr. Muster, Hauptstraße 5, Berlin")
        let url = try #require(TravelRoute.mapsURL(from: from, to: to, transport: .transit))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "saddr" }?.value == "Musterstraße 1, Berlin")
        #expect(items.first { $0.name == "daddr" }?.value == "Praxis Dr. Muster, Hauptstraße 5, Berlin")
        #expect(items.first { $0.name == "dirflg" }?.value == "r")
        // Places with coordinates are named by them, so the route fits the time shown.
        let located = TravelPlace(text: "Büro", latitude: 52.5, longitude: 13.4)
        let byCoordinates = try #require(TravelRoute.mapsURL(from: located, to: to, transport: .automobile))
        let located_items = try #require(URLComponents(url: byCoordinates, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(located_items.first { $0.name == "saddr" }?.value == "52.5,13.4")
        #expect(located_items.first { $0.name == "dirflg" }?.value == "d")
    }
}
