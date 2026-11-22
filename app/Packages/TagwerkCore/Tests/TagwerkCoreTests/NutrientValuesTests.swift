import Foundation
import Testing
@testable import TagwerkCore

struct NutrientValuesTests {
    private func item(_ name: String = "Posten", kcal: Double = 100, factor: Double = 1, fiber: Double? = nil, sugar: Double? = nil,
                      saturatedFat: Double? = nil, salt: Double? = nil) -> MealItem {
        MealItem(name: name, amount: "1 Portion", factor: factor, kcalMin: kcal, kcal: kcal, kcalMax: kcal, protein: 0, carbs: 0,
                 fat: 0, fiber: fiber, sugar: sugar, saturatedFat: saturatedFat, salt: salt)
    }

    private func meal(_ items: [MealItem]) -> MealValue {
        MealValue(id: UUID(), date: Date(timeIntervalSince1970: 0), kind: .lunch, title: "Essen", items: items, origin: .manual)
    }

    // MARK: Items

    @Test func mealItem_decodesOldJSONWithoutNewFields() throws {
        let json = """
        {"name":"Brot","amount":"1 Scheibe","factor":2,"kcalMin":80,"kcal":90,"kcalMax":100,"protein":3,"carbs":15,"fat":1}
        """
        let decoded = try JSONDecoder().decode(MealItem.self, from: Data(json.utf8))
        #expect(decoded.fiber == nil && decoded.sugar == nil && decoded.saturatedFat == nil && decoded.salt == nil)
        #expect(!decoded.nutrients.hasAny)
    }

    @Test func mealItem_encodeDecodeRoundTripKeepsFurtherNutrients() throws {
        let original = item(fiber: 3.5, sugar: 0, saturatedFat: nil, salt: 1.2)
        let decoded = try JSONDecoder().decode(MealItem.self, from: JSONEncoder().encode(original))
        #expect(decoded.fiber == 3.5)
        #expect(decoded.sugar == 0)
        #expect(decoded.saturatedFat == nil)
        #expect(decoded.salt == 1.2)
    }

