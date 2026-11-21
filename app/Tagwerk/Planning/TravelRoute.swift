import CoreLocation
import MapKit
import TagwerkCore
import UIKit

/// Opens the trip in Apple Maps: from the origin of the trip (home or the previous event) to the place of the event,
/// with both ends named, so Maps does not take the current location and the route fits the time shown.
enum TravelRoute {
    /// The Maps direction mode for a transport.
    static func directionsMode(for transport: TravelTransport) -> String {
        switch transport {
        case .automobile: MKLaunchOptionsDirectionsModeDriving
        case .transit: MKLaunchOptionsDirectionsModeTransit
        case .walking: MKLaunchOptionsDirectionsModeWalking
        case .cycling: MKLaunchOptionsDirectionsModeCycling
        }
    }

    /// The `dirflg` value of the Maps web address for a transport.
    private static func directionFlag(for transport: TravelTransport) -> String {
        switch transport {
        case .automobile: "d"
        case .transit: "r"
        case .walking: "w"
        case .cycling: "b"
        }
    }

    /// A Maps web address with the start, the destination and the mode, for places without coordinates (a free text
    /// is resolved by Maps itself). Coordinates, where known, name the place more exactly than its text.
    static func mapsURL(from: TravelPlace, to: TravelPlace, transport: TravelTransport) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "saddr", value: address(of: from)),
            URLQueryItem(name: "daddr", value: address(of: to)),
            URLQueryItem(name: "dirflg", value: directionFlag(for: transport)),
        ]
        return components?.url
    }

    private static func address(of place: TravelPlace) -> String {
        if let latitude = place.latitude, let longitude = place.longitude { return "\(latitude),\(longitude)" }
        return place.text
    }

    @MainActor
    static func open(from: TravelPlace, to: TravelPlace, transport: TravelTransport) {
        if let source = mapItem(from), let destination = mapItem(to) {
            MKMapItem.openMaps(with: [source, destination],
                               launchOptions: [MKLaunchOptionsDirectionsModeKey: directionsMode(for: transport)])
        } else if let url = mapsURL(from: from, to: to, transport: transport) {
            UIApplication.shared.open(url)
        }
    }

    private static func mapItem(_ place: TravelPlace) -> MKMapItem? {
        guard let latitude = place.latitude, let longitude = place.longitude else { return nil }
        let item = MKMapItem(location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
        item.name = place.text
        return item
    }
}
