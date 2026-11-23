import Foundation

/// The answer of the model to a photo of a nutrition table, in the strict format of the request (`nutrition_label`).
///
/// What the model reads off a label is not an estimate, but it can misread: the values are shown to the user, who compares them
/// with the package and confirms them before anything is saved. Every field must be present in the answer; a value the table does not
/// give is `null` and stays unknown, never 0.
public struct NutritionLabelOutput: Sendable, Hashable, Decodable {
    /// What the values on the label refer to.
    public enum Basis: String, Sendable, Hashable, Decodable {
        case per100g = "per_100g"
        case per100ml = "per_100ml"
        case perServing = "per_serving"
    }

    /// A nutrition table is visible in the photo.
    public var tableFound: Bool
    /// The product name when it is legible on the package.
    public var productName: String?
    public var basis: Basis
    /// The weight of one serving or piece in grams, when the label states it.
    public var servingGrams: Double?
    public var kcal: Double?
    public var kilojoules: Double?
    public var proteinG: Double?
    public var carbsG: Double?
    public var fatG: Double?
    public var fiberG: Double?
    public var sugarG: Double?
    public var saturatedFatG: Double?
    public var saltG: Double?

    enum CodingKeys: String, CodingKey {
        case tableFound = "table_found"
        case productName = "product_name"
        case basis
        case servingGrams = "serving_grams"
        case kcal
        case kilojoules = "kj"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case sugarG = "sugar_g"
        case saturatedFatG = "saturated_fat_g"
        case saltG = "salt_g"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tableFound = try container.decode(Bool.self, forKey: .tableFound)
        productName = try container.decode(String?.self, forKey: .productName)
        basis = try container.decode(Basis.self, forKey: .basis)
        servingGrams = try container.decode(Double?.self, forKey: .servingGrams)
        kcal = try container.decode(Double?.self, forKey: .kcal)
        kilojoules = try container.decode(Double?.self, forKey: .kilojoules)
        proteinG = try container.decode(Double?.self, forKey: .proteinG)
        carbsG = try container.decode(Double?.self, forKey: .carbsG)
        fatG = try container.decode(Double?.self, forKey: .fatG)
        fiberG = try container.decode(Double?.self, forKey: .fiberG)
        sugarG = try container.decode(Double?.self, forKey: .sugarG)
        saturatedFatG = try container.decode(Double?.self, forKey: .saturatedFatG)
        saltG = try container.decode(Double?.self, forKey: .saltG)
    }

    public static func decode(_ data: Data) throws -> NutritionLabelOutput {
        try JSONDecoder().decode(NutritionLabelOutput.self, from: data)
    }

    /// Kilojoules per kilocalorie.
    public static let kilojoulesPerKilocalorie = 4.184
    /// An energy value above this per 100 g or 100 ml is nonsense (pure fat has about 900 kcal per 100 g).
    public static let maximumKcalPer100 = 1000.0
    /// The same limit for one serving or piece.
    public static let maximumKcalPerServing = 5000.0
    /// A weight of one piece above this is nonsense.
    public static let maximumServingGrams = 5000.0

    /// The values as a food for the edit sheet, or `nil` when nothing usable was read ("no table" or only unusable numbers).
    ///
    /// A negative or absurd number is dropped and the value stays unknown. Energy given only in kilojoules is converted. The energy
    /// can stay unknown (the sheet then asks for it): `energyUnknown` tells the sheet to leave the field empty.
    public func normalized() -> NutritionLabelReading? {
        guard tableFound else { return nil }
        let isServing = basis == .perServing
        let reference: FoodReference = switch basis {
        case .per100g: .per100g
        case .per100ml: .per100ml
        case .perServing: .perPiece(grams: servingGrams.flatMap { $0 > 0 && $0 <= Self.maximumServingGrams ? $0 : nil })
        }
        let limit = isServing ? Self.maximumKcalPerServing : Self.maximumKcalPer100
        func plausible(_ value: Double?, maximum: Double) -> Double? {
            guard let value, value >= 0, value <= maximum else { return nil }
            return value
        }
        let energy = plausible(kcal, maximum: limit) ?? plausible(kilojoules.map { $0 / Self.kilojoulesPerKilocalorie }, maximum: limit)
        // Grams of a nutrient can not exceed the reference amount; a serving has no fixed size, so only the 100 g bases are checked.
        let gramLimit = isServing ? Self.maximumServingGrams : 100
        let nutrients = NutrientValues(fiber: plausible(fiberG, maximum: gramLimit), sugar: plausible(sugarG, maximum: gramLimit),
                                       saturatedFat: plausible(saturatedFatG, maximum: gramLimit), salt: plausible(saltG, maximum: gramLimit))
        let protein = plausible(proteinG, maximum: gramLimit), carbs = plausible(carbsG, maximum: gramLimit)
        let fat = plausible(fatG, maximum: gramLimit)
        guard energy != nil || protein != nil || carbs != nil || fat != nil || nutrients.hasAny else { return nil }
        let name = (productName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let food = FoodValue(name: name, reference: reference, kcal: energy ?? 0, protein: protein, carbs: carbs, fat: fat,
                             nutrients: nutrients, origin: .label)
        return NutritionLabelReading(food: food, energyUnknown: energy == nil)
    }
}

/// A nutrition table read from a photo: the food to confirm and whether its energy value is missing.
public struct NutritionLabelReading: Sendable, Hashable {
    public var food: FoodValue
    /// The label (or the reading) gave no usable energy value; the field stays empty until the user types it.
    public var energyUnknown: Bool

    public init(food: FoodValue, energyUnknown: Bool) {
        self.food = food
        self.energyUnknown = energyUnknown
    }
}
