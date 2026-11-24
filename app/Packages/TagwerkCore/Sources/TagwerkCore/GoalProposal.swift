import Foundation

/// The values of a nutrition goal proposal; `nil` keeps the value of the plan that holds now.
public struct NutritionGoalProposal: Sendable, Hashable {
    public var kcal: Int?
    public var proteinGrams: Int?
    public var carbsGrams: Int?
    public var fatGrams: Int?
    public var fiberGrams: Int?
    public var sugarLimitGrams: Int?
    public var waterMilliliters: Int?
    public var targetWeightKg: Double?
    public var paceKgPerWeek: Double?
    public var reason: String

    public init(kcal: Int? = nil, proteinGrams: Int? = nil, carbsGrams: Int? = nil, fatGrams: Int? = nil, fiberGrams: Int? = nil,
                sugarLimitGrams: Int? = nil, waterMilliliters: Int? = nil, targetWeightKg: Double? = nil, paceKgPerWeek: Double? = nil,
                reason: String = "") {
        self.kcal = kcal
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.sugarLimitGrams = sugarLimitGrams
        self.waterMilliliters = waterMilliliters
        self.targetWeightKg = targetWeightKg
        self.paceKgPerWeek = paceKgPerWeek
        self.reason = reason
    }

    /// True when no value is proposed.
    public var isEmpty: Bool {
        kcal == nil && proteinGrams == nil && carbsGrams == nil && fatGrams == nil && fiberGrams == nil && sugarLimitGrams == nil
            && waterMilliliters == nil && targetWeightKg == nil && paceKgPerWeek == nil
    }
}

/// The values of an activity goal proposal; `nil` keeps the value of the plan that holds now.
public struct ActivityGoalProposal: Sendable, Hashable {
    public var stepsPerDay: Int?
    public var workoutMinutesPerWeek: Int?
    public var activeKcalPerDay: Int?
    public var reason: String

    public init(stepsPerDay: Int? = nil, workoutMinutesPerWeek: Int? = nil, activeKcalPerDay: Int? = nil, reason: String = "") {
        self.stepsPerDay = stepsPerDay
        self.workoutMinutesPerWeek = workoutMinutesPerWeek
        self.activeKcalPerDay = activeKcalPerDay
        self.reason = reason
    }

    public var isEmpty: Bool { stepsPerDay == nil && workoutMinutesPerWeek == nil && activeKcalPerDay == nil }
}

/// A value of a proposal that lies outside the range of its goal (`GoalRanges`).
public struct GoalRangeViolation: Sendable, Hashable {
    /// The field as the function calls it ("kcal", "protein_g", ...).
    public var field: String
    public var lower: Double
    public var upper: Double
}

extension GoalPlan {
    /// The plan with the values of `proposal` over the current ones. A proposed kilogram or pace value of the weight goal replaces the old
    /// one; the other fields stay.
    public func applying(_ proposal: NutritionGoalProposal) -> GoalPlan {
        var plan = self
        if let value = proposal.kcal { plan.kcal = value }
        if let value = proposal.proteinGrams { plan.proteinGrams = value }
        if let value = proposal.carbsGrams { plan.carbsGrams = value }
        if let value = proposal.fatGrams { plan.fatGrams = value }
        if let value = proposal.fiberGrams { plan.fiberGrams = value }
        if let value = proposal.sugarLimitGrams { plan.sugarLimitGrams = value }
        if let value = proposal.waterMilliliters { plan.waterMilliliters = value }
        if let value = proposal.targetWeightKg { plan.targetWeightKg = value }
        if let value = proposal.paceKgPerWeek { plan.paceKgPerWeek = value }
        return plan
    }

    public func applying(_ proposal: ActivityGoalProposal) -> GoalPlan {
        var plan = self
        if let value = proposal.stepsPerDay { plan.stepsPerDay = value }
        if let value = proposal.workoutMinutesPerWeek { plan.workoutMinutesPerWeek = value }
        if let value = proposal.activeKcalPerDay { plan.activeKcalPerDay = value }
        return plan
    }
}

extension NutritionGoalProposal {
    /// The proposed values that lie outside their ranges; empty when all fit. A proposal below the hard limit of the base goal is a
    /// separate case (`GoalCheck.isBlocked`): the range of the base goal starts at that limit.
    public var violations: [GoalRangeViolation] {
        var result: [GoalRangeViolation] = []
        func check(_ field: String, _ value: Int?, _ range: ClosedRange<Int>) {
            if let value, !range.contains(value) { result.append(GoalRangeViolation(field: field, lower: Double(range.lowerBound), upper: Double(range.upperBound))) }
        }
        check("kcal", kcal, GoalRanges.kcal)
        check("protein_g", proteinGrams, GoalRanges.proteinGrams)
        check("carbs_g", carbsGrams, GoalRanges.carbsGrams)
        check("fat_g", fatGrams, GoalRanges.fatGrams)
        check("fiber_g", fiberGrams, GoalRanges.fiberGrams)
        check("sugar_limit_g", sugarLimitGrams, GoalRanges.sugarLimitGrams)
        check("water_ml", waterMilliliters, GoalRanges.waterMilliliters)
        if let value = targetWeightKg, !GoalRanges.targetWeightKg.contains(value) {
            result.append(GoalRangeViolation(field: "target_weight_kg", lower: GoalRanges.targetWeightKg.lowerBound, upper: GoalRanges.targetWeightKg.upperBound))
        }
        if let value = paceKgPerWeek, !GoalRanges.paceKgPerWeek.contains(value) {
            result.append(GoalRangeViolation(field: "pace_kg_per_week", lower: GoalRanges.paceKgPerWeek.lowerBound, upper: GoalRanges.paceKgPerWeek.upperBound))
        }
        return result
    }
}

extension ActivityGoalProposal {
    public var violations: [GoalRangeViolation] {
        var result: [GoalRangeViolation] = []
        func check(_ field: String, _ value: Int?, _ range: ClosedRange<Int>) {
            if let value, !range.contains(value) { result.append(GoalRangeViolation(field: field, lower: Double(range.lowerBound), upper: Double(range.upperBound))) }
        }
        check("steps_per_day", stepsPerDay, GoalRanges.stepsPerDay)
        check("workout_minutes_per_week", workoutMinutesPerWeek, GoalRanges.workoutMinutesPerWeek)
        check("active_kcal_per_day", activeKcalPerDay, GoalRanges.activeKcalPerDay)
        return result
    }
}
