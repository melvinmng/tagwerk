import Foundation
@testable import Tagwerk

/// Answers address completion without MapKit: fixed suggestions per query, an optional gate per query (to let an earlier
/// request finish after a later one, without any timing), the places the suggestions resolve to and a call log.
final class FakeAddressSuggester: AddressSuggesting, @unchecked Sendable {
    private let lock = NSLock()
    private var _answers: [String: [AddressSuggestion]] = [:]
    private var _gates: [String: Gate] = [:]
    private var _places: [String: PlaceLookup] = [:]
    private var _calls: [String] = []
    private var _failsToResolve = false

    var answers: [String: [AddressSuggestion]] {
        get { lock.withLock { _answers } }
        set { lock.withLock { _answers = newValue } }
    }
    /// A request for the query waits at its gate until the test opens it.
    var gates: [String: Gate] {
        get { lock.withLock { _gates } }
        set { lock.withLock { _gates = newValue } }
    }
    /// Suggestion ID → what it resolves to.
    var places: [String: PlaceLookup] {
        get { lock.withLock { _places } }
        set { lock.withLock { _places = newValue } }
    }
    var failsToResolve: Bool {
        get { lock.withLock { _failsToResolve } }
        set { lock.withLock { _failsToResolve = newValue } }
    }
    var calls: [String] { lock.withLock { _calls } }

    func suggestions(for query: String) async -> [AddressSuggestion] {
        lock.withLock { _calls.append(query) }
        if let gate = gates[query] { await gate.wait() }
        return answers[query] ?? []
    }

    func resolve(_ suggestion: AddressSuggestion) async throws -> PlaceLookup {
        if failsToResolve { throw TravelTimeError.addressNotFound }
        guard let place = places[suggestion.id] else { throw TravelTimeError.addressNotFound }
        return place
    }
}
