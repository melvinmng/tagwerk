import Foundation
import Testing
@testable import TagwerkCore

struct FoodValueTests {
    private let german = Locale(identifier: "de_DE")

    private func skyr() -> FoodValue {
        FoodValue(name: "Skyr natur", reference: .per100g, kcal: 62, protein: 11, carbs: 4, fat: 0.2,
                  nutrients: NutrientValues(fiber: nil, sugar: 4, saturatedFat: 0.1, salt: 0.1))
    }

    // MARK: Portions

    @Test func portion_gramsToItem() {
        let item = skyr().item(amount: 250, locale: german)
        #expect(item.kcal == 155)
        #expect(item.protein == 27.5)
        #expect(item.carbs == 10)
        #expect(abs(item.fat - 0.5) < 0.0001)
        #expect(item.amount == "250 g")
        #expect(item.name == "Skyr natur")
        #expect(item.factor == 1, "the amount is already in the values")
    }

    @Test func portion_millilitres() {
        let milk = FoodValue(name: "Milch", reference: .per100ml, kcal: 47, protein: 3.4)
        let item = milk.item(amount: 200, locale: german)
        #expect(item.kcal == 94)
        #expect(abs(item.protein - 6.8) < 0.0001)
        #expect(item.amount == "200 ml")
    }

    @Test func portion_pieces() {
        let bar = FoodValue(name: "Proteinriegel", reference: .perPiece(grams: 45), kcal: 168, protein: 15)
        let item = bar.item(amount: 2, locale: german)
        #expect(item.kcal == 336)
        #expect(item.protein == 30)
        #expect(item.amount.hasPrefix("2 "))
    }

    @Test func portion_fractionalAmountKeepsOneDecimal() {
        #expect(skyr().amountText(12.5, locale: german) == "12,5 g")
        #expect(skyr().amountText(180, locale: german) == "180 g")
    }

    @Test func item_fromFood_isExact() {
        let item = skyr().item(amount: 180)
        #expect(item.kcalMin == item.kcal && item.kcal == item.kcalMax)
        #expect(!item.isEstimated)
    }

    @Test func item_unknownNutrientsStayUnknown() {
        let item = skyr().item(amount: 200)
        #expect(item.fiber == nil, "an unknown value is never turned into 0")
        #expect(item.sugar == 8)
        #expect(abs((item.saturatedFat ?? 0) - 0.2) < 0.0001)
        #expect(item.salt != nil)
    }

    @Test func item_missingMacrosBecomeZeroInTheItem() {
        let food = FoodValue(name: "Brühe", reference: .per100ml, kcal: 10)
        let item = food.item(amount: 250)
        #expect(item.protein == 0 && item.carbs == 0 && item.fat == 0, "an item holds numbers; Health never receives 0")
        #expect(item.kcal == 25)
    }

    // MARK: Taking over an item

    @Test func fromItem_keepsValuesWithQuantityFactor() {
        let item = MealItem(name: "Banane", amount: "1 Stück", factor: 2, kcalMin: 80, kcal: 100, kcalMax: 120, protein: 1, carbs: 25,
                            fat: 0.3, fiber: 2.5, isEstimated: true)
        let food = FoodValue.fromItem(item)
        #expect(food.kcal == 200 && food.protein == 2 && food.carbs == 50)
        #expect(food.nutrients.fiber == 5 && food.nutrients.sugar == nil)
        #expect(food.reference == .perPiece(grams: nil))
        #expect(food.origin == .estimate)
    }

    // MARK: Search

    @Test func search_matchesWordsCaseInsensitive() {
        let foods = [skyr(), FoodValue(name: "Haferflocken, zart", reference: .per100g, kcal: 372),
                     FoodValue(name: "Käse Müsli", reference: .per100g, kcal: 100)]
        #expect(FoodSearch.matching(foods, query: "SKYR").map(\.name) == ["Skyr natur"])
        #expect(FoodSearch.matching(foods, query: "natur skyr").map(\.name) == ["Skyr natur"], "word order does not matter")
        #expect(FoodSearch.matching(foods, query: "kase musli").map(\.name) == ["Käse Müsli"], "accents are ignored")
        #expect(FoodSearch.matching(foods, query: "flocken").count == 1)
        #expect(FoodSearch.matching(foods, query: "xyz").isEmpty)
    }

    @Test func search_emptyQueryReturnsAllSortedByName() {
        let foods = [FoodValue(name: "Zwieback", reference: .per100g, kcal: 400), FoodValue(name: "Apfel", reference: .per100g, kcal: 52)]
        #expect(FoodSearch.matching(foods, query: "  ").map(\.name) == ["Apfel", "Zwieback"])
    }

    @Test func search_prefixMatchesComeFirst() {
        let foods = [FoodValue(name: "Reis-Waffel", reference: .per100g, kcal: 380), FoodValue(name: "Waffel", reference: .per100g, kcal: 400)]
        #expect(FoodSearch.matching(foods, query: "waffel").map(\.name) == ["Waffel", "Reis-Waffel"])
    }

    // MARK: Coding

    @Test func codable_roundTripsEveryReference() throws {
        for reference in [FoodReference.per100g, .per100ml, .perPiece(grams: nil), .perPiece(grams: 45)] {
            let food = FoodValue(name: "X", reference: reference, kcal: 1, origin: .openFoodFacts, barcode: "4000000000000",
                                 sourceNote: "Quelle")
            let decoded = try JSONDecoder().decode(FoodValue.self, from: JSONEncoder().encode(food))
            #expect(decoded == food)
        }
    }

    @Test func reference_storageParts() {
        #expect(FoodReference(storageKind: "perPiece", pieceGrams: 45) == .perPiece(grams: 45))
        #expect(FoodReference(storageKind: "per100ml", pieceGrams: nil) == .per100ml)
        #expect(FoodReference(storageKind: "unknown", pieceGrams: nil) == .per100g)
        #expect(FoodReference.perPiece(grams: 45).storageKind == "perPiece")
    }

    @Test func validity() {
        #expect(skyr().isValid)
        #expect(!FoodValue(name: "  ", reference: .per100g, kcal: 10).isValid)
        #expect(!FoodValue(name: "X", reference: .per100g, kcal: -1).isValid)
        #expect(FoodValue(name: "Wasser", reference: .per100ml, kcal: 0).isValid)
    }

    @Test func gaps() {
        #expect(skyr().hasGaps, "fibre is missing")
        let complete = FoodValue(name: "X", reference: .per100g, kcal: 1, protein: 1, carbs: 1, fat: 1,
                                 nutrients: NutrientValues(fiber: 0, sugar: 0, saturatedFat: 0, salt: 0))
        #expect(!complete.hasGaps)
    }

    @Test func summary_nameReferenceAndValues() {
        #expect(skyr().summary(locale: german).contains("62"))
        #expect(skyr().summary(locale: german).contains("11"))
        let noProtein = FoodValue(name: "Wasser", reference: .per100ml, kcal: 0)
        #expect(!noProtein.summary(locale: german).contains("Eiweiß"))
    }
}
