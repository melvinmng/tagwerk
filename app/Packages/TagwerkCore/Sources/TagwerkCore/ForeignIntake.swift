import Foundation

/// Day totals of nutrition entries that other apps wrote to Health. Tagwerk's own entries never appear here: they come from
/// Tagwerk's database only, so nothing is counted twice.
///
/// A `nil` value means "no foreign entries or reading not allowed": iOS does not tell those apart, and neither does this type.
public struct ForeignIntake: Sendable, Hashable {
    public var kcal: Double?
    public var protein: Double?
    public var carbs: Double?
    public var fat: Double?
    /// Fibre, sugar, saturated fat and salt (sodium converted to salt) in grams.
    public var nutrients: NutrientValues
    public var waterMilliliters: Double?
    /// Names of the apps the entries came from, for the row "Aus Health · andere Apps".
    public var sources: [String]

    public init(kcal: Double? = nil, protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil,
                nutrients: NutrientValues = .unknown, waterMilliliters: Double? = nil, sources: [String] = []) {
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.nutrients = nutrients
        self.waterMilliliters = waterMilliliters
        self.sources = sources
    }

    /// At least one value is there, so the row is worth showing.
    public var hasValues: Bool {
        kcal != nil || protein != nil || carbs != nil || fat != nil || nutrients.hasAny || waterMilliliters != nil
    }
}

/// What a day counts as eaten: the own entries plus, when the user switched it on, the totals of other apps.
public struct IntakeTotals: Sendable, Hashable {
    public var own: DayIntake
    /// `nil` when other apps' entries are not counted or there are none.
    public var foreign: ForeignIntake?

    public init(own: DayIntake, foreign: ForeignIntake?) {
        self.own = own
        self.foreign = foreign
    }

    /// The totals of a day. `foreign` only counts with `countsForeign` and when it holds a value.
    public static func make(own: DayIntake, foreign: ForeignIntake?, countsForeign: Bool) -> IntakeTotals {
        IntakeTotals(own: own, foreign: countsForeign && foreign?.hasValues == true ? foreign : nil)
    }

    public var kcal: Double { own.kcal + (foreign?.kcal ?? 0) }
    public var protein: Double { own.protein + (foreign?.protein ?? 0) }
    public var carbs: Double { own.carbs + (foreign?.carbs ?? 0) }
    public var fat: Double { own.fat + (foreign?.fat ?? 0) }
    public var waterMilliliters: Int { own.waterMilliliters + Int((foreign?.waterMilliliters ?? 0).rounded()) }

    /// Estimates come from the own meals only; values of other apps are shown as they are.
    public var hasEstimate: Bool { own.hasEstimate }

    /// A further nutrient: the own sum plus the foreign value. The coverage (`known`, `total`) counts the own meals only, as
    /// foreign totals are not meals; a foreign value alone still gives a value.
    public func nutrient(_ nutrient: Nutrient) -> NutrientSum {
        var sum = own[nutrient]
        if let extra = foreign?.nutrients[nutrient] { sum.value = (sum.value ?? 0) + extra }
        return sum
    }
}