    @Test func mealItem_unknownIsNotWrittenAsZero() throws {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item(fiber: 2))) as? [String: Any]
        #expect(object?["fiber"] as? Double == 2)
        #expect(object?["sugar"] == nil)
    }

    @Test func overridden_keepsFurtherNutrients() {
        let typed = item(fiber: 4, sugar: 7, saturatedFat: 2, salt: 0.5).overridden(kcal: 300, protein: 10, carbs: 20, fat: 5)
        #expect(typed.kcal == 300)
        #expect(typed.fiber == 4 && typed.sugar == 7 && typed.saturatedFat == 2 && typed.salt == 0.5)
    }

    @Test func scaled_keepsUnknown() {
        let scaled = NutrientValues(fiber: 2, sugar: nil, saturatedFat: 0, salt: 1).scaled(by: 1.5)
        #expect(scaled.fiber == 3)
        #expect(scaled.sugar == nil)
        #expect(scaled.saturatedFat == 0)
        #expect(scaled.salt == 1.5)
    }

    @Test func totalNutrient_appliesFactor_andKeepsUnknown() {
        let value = item(factor: 2, fiber: 3)
        #expect(value.totalNutrient(.fiber) == 6)
        #expect(value.totalNutrient(.sugar) == nil)
    }

    @Test func salt_fromSodium() {
        #expect(NutrientValues.salt(fromSodiumGrams: 0.4) == 1.0)
        #expect(NutrientValues.sodiumGrams(fromSalt: 2.5) == 1.0)
    }

    // MARK: Sums

    @Test func sum_ignoresUnknownAndCountsCoverage() {
        let meals = [meal([item(fiber: 5)]), meal([item(fiber: 9)]), meal([item()])]
        let sum = IntakeRules.nutrientSum(.fiber, of: meals)
        #expect(sum == NutrientSum(value: 14, known: 2, total: 3))
        #expect(!sum.isComplete)
    }

    @Test func sum_allUnknown_isNil() {
        let sum = IntakeRules.nutrientSum(.sugar, of: [meal([item(fiber: 5)]), meal([item()])])
        #expect(sum.value == nil)
        #expect(sum.known == 0 && sum.total == 2)
        #expect(!sum.isComplete)
    }

    @Test func sum_knownZeroIsAValue() {
        let sum = IntakeRules.nutrientSum(.sugar, of: [meal([item(sugar: 0)])])
        #expect(sum == NutrientSum(value: 0, known: 1, total: 1))
        #expect(sum.isComplete)
    }

    @Test func sum_partiallyKnownMeal_countsValueButNotCoverage() {
        // One item knows its fibre, the other does not: the meal adds a lower bound but is not fully known.
        let partial = meal([item("A", fiber: 3), item("B")])
        let sum = IntakeRules.nutrientSum(.fiber, of: [partial])
        #expect(sum == NutrientSum(value: 3, known: 0, total: 1))
        #expect(!sum.isComplete)
    }

    @Test func sum_scalesWithFactor() {
        let sum = IntakeRules.nutrientSum(.fiber, of: [meal([item(factor: 2, fiber: 3), item(fiber: 1)])])
        #expect(sum == NutrientSum(value: 7, known: 1, total: 1))
    }

    @Test func sum_noMeals_isEmpty() {
        #expect(IntakeRules.nutrientSum(.fiber, of: []) == .empty)
    }

    @Test func dayIntake_carriesTheSumsOfAllFurtherNutrients() {
        let intake = IntakeRules.dayIntake(meals: [meal([item(fiber: 5, salt: 1)]), meal([item(fiber: 2)])], drinks: [])
        #expect(intake.fiber == NutrientSum(value: 7, known: 2, total: 2))
        #expect(intake.salt == NutrientSum(value: 1, known: 1, total: 2))
        #expect(intake.sugar.value == nil)
        #expect(intake[.saturatedFat] == NutrientSum(value: nil, known: 0, total: 2))
    }

    @Test func dayIntake_oldInitializerStillWorks() {
        let intake = DayIntake(kcal: 1, kcalMin: 1, kcalMax: 1, protein: 0, carbs: 0, fat: 0, waterMilliliters: 0, hasEstimate: false)
        #expect(intake.fiber == .empty)
    }

    // MARK: Format

    @Test func format_minimumWithCoverage() {
        let sum = NutrientSum(value: 14, known: 2, total: 3)
        #expect(IntakeFormat.nutrient(.fiber, sum: sum) == "mind. 14 g · 2 von 3 Mahlzeiten")
        #expect(IntakeFormat.nutrient(.fiber, sum: sum, goal: 30) == "mind. 14 / 30 g · 2 von 3 Mahlzeiten")
    }

    @Test func format_completeAndUnknown() {
        #expect(IntakeFormat.nutrient(.fiber, sum: NutrientSum(value: 14, known: 3, total: 3)) == "14 g")
        #expect(IntakeFormat.nutrient(.sugar, sum: NutrientSum(value: 40, known: 2, total: 2), goal: 50) == "40 / 50 g")
        #expect(IntakeFormat.nutrient(.sugar, sum: NutrientSum(value: nil, known: 0, total: 2)) == "–")
        #expect(IntakeFormat.nutrient(.sugar, sum: .empty) == "–")
    }

    @Test func format_partialSingleMeal_hasNoCoverageText() {
        #expect(IntakeFormat.nutrient(.fiber, sum: NutrientSum(value: 3, known: 0, total: 1)) == "mind. 3 g")
    }

    @Test func format_saltShowsOneDecimal() {
        #expect(IntakeFormat.nutrient(.salt, sum: NutrientSum(value: 4.26, known: 2, total: 2), goal: 6) == "4,3 / 6,0 g")
    }
}
