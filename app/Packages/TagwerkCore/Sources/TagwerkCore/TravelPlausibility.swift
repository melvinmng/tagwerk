import Foundation

/// A point on the earth, without any framework type (CoreLocation stays out of the core package).
public struct TravelCoordinate: Sendable, Hashable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Plausibility rules for travel times. A free text such as "Raum 2.14", "Mensa" or "Bibliothek" can resolve to a
/// place far away; such a result must not turn into an absurd trip that blocks the day.
public enum TravelPlausibility {
    /// A looked-up place must lie within this distance of the reference point.
    public static let maximumLookupDistanceMeters: Double = 50_000
    /// A trip longer than this is not shown and not stored.
    public static let maximumTravelMinutes = 180

    private static let earthRadiusMeters: Double = 6_371_000

    /// Great-circle distance (haversine) in metres.
    public static func distanceMeters(from first: TravelCoordinate, to second: TravelCoordinate) -> Double {
        let latitudeFirst = first.latitude * .pi / 180
        let latitudeSecond = second.latitude * .pi / 180
        let latitudeDelta = (second.latitude - first.latitude) * .pi / 180
        let longitudeDelta = (second.longitude - first.longitude) * .pi / 180
        let haversine = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(latitudeFirst) * cos(latitudeSecond) * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return 2 * earthRadiusMeters * asin(min(1, haversine.squareRoot()))
    }

    /// The point a free-text lookup is checked against: the home place if it has coordinates, otherwise the other
    /// end of the leg if that has coordinates. `nil` without any: then a free text is not looked up at all.
    public static func referencePoint(home: TravelPlace?, otherEnd: TravelPlace?) -> TravelCoordinate? {
        for place in [home, otherEnd] {
            if let latitude = place?.latitude, let longitude = place?.longitude {
                return TravelCoordinate(latitude: latitude, longitude: longitude)
            }
        }
        return nil
    }

    /// Whether a looked-up place is close enough to the reference point. Without a reference nothing is plausible.
    public static func isPlausibleLookup(_ found: TravelCoordinate, near reference: TravelCoordinate?) -> Bool {
        guard let reference else { return false }
        return distanceMeters(from: found, to: reference) <= maximumLookupDistanceMeters
    }

    /// Whether a computed trip is short enough to be shown.
    public static func isPlausibleTravelTime(minutes: Int) -> Bool {
        minutes <= maximumTravelMinutes
    }
}
