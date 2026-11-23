import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// A lookup that records its calls and answers from a script; no network, no consent logic (that is `ProductLookup`'s job).
@MainActor
private final class FakeLookup: ProductLookingUp {
    private(set) var searches: [(query: String, page: Int)] = []
    private(set) var cleared = 0
    var pages: [ProductPage] = []
    var error: ProductLookupError?

    func search(_ query: String, page: Int) async throws -> ProductPage {
        searches.append((query, page))
        if let error { throw error }
        return pages.isEmpty ? ProductPage(candidates: [], page: page, total: 0, hasMore: false) : pages.removeFirst()
    }

    func product(barcode: String) async throws -> ProductCandidate? { nil }
    func clearMemory() { cleared += 1 }
}

@MainActor
struct ProductSearchModelTests {
    private func candidate(_ name: String, code: String, kcal: Double? = 62) -> ProductCandidate {
        let food = FoodValue(name: name, reference: .per100g, kcal: kcal ?? 0, protein: kcal == nil ? nil : 11, carbs: kcal == nil ? nil : 4,
                             fat: kcal == nil ? nil : 0.2, origin: .openFoodFacts, barcode: code)
        return ProductCandidate(barcode: code, name: name, brand: nil, quantity: nil, food: food, energyUnknown: kcal == nil, valuesPerServingOnly: false)
    }

    private func make(_ lookup: FakeLookup, query: String = "", online: Bool = true) -> ProductSearchModel {
        ProductSearchModel(query: query, lookup: lookup, isOnline: { online })
    }

    @Test func search_startsOnlyOnTap_notWhileTyping() async {
        let lookup = FakeLookup()
        let model = make(lookup)
        for text in ["s", "sk", "sky", "skyr", "skyr n"] { model.query = text }
        #expect(lookup.searches.isEmpty, "typing sends nothing")
        #expect(model.phase == .idle)
        await model.submit()
        #expect(lookup.searches.count == 1 && lookup.searches.first?.query == "skyr n")
    }

    @Test func search_minimumThreeCharacters() async {
        let lookup = FakeLookup()
        let model = make(lookup, query: " sk ")
        #expect(!model.canSubmit && model.blocker == .queryTooShort)
        await model.submit()
        #expect(lookup.searches.isEmpty)
        model.query = "sky"
        #expect(model.canSubmit && model.blocker == nil)
    }

    @Test func search_noNetwork_buttonDisabledWithHint() async {
        let lookup = FakeLookup()
        let model = make(lookup, query: "skyr", online: false)
        #expect(!model.canSubmit)
        #expect(model.blocker == .offline && model.blocker?.message == "Keine Verbindung")
        await model.submit()
        #expect(lookup.searches.isEmpty)
    }

    @Test func search_showsHits_andAnEmptyAnswer() async {
        let lookup = FakeLookup()
        lookup.pages = [ProductPage(candidates: [candidate("A", code: "1"), candidate("B", code: "2", kcal: nil)], page: 1, total: 2, hasMore: false)]
        let model = make(lookup, query: "skyr")
        await model.submit()
        #expect(model.phase == .results && model.candidates.map(\.name) == ["A", "B"] && !model.hasMore)
        await model.submit()
        #expect(model.phase == .empty && model.candidates.isEmpty)
    }

    @Test func loadMore_isATapOfItsOwn_andAppendsWithoutDuplicates() async {
        let lookup = FakeLookup()
        lookup.pages = [ProductPage(candidates: [candidate("A", code: "1")], page: 1, total: 3, hasMore: true),
                        ProductPage(candidates: [candidate("A", code: "1"), candidate("B", code: "2")], page: 2, total: 3, hasMore: false)]
        let model = make(lookup, query: "skyr")
        await model.submit()
        #expect(model.hasMore && lookup.searches.count == 1, "the next page is not loaded by itself")
        await model.loadMore()
        #expect(lookup.searches.map(\.page) == [1, 2])
        #expect(model.candidates.map(\.id) == ["1", "2"] && !model.hasMore)
        await model.loadMore()
        #expect(lookup.searches.count == 2, "nothing more to load")
    }

    @Test func failure_isShownWithItsMessage() async {
        let lookup = FakeLookup()
        lookup.error = .rateLimited(wait: 42)
        let model = make(lookup, query: "skyr")
        await model.submit()
        #expect(model.phase == .failed(ProductLookupError.rateLimited(wait: 42).message))
        #expect(model.candidates.isEmpty)
    }

    @Test func newSearch_replacesTheOldHits() async {
        let lookup = FakeLookup()
        lookup.pages = [ProductPage(candidates: [candidate("A", code: "1")], page: 1, total: 1, hasMore: false),
                        ProductPage(candidates: [candidate("B", code: "2")], page: 1, total: 1, hasMore: false)]
        let model = make(lookup, query: "skyr")
        await model.submit()
        model.query = "quark"
        await model.submit()
        #expect(model.candidates.map(\.name) == ["B"])
    }

    // MARK: Preview

    @Test func preview_incompleteValues_offerLabelPhoto() {
        let incomplete = candidate("Skyr", code: "1", kcal: nil)
        #expect(ProductPreviewModel(candidate: incomplete, isSignedIn: true).offersLabelPhoto)
        #expect(!ProductPreviewModel(candidate: incomplete, isSignedIn: false).offersLabelPhoto, "reading a label needs the ChatGPT sign-in")
        #expect(!ProductPreviewModel(candidate: candidate("Skyr", code: "1"), isSignedIn: true).offersLabelPhoto, "complete values need no photo")
    }

    @Test func preview_takeOver_isANewFoodWithTheSourceNote_andNotYetSaved() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = FoodStore(context: container.mainContext)
        let product = candidate("Skyr", code: "4000000000001")
        let seed = ProductPreviewModel(candidate: product, isSignedIn: false).takeOverSeed(retrievedOn: Date(timeIntervalSince1970: 1_795_262_400))
        #expect(store.isEmpty, "showing the preview saves nothing")
        let food = try #require(seed.food)
        #expect(!seed.isExisting && !seed.energyUnknown && !seed.startsWithLabelPhoto)
        #expect(food.origin == .openFoodFacts && food.barcode == "4000000000001")
        #expect(food.sourceNote?.hasPrefix("Open Food Facts") == true)
        // The sheet saves what it holds; here the same step by hand.
        #expect(store.save(food))
        let stored = try #require(store.foods().first)
        #expect(stored.origin == .openFoodFacts && stored.sourceNote == food.sourceNote && stored.barcode == "4000000000001")
        #expect(stored.id != product.food.id, "an own entry, separate from the hit")
    }

    @Test func preview_energyUnknown_startsWithAnEmptyEnergyField() {
        let seed = ProductPreviewModel(candidate: candidate("Skyr", code: "1", kcal: nil), isSignedIn: true).takeOverSeed(retrievedOn: Date())
        #expect(seed.energyUnknown)
        #expect(ProductPreviewModel(candidate: candidate("Skyr", code: "1", kcal: nil), isSignedIn: true).labelPhotoSeed(retrievedOn: Date()).startsWithLabelPhoto)
    }
}
