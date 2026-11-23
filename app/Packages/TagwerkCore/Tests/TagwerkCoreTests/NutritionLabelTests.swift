import Foundation
import Testing
@testable import TagwerkCore

struct NutritionLabelTests {
    private func json(table: Bool = true, name: String? = "\"Skyr\"", basis: String = "per_100g", serving: String = "null",
                      kcal: String = "62", kj: String = "null", protein: String = "11", carbs: String = "4", fat: String = "0.2",
                      fiber: String = "null", sugar: String = "4", saturated: String = "0.1", salt: String = "0.1") -> Data {
        Data("""
        {"table_found":\(table),"product_name":\(name ?? "null"),"basis":"\(basis)","serving_grams":\(serving),"kcal":\(kcal),"kj":\(kj),\
        "protein_g":\(protein),"carbs_g":\(carbs),"fat_g":\(fat),"fiber_g":\(fiber),"sugar_g":\(sugar),"saturated_fat_g":\(saturated),\
        "salt_g":\(salt)}
        """.utf8)
    }

    private func reading(_ data: Data) throws -> NutritionLabelReading? { try NutritionLabelOutput.decode(data).normalized() }

    @Test func nullFieldsStayUnknown() throws {
        let result = try #require(try reading(json()))
        #expect(result.food.nutrients.fiber == nil, "no fibre on the label: unknown, not 0")
        #expect(result.food.nutrients.sugar == 4)
        #expect(result.food.kcal == 62 && !result.energyUnknown)
        #expect(result.food.origin == .label && result.food.reference == .per100g)
    }

    @Test func statedZeroStaysZero() throws {
        let result = try #require(try reading(json(fiber: "0")))
        #expect(result.food.nutrients.fiber == 0)
    }

    @Test func noTable_readsNothing() throws {
        #expect(try reading(json(table: false)) == nil)
        let empty = json(table: true, kcal: "null", protein: "null", carbs: "null", fat: "null", sugar: "null", saturated: "null", salt: "null")
        #expect(try reading(empty) == nil, "a table without a single value is nothing recognized")
    }

    @Test func kilojoulesOnly_convertsToKcal() throws {
        let result = try #require(try reading(json(kcal: "null", kj: "1046")))
        #expect(abs(result.food.kcal - 250) < 0.01)
        #expect(!result.energyUnknown)
    }

    @Test func kcalWinsOverKilojoules() throws {
        let result = try #require(try reading(json(kcal: "250", kj: "1046")))
        #expect(result.food.kcal == 250)
    }

    @Test func missingEnergy_isMarkedUnknown() throws {
        let result = try #require(try reading(json(kcal: "null", kj: "null")))
        #expect(result.energyUnknown)
        #expect(result.food.protein == 11)
    }

    @Test func absurdValuesAreDropped() throws {
        let result = try #require(try reading(json(kcal: "5200", protein: "-3", fat: "140")))
        #expect(result.energyUnknown, "5200 kcal per 100 g is not a food")
        #expect(result.food.protein == nil && result.food.fat == nil)
        #expect(result.food.carbs == 4)
    }

    @Test func perServing_becomesAPieceWithItsWeight() throws {
        let result = try #require(try reading(json(basis: "per_serving", serving: "45", kcal: "168")))
        #expect(result.food.reference == .perPiece(grams: 45))
        #expect(result.food.kcal == 168)
    }

    @Test func perServing_withoutWeight() throws {
        let result = try #require(try reading(json(basis: "per_serving", serving: "null", kcal: "168")))
        #expect(result.food.reference == .perPiece(grams: nil))
    }

    @Test func per100ml() throws {
        let result = try #require(try reading(json(basis: "per_100ml", kcal: "47")))
        #expect(result.food.reference == .per100ml)
    }

    @Test func productNameIsTrimmed_andMayBeMissing() throws {
        let trimmed = try #require(try reading(json(name: "\"  Skyr natur \"")))
        #expect(trimmed.food.name == "Skyr natur")
        let missing = try #require(try reading(json(name: nil)))
        #expect(missing.food.name == "")
    }

    @Test func strictFormat_aMissingKeyIsAnInvalidAnswer() {
        let incomplete = Data(#"{"table_found":true,"basis":"per_100g","kcal":62}"#.utf8)
        #expect(throws: DecodingError.self) { try NutritionLabelOutput.decode(incomplete) }
        let unknownBasis = json(basis: "per_bottle")
        #expect(throws: DecodingError.self) { try NutritionLabelOutput.decode(unknownBasis) }
    }
}
