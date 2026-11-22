import Foundation

/// The nutrients beyond energy, protein, carbohydrates and fat that Tagwerk tracks. Every value is optional: a missing
/// value is unknown, never 0.
public enum Nutrient: String, Sendable, Codable, CaseIterable, Hashable {
    case fiber, sugar, saturatedFat, salt

    public var displayName: String {
        switch self {
        case .fiber: String(localized: "Ballaststoffe", bundle: .module)
        case .sugar: String(localized: "Zucker", bundle: .module)
        case .saturatedFat: String(localized: "Gesättigte Fettsäuren", bundle: .module)
        case .salt: String(localized: "Salz", bundle: .module)
        }
    }

    /// Whether a value above its target is a problem (sugar, saturated fat, salt) or below it (fibre).
    public var isLimit: Bool { self != .fiber }

    /// Decimal places shown for a value in grams; salt is small enough to need one.
    public var fractionDigits: Int { self == .salt ? 1 : 0 }
}

/// Optional values of the further nutrients, in grams per portion.
public struct NutrientValues: Sendable, Hashable, Codable {
    public var fiber: Double?
    public var sugar: Double?
    public var saturatedFat: Double?
    public var salt: Double?

    public init(fiber: Double? = nil, sugar: Double? = nil, saturatedFat: Double? = nil, salt: Double? = nil) {
        self.fiber = fiber
        self.sugar = sugar
        self.saturatedFat = saturatedFat
        self.salt = salt
    }

    /// No value is known.
    public static let unknown = NutrientValues()

    public subscript(nutrient: Nutrient) -> Double? {
        get {
            switch nutrient {
            case .fiber: fiber
            case .sugar: sugar
            case .saturatedFat: saturatedFat
            case .salt: salt
            }
        }
        set {
            switch nutrient {
            case .fiber: fiber = newValue
            case .sugar: sugar = newValue
            case .saturatedFat: saturatedFat = newValue
            case .salt: salt = newValue
            }
        }
    }

    /// At least one value is known.
    public var hasAny: Bool { Nutrient.allCases.contains { self[$0] != nil } }

    /// Every known value multiplied by `factor`; unknown values stay unknown.
    public func scaled(by factor: Double) -> NutrientValues {
        var result = self
        for nutrient in Nutrient.allCases { result[nutrient] = self[nutrient].map { $0 * factor } }
        return result
    }

    /// Grams of salt per gram of sodium (EU food labelling: salt = sodium × 2.5, Regulation (EU) No 1169/2011, Annex I).
    public static let saltPerSodium = 2.5

    /// Salt in grams for a sodium amount in grams (Health stores sodium, the app shows salt).
    public static func salt(fromSodiumGrams sodium: Double) -> Double { sodium * saltPerSodium }

    /// Sodium in grams for a salt amount in grams.
    public static func sodiumGrams(fromSalt salt: Double) -> Double { salt / saltPerSodium }
}

/// The total of one nutrient over several meals, with the number of meals that know it.
///
/// `value` adds up everything that is known, so it is a lower bound whenever `known < total`.
public struct NutrientSum: Sendable, Hashable {
    /// Sum of the known values; `nil` when no value at all is known (not 0).
    public var value: Double?
    /// Meals whose items all have a value.
    public var known: Int
    /// Meals counted.
    public var total: Int

    public init(value: Double?, known: Int, total: Int) {
        self.value = value
        self.known = known
        self.total = total
    }

    /// Nothing counted.
    public static let empty = NutrientSum(value: nil, known: 0, total: 0)

    /// Every counted meal knows the value (and there is one).
    public var isComplete: Bool { value != nil && known == total }

    /// One meal's contribution to a `NutrientSum`.
    public struct Part: Sendable, Hashable {
        public var value: Double?
        public var isComplete: Bool

        public init(value: Double?, isComplete: Bool) {
            self.value = value
            self.isComplete = isComplete
        }
    }

    /// Adds the known values and counts the complete parts.
    public static func combine(_ parts: [Part]) -> NutrientSum {
        let values = parts.compactMap(\.value)
        return NutrientSum(value: values.isEmpty ? nil : values.reduce(0, +),
                           known: parts.filter(\.isComplete).count, total: parts.count)
    }
}
