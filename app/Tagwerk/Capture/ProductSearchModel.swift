import Foundation
import Observation
import TagwerkCore

/// The state of the online search sheet. Nothing is sent while the user types: a request starts only with `submit()` or `loadMore()`,
/// which the screen calls on a tap (or on the return key) and once when the sheet opens from the tap on "Online suchen".
@MainActor
@Observable
final class ProductSearchModel {
    enum Phase: Equatable {
        case idle
        case loading
        case results
        case empty
        case failed(String)
    }

    var query: String
    private(set) var phase: Phase = .idle
    /// The hits of all pages loaded so far.
    private(set) var candidates: [ProductCandidate] = []
    private(set) var hasMore = false
    @ObservationIgnored private var loadedPages = 0
    @ObservationIgnored private var lastQuery = ""
    @ObservationIgnored private let lookup: any ProductLookingUp
    @ObservationIgnored private let isOnline: () -> Bool

    init(query: String, lookup: any ProductLookingUp, isOnline: @escaping () -> Bool) {
        self.query = query
        self.lookup = lookup
        self.isOnline = isOnline
    }

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Why a search can not start now: too few characters or no connection. `nil` when it can.
    var blocker: ProductLookupError? {
        if !isOnline() { return .offline }
        if trimmedQuery.count < ProductSearchRules.minimumQueryLength { return .queryTooShort }
        return nil
    }

    var canSubmit: Bool { blocker == nil && phase != .loading }

    /// Searches for the words in `query` (page 1). The only way a search starts, besides `loadMore()`.
    func submit() async {
        guard canSubmit else { return }
        lastQuery = trimmedQuery
        loadedPages = 0
        candidates = []
        hasMore = false
        await load(page: 1)
    }

    /// The next page of the same words, a request of its own.
    func loadMore() async {
        guard hasMore, phase != .loading, isOnline() else { return }
        await load(page: loadedPages + 1)
    }

    private func load(page: Int) async {
        phase = .loading
        do {
            let result = try await lookup.search(lastQuery, page: page)
            loadedPages = page
            let known = Set(candidates.map(\.id))
            candidates += result.candidates.filter { !known.contains($0.id) }
            hasMore = result.hasMore
            phase = candidates.isEmpty ? .empty : .results
        } catch is CancellationError {
            phase = candidates.isEmpty ? .idle : .results
        } catch let error as ProductLookupError {
            phase = .failed(error.message)
        } catch {
            phase = .failed(ProductLookupError.failed.message)
        }
    }
}

/// What the preview of a product offers.
struct ProductPreviewModel {
    let candidate: ProductCandidate
    let isSignedIn: Bool

    /// Values are missing: the preview says so, and the label photo is offered as a way to fill the gaps (it needs the ChatGPT sign-in).
    var offersLabelPhoto: Bool { candidate.isIncomplete && isSignedIn }

    /// The edit sheet for taking the product over: a new food with the values, the barcode and the source note.
    func takeOverSeed(retrievedOn date: Date) -> FoodEditSheet.Seed {
        FoodEditSheet.Seed(food: candidate.food(retrievedOn: date), energyUnknown: candidate.energyUnknown)
    }

    /// The same, with the camera open to read the label instead of the incomplete values.
    func labelPhotoSeed(retrievedOn date: Date) -> FoodEditSheet.Seed {
        var seed = takeOverSeed(retrievedOn: date)
        seed.startsWithLabelPhoto = true
        return seed
    }
}
