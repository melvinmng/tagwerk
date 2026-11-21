import Foundation
import MapKit
import Observation
import TagwerkCore

/// One suggestion while typing an address ("Musterstraße 1" / "10115 Berlin").
struct AddressSuggestion: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String

    /// The address as one text: the title, then the postcode and city.
    var text: String { [title, subtitle].filter { !$0.isEmpty }.joined(separator: ", ") }
}

/// Address completion while typing; MapKit in the app, a fixed list in the simulator demo and in tests. The typed
/// fragments go to Apple Maps (the page "Mehr dazu" says so).
protocol AddressSuggesting: Sendable {
    func suggestions(for query: String) async -> [AddressSuggestion]
    func resolve(_ suggestion: AddressSuggestion) async throws -> PlaceLookup
}

/// The home address in the settings (PL12b): a search field with suggestions. A chosen suggestion is stored with its
/// coordinates and the plan reloads; without suggestions the typed text can still be checked the way it was before.
@MainActor
@Observable
final class HomeAddressModel {
    enum Status: Equatable {
        case idle, searching, noSuggestions
        /// The address was stored; the text is how Apple Maps writes it.
        case saved(String)
        /// The chosen or typed address was not found.
        case failed
    }

    /// The text in the search field.
    var query: String
    private(set) var suggestions: [AddressSuggestion] = []
    private(set) var status: Status

    /// Fewer characters ask nothing: short fragments only return noise and cost requests.
    nonisolated static let minimumQueryLength = 3

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let suggester: any AddressSuggesting
    @ObservationIgnored private let lookUp: (String) async throws -> PlaceLookup
    @ObservationIgnored private let reload: () async -> Void
    @ObservationIgnored private let debounce: Duration
    /// Counts the requests; an answer of an earlier one is dropped.
    @ObservationIgnored private var generation = 0

    init(settings: AppSettings, suggester: any AddressSuggesting, lookUp: @escaping (String) async throws -> PlaceLookup,
         reload: @escaping () async -> Void, debounce: Duration = .milliseconds(300)) {
        self.settings = settings
        self.suggester = suggester
        self.lookUp = lookUp
        self.reload = reload
        self.debounce = debounce
        let stored = settings.homeAddress ?? ""
        query = stored
        status = !stored.isEmpty && settings.homeLatitude != nil ? .saved(stored) : .idle
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Called when the field changes: waits for the debounce, then asks for suggestions. A later change makes an
    /// earlier request give up, also while it waits for its answer.
    func queryChanged() async {
        generation += 1
        let mine = generation
        let text = trimmedQuery
        // The text of the stored address (set by a choice) is no new search.
        guard text.count >= Self.minimumQueryLength, text != settings.homeAddress else {
            suggestions = []
            if case .saved = status {} else { status = .idle }
            return
        }
        status = .searching
        try? await Task.sleep(for: debounce)
        guard mine == generation else { return }
        let found = await suggester.suggestions(for: text)
        guard mine == generation else { return }
        suggestions = found
        status = found.isEmpty ? .noSuggestions : .idle
    }

    /// Stores the chosen suggestion with its coordinates and reloads the plan.
    func choose(_ suggestion: AddressSuggestion) async {
        generation += 1
        let mine = generation
        status = .searching
        do {
            let found = try await suggester.resolve(suggestion)
            guard mine == generation else { return }
            store(suggestion.text, found)
            suggestions = []
            status = .saved(found.description.isEmpty ? suggestion.text : found.description)
            await reload()
        } catch {
            guard mine == generation else { return }
            status = .failed
        }
    }

    /// The typed text, checked with Apple Maps as a whole (offered when there are no suggestions); an empty field removes
    /// the address. A text that is not found is not stored.
    func checkTypedAddress() async {
        generation += 1
        let mine = generation
        let text = trimmedQuery
        guard !text.isEmpty else {
            await clear()
            return
        }
        status = .searching
        do {
            let found = try await lookUp(text)
            guard mine == generation else { return }
            store(text, found)
            suggestions = []
            status = .saved(found.description)
            await reload()
        } catch {
            guard mine == generation else { return }
            status = .failed
        }
    }

    /// Removes the home address.
    func clear() async {
        generation += 1
        settings.homeAddress = nil
        settings.homeLatitude = nil
        settings.homeLongitude = nil
        query = ""
        suggestions = []
        status = .idle
        await reload()
    }

    private func store(_ text: String, _ found: PlaceLookup) {
        settings.homeAddress = text
        settings.homeLatitude = found.latitude
        settings.homeLongitude = found.longitude
        query = text
    }
}

/// Address completion through MapKit (`MKLocalSearchCompleter`, `MKLocalSearch`). Needs no location permission. A chosen
/// suggestion is resolved with a search for its text (street, postcode and city), which finds the address exactly.
@MainActor
final class MapKitAddressSuggester: AddressSuggesting {
    func suggestions(for query: String) async -> [AddressSuggestion] {
        await CompleterRequest().complete(query)
    }

    func resolve(_ suggestion: AddressSuggestion) async throws -> PlaceLookup {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = suggestion.text
        request.resultTypes = .address
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else { throw TravelTimeError.addressNotFound }
        let coordinate = item.location.coordinate
        return PlaceLookup(latitude: coordinate.latitude, longitude: coordinate.longitude,
                           description: item.address?.fullAddress ?? item.name ?? suggestion.text)
    }
}

/// One completer request: sets the fragment and waits for the first answer (or a failure, or a time limit).
@MainActor
private final class CompleterRequest: NSObject, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private var continuation: CheckedContinuation<[AddressSuggestion], Never>?

    func complete(_ query: String) async -> [AddressSuggestion] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            completer.delegate = self
            completer.resultTypes = .address
            completer.queryFragment = query
            // A completer without an answer must not hold the request forever.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.finish([])
            }
        }
    }

    private func finish(_ results: [AddressSuggestion]) {
        continuation?.resume(returning: results)
        continuation = nil
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results.map { AddressSuggestion(id: "\($0.title)|\($0.subtitle)", title: $0.title, subtitle: $0.subtitle) }
        Task { @MainActor in finish(results) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        Task { @MainActor in finish([]) }
    }
}
