import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct FoodStoreTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
    }

    private func makeStore() -> FoodStore { FoodStore(context: container.mainContext) }

    @Test func save_storesAndReadsEveryValue() {
        let store = makeStore()
        let food = FoodValue(name: "Haferflocken", reference: .per100g, kcal: 372, protein: 13.5, carbs: nil, fat: 7,
                             nutrients: NutrientValues(fiber: 10, sugar: nil, saturatedFat: 1.3, salt: 0.02),
                             origin: .label, barcode: "4000000000001", sourceNote: "Etikett")
        #expect(store.save(food))
        #expect(store.foods() == [food])
        #expect(store.food(food.id) == food)
    }

    @Test func save_sameIdentityReplaces() {
        let store = makeStore()
        var food = FoodValue(name: "Skyr", reference: .per100g, kcal: 62)
        store.save(food)
        food.kcal = 65
        food.name = "  Skyr natur  "
        store.save(food)
        #expect(store.foods().count == 1)
        #expect(store.foods().first?.kcal == 65)
        #expect(store.foods().first?.name == "Skyr natur", "the name is trimmed")
    }

    @Test func save_invalidFoodIsNotStored() {
        let store = makeStore()
        #expect(!store.save(FoodValue(name: "  ", reference: .per100g, kcal: 10)))
        #expect(!store.save(FoodValue(name: "X", reference: .per100g, kcal: -5)))
        #expect(store.isEmpty)
    }

    @Test func delete_removesOnlyThatFood() {
        let store = makeStore()
        let first = FoodValue(name: "A", reference: .per100g, kcal: 1)
        let second = FoodValue(name: "B", reference: .per100g, kcal: 2)
        store.save(first)
        store.save(second)
        store.delete(first.id)
        #expect(store.foods().map(\.name) == ["B"])
    }

    @Test func search_filtersByWordsAndSortsByName() {
        let store = makeStore()
        for name in ["Skyr Vanille", "Haferflocken", "Skyr natur"] {
            store.save(FoodValue(name: name, reference: .per100g, kcal: 50))
        }
        #expect(store.search("skyr").map(\.name) == ["Skyr natur", "Skyr Vanille"])
        #expect(store.search("").map(\.name) == ["Haferflocken", "Skyr natur", "Skyr Vanille"])
        #expect(store.search("natur skyr").map(\.name) == ["Skyr natur"])
    }

    @Test func foodsAreInTheSchema_andTheOpenFoodFactsOriginSurvives() {
        let store = makeStore()
        store.save(FoodValue(name: "Produkt", reference: .perPiece(grams: 30), kcal: 120, origin: .openFoodFacts,
                             sourceNote: "Open Food Facts, abgerufen am 21.11.2026"))
        let stored = store.foods().first
        #expect(stored?.origin == .openFoodFacts)
        #expect(stored?.reference == .perPiece(grams: 30))
        #expect(stored?.sourceNote == "Open Food Facts, abgerufen am 21.11.2026")
    }

    @Test func estimatedItem_saveAsFood_keepsValues() throws {
        let store = makeStore()
        let item = MealItem(name: "Müsliriegel", amount: "1 Stück", factor: 2, kcalMin: 160, kcal: 180, kcalMax: 200, protein: 3, carbs: 30,
                            fat: 5, fiber: 2, isEstimated: true)
        var food = FoodValue.fromItem(item)
        food.name = "Müsliriegel (Marke X)"
        #expect(store.save(food))
        let stored = try #require(store.foods().first)
        #expect(stored.kcal == 360 && stored.protein == 6 && stored.carbs == 60 && stored.fat == 10)
        #expect(stored.nutrients.fiber == 4 && stored.nutrients.sugar == nil)
        #expect(stored.origin == .estimate)
        // One piece of the saved food gives back the values the meal showed.
        let again = stored.item(amount: 1)
        #expect(again.kcal == 360 && !again.isEstimated)
    }
}
