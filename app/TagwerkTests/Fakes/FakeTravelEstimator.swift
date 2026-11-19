import Foundation
import TagwerkCore
@testable import Tagwerk

/// Answers travel questions without MapKit: a fixed time per call, failures by place text, and a call log.
final class FakeTravelEstimator: TravelTimeEstimating, @unchecked Sendable {
    private let lock = NSLock()
    private var _minutes = 25
    private var _failingTexts: Set<String> = []
    private var _tripCalls: [String] = []
    private var _geocodeCalls: [String] = []

    var minutes: Int {
        get { lock.withLock { _minutes } }
        set { lock.withLock { _minutes = newValue } }
    }
    /// Place texts for which every request fails (no network, address unknown).
    var failingTexts: Set<String> {
        get { lock.withLock { _failingTexts } }
        set { lock.withLock { _failingTexts = newValue } }
    }
    var tripCalls: [String] { lock.withLock { _tripCalls } }
    var geocodeCalls: [String] { lock.withLock { _geocodeCalls } }

    func coordinates(for place: TravelPlace) async throws -> (latitude: Double, longitude: Double) {
        lock.withLock { _geocodeCalls.append(place.text) }
        if failingTexts.contains(place.text) { throw TravelTimeError.addressNotFound }
        return (52.5, 13.4)
    }

    func minutes(from: TravelPlace, to: TravelPlace, transport: TravelTransport, arrival: Date) async throws -> Int {
        lock.withLock { _tripCalls.append("\(from.text)>\(to.text)>\(transport.rawValue)") }
        if failingTexts.contains(from.text) || failingTexts.contains(to.text) { throw TravelTimeError.missingCoordinates }
        return minutes
    }
}
