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

    // MARK: Values the number fields round (the edit sheet)

    /// What a number field shows for a value and writes back when it appears.
    private func shown(_ value: Double) -> Double {
        Double(DecimalField.format(value).replacingOccurrences(of: ",", with: ".")) ?? value
    }

    private func product() -> FoodValue {
        FoodValue(name: "Skyr", reference: .per100g, kcal: 260 / 4.184, protein: 11.37, carbs: 4, fat: 0.2,
                  nutrients: NutrientValues(fiber: nil, sugar: 4, saturatedFat: 0.123, salt: 0.15), origin: .openFoodFacts,
                  barcode: "4000000000001", sourceNote: "Open Food Facts, abgerufen am 21.11.2026")
    }

    /// The fields of the sheet right after it opened: every value as the number field shows it.
    private func fieldsAfterOpening(_ food: FoodValue) -> FoodValue {
        var fields = food
        fields.kcal = shown(food.kcal)
        fields.protein = food.protein.map(shown)
        fields.carbs = food.carbs.map(shown)
        fields.fat = food.fat.map(shown)
        for nutrient in Nutrient.allCases { fields.nutrients[nutrient] = food.nutrients[nutrient].map(shown) }
        return fields
    }

    @Test func untouched_aValueTheFieldStillShowsIsTheOriginal() {
        #expect(FoodEditSheet.untouched(shown(239.006), original: 239.006) == 239.006)
        #expect(FoodEditSheet.untouched(shown(0.15), original: 0.15) == 0.15)
        #expect(FoodEditSheet.untouched(62, original: 62) == 62)
    }

    @Test func untouched_aTypedValueWins_andUnknownStaysUnknown() {
        #expect(FoodEditSheet.untouched(240, original: 239.006) == 240)
        #expect(FoodEditSheet.untouched(5, original: nil) == 5, "a value typed into a field that was unknown")
        #expect(FoodEditSheet.untouched(nil, original: 3) == nil, "a cleared field is unknown again")
        #expect(FoodEditSheet.untouched(nil, original: nil) == nil)
    }

    @Test func resolved_aProductOpenedAndSavedWithoutChange_keepsItsValuesAndItsSource() {
        let original = product()
        #expect(fieldsAfterOpening(original) != original, "the fields really do show rounded values")
        let result = FoodEditSheet.resolved(typed: fieldsAfterOpening(original), against: original, energyUnknown: false)
        #expect(result == original, "no rounding, and the entry still counts as the data of Open Food Facts")
        #expect(result.origin == .openFoodFacts && result.sourceNote == original.sourceNote)
    }

    @Test func resolved_oneTypedValue_changesOnlyThatValue_andEndsTheClaimOfTheThirdParty() {
        let original = product()
        var fields = fieldsAfterOpening(original)
        fields.kcal = 70
        let result = FoodEditSheet.resolved(typed: fields, against: original, energyUnknown: false)
        #expect(result.kcal == 70)
        #expect(result.protein == 11.37 && result.nutrients.salt == 0.15 && result.nutrients.saturatedFat == 0.123, "the other values stay exact")
        #expect(result.origin == .typed && result.sourceNote != original.sourceNote)
    }

    @Test func resolved_anOwnFoodEditedWithoutChange_isNotRounded() {
        let own = FoodValue(name: "Haferflocken", reference: .perPiece(grams: 33.333), kcal: 123.456, protein: 4.321, origin: .typed)
        var fields = fieldsAfterOpening(own)
        fields.reference = .perPiece(grams: shown(33.333))
        #expect(FoodEditSheet.resolved(typed: fields, against: own, energyUnknown: false) == own)
    }

    @Test func resolved_newFood_isTakenAsTyped() {
        let fresh = FoodValue(name: "Neu", reference: .per100g, kcal: 12.34)
        #expect(FoodEditSheet.resolved(typed: fresh, against: nil, energyUnknown: false) == fresh)
    }

    @Test func resolved_productWithoutEnergy_takesTheTypedEnergy() {
        let original = FoodValue(name: "Skyr", reference: .per100g, kcal: 0, protein: 9, origin: .openFoodFacts, sourceNote: "Open Food Facts")
        var fields = fieldsAfterOpening(original)
        fields.kcal = 55
        let result = FoodEditSheet.resolved(typed: fields, against: original, energyUnknown: true)
        #expect(result.kcal == 55 && result.protein == 9)
        #expect(result.origin == .typed, "the energy was filled in by the user")
    }
}
