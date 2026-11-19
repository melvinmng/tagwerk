import Foundation
import TagwerkCore
@testable import Tagwerk

/// Answers travel questions without MapKit: a fixed time per call, failures by place text, a switch for "no network"
/// and a call log.
final class FakeTravelEstimator: TravelTimeEstimating, @unchecked Sendable {
    private let lock = NSLock()
    private var _minutes = 25
    private var _failingTexts: Set<String> = []
    private var _isOffline = false
    private var _tripCalls: [String] = []
    private var _geocodeCalls: [String] = []
    private var _geocodeReferences: [TravelCoordinate?] = []
    private var _locations: [String: TravelCoordinate] = [:]

    var minutes: Int {
        get { lock.withLock { _minutes } }
        set { lock.withLock { _minutes = newValue } }
    }
    /// Every request fails like a request without network (`URLError.notConnectedToInternet`).
    var isOffline: Bool {
        get { lock.withLock { _isOffline } }
        set { lock.withLock { _isOffline = newValue } }
    }
    /// Place texts for which every request fails as "not found" (address unknown, no route).
    var failingTexts: Set<String> {
        get { lock.withLock { _failingTexts } }
        set { lock.withLock { _failingTexts = newValue } }
    }
    /// Where a place text is found; every other text is found in Berlin (52.5, 13.4).
    var locations: [String: TravelCoordinate] {
        get { lock.withLock { _locations } }
        set { lock.withLock { _locations = newValue } }
    }
    /// The reference point passed with each lookup, in the order of `geocodeCalls`.
    var geocodeReferences: [TravelCoordinate?] { lock.withLock { _geocodeReferences } }
    var tripCalls: [String] { lock.withLock { _tripCalls } }
    var geocodeCalls: [String] { lock.withLock { _geocodeCalls } }

    func lookUp(address: String, near: TravelCoordinate?) async throws -> PlaceLookup {
        lock.withLock {
            _geocodeCalls.append(address)
            _geocodeReferences.append(near)
        }
        if isOffline { throw URLError(.notConnectedToInternet) }
        if failingTexts.contains(address) { throw TravelTimeError.addressNotFound }
        let found = locations[address] ?? TravelCoordinate(latitude: 52.5, longitude: 13.4)
        return PlaceLookup(latitude: found.latitude, longitude: found.longitude, description: address)
    }

    func minutes(from: TravelPlace, to: TravelPlace, transport: TravelTransport, arrival: Date) async throws -> Int {
        lock.withLock { _tripCalls.append("\(from.text)>\(to.text)>\(transport.rawValue)") }
        if isOffline { throw URLError(.notConnectedToInternet) }
        if failingTexts.contains(from.text) || failingTexts.contains(to.text) { throw TravelTimeError.missingCoordinates }
        return minutes
    }
}
