import CoreLocation
import Foundation
import MapKit
import Observation
import TagwerkCore

/// Asks for the way between two places. Only places and the arrival time go out (to Apple Maps), never to ChatGPT.
protocol TravelTimeEstimating: Sendable {
    /// Coordinates for a place that has none (address text → Apple Maps).
    func coordinates(for place: TravelPlace) async throws -> (latitude: Double, longitude: Double)
    /// The travel time in minutes, rounded up to 5; 0 under 3 minutes. Both places have coordinates.
    func minutes(from: TravelPlace, to: TravelPlace, transport: TravelTransport, arrival: Date) async throws -> Int
}

enum TravelTimeError: Error, Equatable {
    case addressNotFound
    case missingCoordinates
}

/// Apple Maps through MapKit (`MKGeocodingRequest`, `MKDirections`). Needs no location permission: both ends are
/// addresses or coordinates, never the device's position.
struct MapKitTravelEstimator: TravelTimeEstimating {
    func coordinates(for place: TravelPlace) async throws -> (latitude: Double, longitude: Double) {
        guard let request = MKGeocodingRequest(addressString: place.text) else { throw TravelTimeError.addressNotFound }
        let items = try await request.mapItems
        guard let coordinate = items.first?.location.coordinate else { throw TravelTimeError.addressNotFound }
        return (coordinate.latitude, coordinate.longitude)
    }

    func minutes(from: TravelPlace, to: TravelPlace, transport: TravelTransport, arrival: Date) async throws -> Int {
        guard let source = Self.mapItem(from), let destination = Self.mapItem(to) else { throw TravelTimeError.missingCoordinates }
        let request = MKDirections.Request()
        request.source = source
        request.destination = destination
        request.transportType = Self.mapKitType(transport)
        // Past events have no arrival date to plan for; MapKit answers for now then.
        if arrival > .now { request.arrivalDate = arrival }
        let response = try await MKDirections(request: request).calculateETA()
        return TravelRules.roundedMinutes(seconds: response.expectedTravelTime)
    }

    private static func mapItem(_ place: TravelPlace) -> MKMapItem? {
        guard let latitude = place.latitude, let longitude = place.longitude else { return nil }
        return MKMapItem(location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
    }

    private static func mapKitType(_ transport: TravelTransport) -> MKDirectionsTransportType {
        switch transport {
        case .automobile: .automobile
        case .transit: .transit
        case .walking: .walking
        case .cycling: .cycling
        }
    }
}

/// Travel times for the trips of the plan: read synchronously from the cache, fetched in the background.
/// A failed request is not cached and not repeated in the same session, so a missing network or an unknown
/// address costs one request, not a loop.
@MainActor
@Observable
final class TravelTimeService {
    /// Counts the times new values arrived; a view can use it to refresh.
    private(set) var revision = 0
    /// Requests per `fetchMissing` call (MapKit throttles bursts).
    static let requestsPerRun = 20

    @ObservationIgnored private var cache: TravelTimeCache
    @ObservationIgnored private let estimator: any TravelTimeEstimating
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var failedKeys: Set<String> = []
    @ObservationIgnored private var isFetching = false

    init(estimator: any TravelTimeEstimating = MapKitTravelEstimator(), cacheURL: URL? = TravelTimeCache.defaultFileURL,
         now: @escaping () -> Date = Date.init) {
        self.estimator = estimator
        self.cache = TravelTimeCache(fileURL: cacheURL)
        self.now = now
    }

    /// Event ID → known travel time (0 for a trip under 3 minutes). Trips without a value are left out.
    func cachedMinutes(for legs: [TravelLeg], transport: TravelTransport) -> [String: Int] {
        var result: [String: Int] = [:]
        for leg in legs {
            let key = TravelTimeCache.tripKey(from: leg.from, to: leg.to, transport: transport)
            if let minutes = cache.minutes(forTrip: key, now: now()) { result[leg.eventID] = minutes }
        }
        return result
    }

    /// Looks up the trips that have no value yet, one after the other, at most `requestsPerRun` requests. Returns
    /// `true` when new values arrived (the caller reloads once). A leg that failed earlier in this session is skipped.
    func fetchMissing(legs: [TravelLeg], transport: TravelTransport) async -> Bool {
        while isFetching { try? await Task.sleep(for: .milliseconds(50)) }
        isFetching = true
        defer { isFetching = false }
        var requests = 0
        var gotNewValue = false
        var seen = Set<String>()
        for leg in legs {
            let key = TravelTimeCache.tripKey(from: leg.from, to: leg.to, transport: transport)
            guard seen.insert(key).inserted, cache.minutes(forTrip: key, now: now()) == nil,
                  !failedKeys.contains(key) else { continue }
            guard requests < Self.requestsPerRun else { break }
            requests += 1
            do {
                let from = try await located(leg.from)
                let to = try await located(leg.to)
                let minutes = try await estimator.minutes(from: from, to: to, transport: transport, arrival: leg.arrival)
                cache.store(minutes: minutes, forTrip: key, now: now())
                gotNewValue = true
            } catch {
                failedKeys.insert(key)
            }
        }
        if gotNewValue {
            cache.save()
            revision += 1
        }
        return gotNewValue
    }

    /// The place with coordinates: its own, the cached lookup, or a new lookup (cached on success). The place keeps
    /// its key, so the trip's cache entry does not depend on whether the lookup came from the cache.
    private func located(_ place: TravelPlace) async throws -> TravelPlace {
        if place.latitude != nil, place.longitude != nil { return place }
        let placeKey = TravelTimeCache.placeKey(place)
        var result = place
        if let known = cache.coordinates(forPlace: placeKey, now: now()) {
            result.latitude = known.latitude
            result.longitude = known.longitude
            return result
        }
        if failedKeys.contains(placeKey) { throw TravelTimeError.addressNotFound }
        do {
            let found = try await estimator.coordinates(for: place)
            cache.store(latitude: found.latitude, longitude: found.longitude, forPlace: placeKey, now: now())
            result.latitude = found.latitude
            result.longitude = found.longitude
            return result
        } catch {
            failedKeys.insert(placeKey)
            throw error
        }
    }
}
