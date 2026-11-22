import Foundation
import SwiftData
import TagwerkCore

// The Health values of a day that Tagwerk keeps (see `DayHealth`). Schema rule: later attributes must be optional or have a default.

@Model
final class DayHealthRecord {
    /// "YYYY-MM-DD"; one record per day.
    @Attribute(.unique) var dayKey: String = ""
    var activeKcal: Double?
    var creditPercent: Int = 50
    var foreignKcal: Double?
    var foreignProtein: Double?
    var foreignCarbs: Double?
    var foreignFat: Double?
    var foreignFiber: Double?
    var foreignSugar: Double?
    var foreignSaturatedFat: Double?
    var foreignSalt: Double?
    var foreignWaterMilliliters: Double?
    var foreignSources: [String] = []
    var updatedAt: Date = Date.now

    init(_ value: DayHealth, updatedAt: Date) {
        dayKey = value.day.dayKey
        self.updatedAt = updatedAt
        apply(value)
    }

    var value: DayHealth {
        DayHealth(day: PlanDay(dayKey: dayKey) ?? PlanDay(year: 1970, month: 1, day: 1), activeKcal: activeKcal,
                  creditPercent: creditPercent,
                  foreign: ForeignIntake(kcal: foreignKcal, protein: foreignProtein, carbs: foreignCarbs, fat: foreignFat,
                                         nutrients: NutrientValues(fiber: foreignFiber, sugar: foreignSugar,
                                                                   saturatedFat: foreignSaturatedFat, salt: foreignSalt),
                                         waterMilliliters: foreignWaterMilliliters, sources: foreignSources))
    }

    /// Overwrites every value except the day.
    func apply(_ value: DayHealth) {
        activeKcal = value.activeKcal
        creditPercent = value.creditPercent
        foreignKcal = value.foreign.kcal
        foreignProtein = value.foreign.protein
        foreignCarbs = value.foreign.carbs
        foreignFat = value.foreign.fat
        foreignFiber = value.foreign.nutrients.fiber
        foreignSugar = value.foreign.nutrients.sugar
        foreignSaturatedFat = value.foreign.nutrients.saturatedFat
        foreignSalt = value.foreign.nutrients.salt
        foreignWaterMilliliters = value.foreign.waterMilliliters
        foreignSources = value.foreign.sources
    }
}
