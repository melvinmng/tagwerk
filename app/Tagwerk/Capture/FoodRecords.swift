import Foundation
import SwiftData
import TagwerkCore

// "Meine Lebensmittel": foods with values per 100 g, per 100 ml or per piece. Products found in Open Food Facts are never
// stored as such; only a product the user takes over becomes a food (with `originRaw == "openFoodFacts"` and a source note).
// Schema rule: later attributes must be optional or have a default value.

@Model
final class FoodRecord {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    /// `FoodReference.storageKind`: "per100g", "per100ml" or "perPiece".
    var referenceRaw: String = "per100g"
    /// Weight of one piece when the reference is "perPiece" and the weight is known.
    var pieceGrams: Double?
    var kcal: Double = 0
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var fiber: Double?
    var sugar: Double?
    var saturatedFat: Double?
    var salt: Double?
    var originRaw: String = FoodOrigin.typed.rawValue
    var barcode: String?
    var sourceNote: String?
    var createdAt: Date = Date(timeIntervalSince1970: 0)

    init(_ value: FoodValue, createdAt: Date = Date()) {
        id = value.id
        self.createdAt = createdAt
        apply(value)
    }

    var value: FoodValue {
        FoodValue(id: id, name: name, reference: FoodReference(storageKind: referenceRaw, pieceGrams: pieceGrams), kcal: kcal,
                  protein: protein, carbs: carbs, fat: fat,
                  nutrients: NutrientValues(fiber: fiber, sugar: sugar, saturatedFat: saturatedFat, salt: salt),
                  origin: FoodOrigin(rawValue: originRaw) ?? .typed, barcode: barcode, sourceNote: sourceNote)
    }

    /// Overwrites every value except the identity and the creation date.
    func apply(_ value: FoodValue) {
        name = value.name
        referenceRaw = value.reference.storageKind
        pieceGrams = value.reference.pieceGrams
        kcal = value.kcal
        protein = value.protein
        carbs = value.carbs
        fat = value.fat
        fiber = value.nutrients.fiber
        sugar = value.nutrients.sugar
        saturatedFat = value.nutrients.saturatedFat
        salt = value.nutrients.salt
        originRaw = value.origin.rawValue
        barcode = value.barcode
        sourceNote = value.sourceNote
    }
}
