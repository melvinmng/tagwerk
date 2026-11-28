import CoreLocation
import Foundation
import MapKit
import Observation
import TagwerkCore

/// Asks for the way between two places. Only places and the arrival time go out (to Apple Maps), never to ChatGPT.
protocol TravelTimeEstimating: Sendable {
    /// Looks up an address text (→ Apple Maps): its coordinates and how Apple Maps writes it. With `near`, the search
    /// is biased to a region around that point (a short text such as "Mensa" then finds the one close by).
    func lookUp(address: String, near: TravelCoordinate?) async throws -> PlaceLookup
    /// The travel time in minutes, rounded up to 5; 0 under 3 minutes. Both places have coordinates.
    func minutes(from: TravelPlace, to: TravelPlace, transport: TravelTransport, arrival: Date) async throws -> Int
    /// The travel time of a trip that starts at `departure` (the way home after an event). The default asks as for
    /// an arrival at that time.
    func minutes(from: TravelPlace, to: TravelPlace, transport: TravelTransport, departure: Date) async throws -> Int
}

extension TravelTimeEstimating {
    func minutes(from: TravelPlace, to: TravelPlace, transport: TravelTransport, departure: Date) async throws -> Int {
        try await minutes(from: from, to: to, transport: transport, arrival: departure)
    }

    /// A lookup without a reference point (the home address in the settings).
    func lookUp(address: String) async throws -> PlaceLookup { try await lookUp(address: address, near: nil) }
}

/// An address found by Apple Maps.
struct PlaceLookup: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    /// The address as Apple Maps writes it, for the settings ("Gefunden: …").
    var description: String
}

enum TravelTimeError: Error, Equatable {
    case addressNotFound
    case missingCoordinates
    /// A free text without home or other end with coordinates: not looked up.
    case noReferencePoint
}

/// Apple Maps through MapKit (`MKGeocodingRequest`, `MKDirections`). Needs no location permission: both ends are
/// addresses or coordinates, never the device's position.
struct MapKitTravelEstimator: TravelTimeEstimating {
    /// The search region around a reference point: as wide as the plausibility radius, in both directions.
    private static let searchSpanMeters = TravelPlausibility.maximumLookupDistanceMeters * 2

