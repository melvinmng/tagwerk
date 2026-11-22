import Foundation

/// The active energy of a day as the budget sees it.
public struct ActiveEnergy: Sendable, Hashable {
    /// The day's sum of the active energy from Health; `nil` when Health gives no value (not allowed, no data, locked).
    public var healthKcal: Double?
    /// Calories of workouts entered in Tagwerk that Health does not hold yet (`healthSynced == false`) or did not take.
    public var unsyncedOwnKcal: Double

    public init(healthKcal: Double?, unsyncedOwnKcal: Double = 0) {
        self.healthKcal = healthKcal
        self.unsyncedOwnKcal = unsyncedOwnKcal
    }

    /// "Aktiv des Tages": the Health sum plus the own workouts Health lacks. Without a Health value only the own workouts count.
    /// There is no deduction for a workout that the watch recorded as well (decision BU2a).
    public var total: Double { max(0, healthKcal ?? 0) + max(0, unsyncedOwnKcal) }

    /// Health delivered a sum; otherwise the screen says so ("Health liefert keine Werte").
    public var isFromHealth: Bool { healthKcal != nil }
}

/// An own workout as the active energy needs it.
public struct OwnWorkoutEnergy: Sendable, Hashable {
    public var kilocalories: Double?
    /// The workout was written to Health (`healthSynced`).
    public var isMirrored: Bool

    public init(kilocalories: Double?, isMirrored: Bool) {
        self.kilocalories = kilocalories
        self.isMirrored = isMirrored
    }
}

extension ActiveEnergy {
    /// The active energy of a day from the Health sum and the own workouts of that day.
    ///
    /// An own workout is inside the Health sum only when it was mirrored with its calories (`healthAcceptsEnergy`: the energy
    /// type may be written). Such a workout is not added again; the others are the gap filler. Without a Health sum nothing
    /// contains the own workouts, so all of them count.
    public static func make(healthKcal: Double?, ownWorkouts: [OwnWorkoutEnergy], healthAcceptsEnergy: Bool) -> ActiveEnergy {
        let missingInHealth = ownWorkouts.filter { healthKcal == nil || !$0.isMirrored || !healthAcceptsEnergy }
        return ActiveEnergy(healthKcal: healthKcal, unsyncedOwnKcal: missingInHealth.compactMap(\.kilocalories).reduce(0, +))
    }
}

/// The daily energy budget: base goal plus the credited share of the active energy, minus what was eaten.
public struct EnergyBudget: Sendable, Hashable {
    /// Credit shares offered in the settings, in percent.
    public static let creditPercents = [0, 50, 75, 100]
    /// Default share in percent (decision BU1b, set by the user on 21 Nov 2026 after the fact check).
    public static let defaultCreditPercent = 50

    /// Base goal of the day (the plan's kcal).
    public var base: Int
    public var active: ActiveEnergy
    /// Share of the active energy that counts, in percent.
    public var creditPercent: Int
    /// Share × active energy, rounded to 10 kcal.
    public var credited: Int
    public var budget: Int
    public var eatenKcal: Double
    /// The eaten value still contains estimates, so the budget numbers carry "~".
    public var isEstimated: Bool
    /// Macro goals grown with the credited energy (decision BU3c); `nil` without a goal.
    public var scaledCarbs: Int?
    public var scaledFat: Int?

    /// Budget minus eaten; negative when over the budget.
    public var remaining: Double { Double(budget) - eatenKcal }
    public var isOver: Bool { remaining < 0 }

    public static func make(plan: GoalPlan, active: ActiveEnergy, creditPercent: Int, eatenKcal: Double,
                            eatenIsEstimated: Bool = false) -> EnergyBudget {
        let percent = min(max(creditPercent, 0), 100)
        let credited = roundedToTens(Double(percent) / 100 * active.total)
        let macros = scaledMacros(carbs: plan.carbsGrams, fat: plan.fatGrams, credited: credited)
        return EnergyBudget(base: plan.kcal, active: active, creditPercent: percent, credited: credited,
                            budget: plan.kcal + credited, eatenKcal: eatenKcal, isEstimated: eatenIsEstimated,
                            scaledCarbs: macros.carbs, scaledFat: macros.fat)
    }

    static func roundedToTens(_ value: Double) -> Int { Int((value / 10).rounded()) * 10 }

    /// Carbohydrates and fat share the credited energy in the ratio of their energy in the base goal; protein and fibre stay.
    /// With only one of the two goals set the split is unknown, so that goal stays as it is; a missing goal stays `nil`.
    static func scaledMacros(carbs: Int?, fat: Int?, credited: Int) -> (carbs: Int?, fat: Int?) {
        guard let carbs, let fat else { return (carbs, fat) }
        let carbEnergy = 4 * Double(carbs), fatEnergy = 9 * Double(fat)
        let total = carbEnergy + fatEnergy
        guard total > 0 else { return (carbs, fat) }
        let extra = Double(credited)
        return (Int((Double(carbs) + extra * (carbEnergy / total) / 4).rounded()),
                Int((Double(fat) + extra * (fatEnergy / total) / 9).rounded()))
    }
}

extension IntakeFormat {
    /// "~1.480" or "1.480": the distance to the budget without the unit; estimates round to tens and carry "~".
    private static func budgetNumber(_ budget: EnergyBudget, locale: Locale) -> String {
        let magnitude = abs(budget.remaining)
        let value = budget.isEstimated ? roundedKcal(magnitude) : Int(magnitude.rounded())
        return "\(budget.isEstimated ? "~" : "")\(grouped(value, locale: locale))"
    }

    /// What is left of the budget: "noch ~1.480" or, over it, "~120 über Budget".
    public static func budgetRemaining(_ budget: EnergyBudget, locale: Locale = .current) -> Remaining {
        let number = budgetNumber(budget, locale: locale)
        if budget.isOver { return Remaining(text: String(localized: "\(number) über Budget", bundle: .module), isOver: true) }
        return Remaining(text: String(localized: "noch \(number)", bundle: .module), isOver: false)
    }

    /// The line in the head of "Planen" with the budget (decision OR2b): "noch ~1.480 kcal · 1,2 / 2,0 l · 6.412 Schritte",
    /// over the budget "~120 kcal über Budget · …". `nil` before the first entry of the day.
    public static func planHeaderLine(budget: EnergyBudget, waterMilliliters: Int, goalWaterMilliliters: Int, hasEntries: Bool,
                                      steps: Int? = nil, locale: Locale = .current) -> String? {
        guard hasEntries else { return nil }
        let number = budgetNumber(budget, locale: locale)
        let energy = budget.isOver ? String(localized: "\(number) kcal über Budget", bundle: .module)
                                   : String(localized: "noch \(number) kcal", bundle: .module)
        let water = waterMilliliters == 0 ? "0" : litersNumber(waterMilliliters, locale: locale)
        let goalWater = liters(goalWaterMilliliters, locale: locale)
        let line = String(localized: "\(energy) · \(water) / \(goalWater)", bundle: .module)
        guard let steps else { return line }
        let count = self.steps(steps, locale: locale)
        return line + " · " + String(localized: "\(count) Schritte", bundle: .module)
    }
}