    func lookUp(address: String, near: TravelCoordinate?) async throws -> PlaceLookup {
        guard let request = MKGeocodingRequest(addressString: address) else { throw TravelTimeError.addressNotFound }
        if let near {
            // `MKGeocodingRequest.region` biases the result towards the region (MapKit, iOS 26 and later).
            request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: near.latitude, longitude: near.longitude),
                                                latitudinalMeters: Self.searchSpanMeters, longitudinalMeters: Self.searchSpanMeters)
        }
        let items = try await request.mapItems
        guard let item = items.first else { throw TravelTimeError.addressNotFound }
        let coordinate = item.location.coordinate
        return PlaceLookup(latitude: coordinate.latitude, longitude: coordinate.longitude,
                           description: item.address?.fullAddress ?? item.name ?? address)
    }

    func minutes(from: TravelPlace, to: TravelPlace, transport: TravelTransport, arrival: Date) async throws -> Int {
        try await eta(from: from, to: to, transport: transport) { request in
            // Past events have no arrival date to plan for; MapKit answers for now then.
            if arrival > .now { request.arrivalDate = arrival }
        }
    }

    func minutes(from: TravelPlace, to: TravelPlace, transport: TravelTransport, departure: Date) async throws -> Int {
        try await eta(from: from, to: to, transport: transport) { request in
            if departure > .now { request.departureDate = departure }
        }
    }

    private func eta(from: TravelPlace, to: TravelPlace, transport: TravelTransport,
                     timing: (MKDirections.Request) -> Void) async throws -> Int {
        guard let source = Self.mapItem(from), let destination = Self.mapItem(to) else { throw TravelTimeError.missingCoordinates }
        let request = MKDirections.Request()
        request.source = source
        request.destination = destination
        request.transportType = Self.mapKitType(transport)
        timing(request)
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

/// What the plan knows about the trips of a day, by event ID.
struct ResolvedTravelTimes: Equatable {
    /// Known travel times (also older ones; 0 for a trip under 3 minutes).
    var minutes: [String: Int] = [:]
    /// Estimates for trips that could not be asked (no network) and have no value yet.
    var provisionalMinutes: [String: Int] = [:]
}

/// Travel times for the trips of the plan: read synchronously from the cache, fetched in the background.
///
/// Offline (F2): a stored time is used at any age and only asked for again online (`TravelTimeCache`). A trip without a
/// value whose request failed for a network reason (`TravelFailure.offline`) is `provisional`: the plan shows an
/// estimate (last time to the same destination, else 30 minutes) until a fresh value arrives; it is asked again after
/// `transientRetryInterval`. "Not found" answers are stored and give no block; a request that cannot be asked at all
/// (no starting point) is not repeated in the same session.
///
/// Plausibility (see `TravelPlausibility`): the text of a place without coordinates is only looked up when there is a
/// reference point (home or the other end of the trip, with coordinates), and a result more than 50 km away from it
/// counts as not found. A trip longer than 180 minutes is discarded. Neither is stored as a value.
@MainActor
@Observable
final class TravelTimeService {
    /// Counts the times the plan changed because of the service (a new value, a trip turning provisional or not);
    /// a view can use it to refresh.
    private(set) var revision = 0
    /// Requests per `fetchMissing` call (MapKit throttles bursts).
    static let requestsPerRun = 20
    /// A trip that failed for a network reason is not asked again before this many seconds have passed.
    static let transientRetryInterval: TimeInterval = 60

    @ObservationIgnored private var cache: TravelTimeCache
    @ObservationIgnored private let estimator: any TravelTimeEstimating
    @ObservationIgnored private let now: () -> Date
    /// Trips and places that cannot be asked in this session.
    @ObservationIgnored private var failedKeys: Set<String> = []
    /// Trips without a value whose last request failed for a network reason.
    @ObservationIgnored private var provisionalKeys: Set<String> = []
    @ObservationIgnored private var retryAfter: [String: Date] = [:]
    /// The most recent queued `fetchMissing` run. A new call waits for it (not by polling) and then starts its own, so runs
    /// never overlap and the cache and the failure sets are only touched by one run at a time.
    @ObservationIgnored private var lastRun: Task<Void, Never>?

    init(estimator: any TravelTimeEstimating = MapKitTravelEstimator(), cacheURL: URL? = TravelTimeCache.defaultFileURL,
         now: @escaping () -> Date = Date.init) {
        self.estimator = estimator
        self.cache = TravelTimeCache(fileURL: cacheURL)
        self.now = now
    }

    /// Trip ID (`TravelLeg.id`) → known travel time (0 for a trip under 3 minutes). Trips without a value are left out.
    func cachedMinutes(for legs: [TravelLeg], transport: TravelTransport) -> [String: Int] {
        resolvedTimes(for: legs, transport: transport).minutes
    }

    /// The known times and the estimates for trips that could not be asked.
    func resolvedTimes(for legs: [TravelLeg], transport: TravelTransport) -> ResolvedTravelTimes {
        var result = ResolvedTravelTimes()
        for leg in legs {
            let legTransport = leg.transport ?? transport
            let key = TravelTimeCache.tripKey(from: leg.from, to: leg.to, transport: legTransport)
            if let minutes = cache.minutes(forTrip: key) {
                result.minutes[leg.id] = minutes
            } else if !cache.isRejected(forTrip: key), provisionalKeys.contains(key) {
                result.provisionalMinutes[leg.id] = TravelRules.provisionalMinutes(
                    lastKnownToDestination: cache.latestMinutes(toDestination: leg.to.key, transport: legTransport))
            }
        }
        return result
    }

    /// Looks up the trips that have no value yet or an old one, one after the other, at most `requestsPerRun` requests.
    /// Returns `true` when the plan changes (a new or different value, a trip that turned provisional or got its
    /// value); the caller reloads once. The same failure a second time returns `false`, so there is no loop.
    /// `home` is the home place; with coordinates it is the reference point for looking up free-text places.
    ///
    /// Concurrent calls run one after the other in the order they arrived. A cancelled caller stops its own run; the runs of
    /// other callers are not affected.
    func fetchMissing(legs: [TravelLeg], transport: TravelTransport, home: TravelPlace? = nil) async -> Bool {
        let previousRun = lastRun
        let run = Task { [self] () -> Bool in
            await previousRun?.value
            return await performFetch(legs: legs, transport: transport, home: home)
        }
        lastRun = Task { _ = await run.value }
        return await withTaskCancellationHandler {
            await run.value
        } onCancel: {
            run.cancel()
        }
    }

    private func performFetch(legs: [TravelLeg], transport: TravelTransport, home: TravelPlace?) async -> Bool {
        var requests = 0
        var changesPlan = false
        var changesCache = false
        var seen = Set<String>()
        for leg in legs {
            let legTransport = leg.transport ?? transport
            let key = TravelTimeCache.tripKey(from: leg.from, to: leg.to, transport: legTransport)
            if Task.isCancelled { break }
            guard seen.insert(key).inserted, cache.needsRefresh(forTrip: key, now: now()), !failedKeys.contains(key),
                  (retryAfter[key] ?? .distantPast) <= now() else { continue }
            guard requests < Self.requestsPerRun else { break }
            requests += 1
            let previous = cache.minutes(forTrip: key)
            let wasProvisional = provisionalKeys.contains(key)
            do {
                let from = try await located(leg.from, otherEnd: leg.to, home: home)
                let to = try await located(leg.to, otherEnd: leg.from, home: home)
                let minutes: Int
                switch leg.direction {
                case .toEvent:
                    minutes = try await estimator.minutes(from: from, to: to, transport: legTransport, arrival: leg.arrival)
                case .returnHome:
                    minutes = try await estimator.minutes(from: from, to: to, transport: legTransport, departure: leg.arrival)
                }
                guard TravelPlausibility.isPlausibleTravelTime(minutes: minutes) else { throw TravelTimeError.addressNotFound }
                cache.store(minutes: minutes, forTrip: key, now: now())
                provisionalKeys.remove(key)
                retryAfter[key] = nil
                changesCache = true
                if wasProvisional || previous != minutes { changesPlan = true }
            } catch {
                // A cancelled run says nothing about the trip: it is neither remembered as failed nor as not found.
                if error is CancellationError || Task.isCancelled { break }
                switch TravelFailure.classify(error) {
                case .offline:
                    retryAfter[key] = now().addingTimeInterval(Self.transientRetryInterval)
                    // A trip with an older value or a remembered "not found" keeps showing that; only a trip with no
                    // answer at all gets the provisional block.
                    if cache.entries[key] == nil, provisionalKeys.insert(key).inserted { changesPlan = true }
                case .notFound:
                    cache.storeRejected(forTrip: key, now: now())
                    provisionalKeys.remove(key)
                    retryAfter[key] = nil
                    changesCache = true
                    if wasProvisional || previous != nil { changesPlan = true }
                case .unresolvable:
                    failedKeys.insert(key)
                    if provisionalKeys.remove(key) != nil { changesPlan = true }
                }
            }
        }
        if changesCache { cache.save() }
        if changesPlan { revision += 1 }
        return changesPlan
    }

    /// Looks up an address for the settings (the home address). Nothing is cached here.
    func lookUp(address: String) async throws -> PlaceLookup {
        try await estimator.lookUp(address: address)
    }

    /// The place with coordinates: its own, the cached lookup, or a new lookup (cached on success). The place keeps
    /// its key, so the trip's cache entry does not depend on whether the lookup came from the cache.
    ///
    /// A free text is only looked up near a reference point (`TravelPlausibility.referencePoint`); a result outside the
    /// plausible distance, also one from an older cache, counts as not found. The failure is remembered per place and
    /// reference area, so the same text is checked again against a different reference.
    private func located(_ place: TravelPlace, otherEnd: TravelPlace, home: TravelPlace?) async throws -> TravelPlace {
        if place.latitude != nil, place.longitude != nil { return place }
        guard let reference = TravelPlausibility.referencePoint(home: home, otherEnd: otherEnd) else {
            throw TravelTimeError.noReferencePoint
        }
        let placeKey = TravelTimeCache.placeKey(place)
        let failureKey = "\(placeKey)@\(String(format: "%.1f,%.1f", reference.latitude, reference.longitude))"
        if failedKeys.contains(failureKey) { throw TravelTimeError.addressNotFound }
        var result = place
        if let known = cache.coordinates(forPlace: placeKey, now: now()) {
            let coordinate = TravelCoordinate(latitude: known.latitude, longitude: known.longitude)
            guard TravelPlausibility.isPlausibleLookup(coordinate, near: reference) else {
                failedKeys.insert(failureKey)
                throw TravelTimeError.addressNotFound
            }
            result.latitude = known.latitude
            result.longitude = known.longitude
            return result
        }
        do {
            let found = try await estimator.lookUp(address: place.text, near: reference)
            let coordinate = TravelCoordinate(latitude: found.latitude, longitude: found.longitude)
            guard TravelPlausibility.isPlausibleLookup(coordinate, near: reference) else { throw TravelTimeError.addressNotFound }
            cache.store(latitude: found.latitude, longitude: found.longitude, forPlace: placeKey, now: now())
            result.latitude = found.latitude
            result.longitude = found.longitude
            return result
        } catch {
            // A network failure is not a verdict on the place: it is looked up again later.
            if TravelFailure.classify(error) != .offline { failedKeys.insert(failureKey) }
            throw error
        }
    }
}
