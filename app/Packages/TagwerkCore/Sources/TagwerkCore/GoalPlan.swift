import Foundation

/// Where a goal plan came from.
public enum GoalOrigin: String, Sendable, Codable, Hashable {
    /// Typed in the settings.
    case manual
    /// Proposed in the goal planning chat and confirmed by the user.
    case assistant
}

/// One set of goals that holds from a day on ("Zielstand"). Older days keep the plan that was valid then.
public struct GoalPlan: Sendable, Hashable, Identifiable {
    public var id: UUID
    /// First day the plan applies to; a plan never applies to earlier days once a newer one exists.
    public var validFrom: PlanDay
    /// Base goal of a day without credited activity.
    public var kcal: Int
    /// Macro and fibre targets in grams; `nil` means no goal.
    public var proteinGrams: Int?
    public var carbsGrams: Int?
    public var fatGrams: Int?
    public var fiberGrams: Int?
    /// Upper limit of sugar in grams; `nil` means no limit.
    public var sugarLimitGrams: Int?
    public var waterMilliliters: Int
    /// 0 shows the steps without a goal.
    public var stepsPerDay: Int
    /// 0 hides the training tile.
    public var workoutMinutesPerWeek: Int
    /// Goal for the active energy per day; 0 switches it off.
    public var activeKcalPerDay: Int
    public var targetWeightKg: Double?
    /// Intended weekly change of the body weight in kilograms; negative for losing weight.
    public var paceKgPerWeek: Double?
    public var origin: GoalOrigin
    public var note: String

    public init(id: UUID = UUID(), validFrom: PlanDay, kcal: Int, proteinGrams: Int? = nil, carbsGrams: Int? = nil,
                fatGrams: Int? = nil, fiberGrams: Int? = nil, sugarLimitGrams: Int? = nil, waterMilliliters: Int,
                stepsPerDay: Int, workoutMinutesPerWeek: Int, activeKcalPerDay: Int = 0, targetWeightKg: Double? = nil,
                paceKgPerWeek: Double? = nil, origin: GoalOrigin = .manual, note: String = "") {
        self.id = id
        self.validFrom = validFrom
        self.kcal = kcal
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.sugarLimitGrams = sugarLimitGrams
        self.waterMilliliters = waterMilliliters
        self.stepsPerDay = stepsPerDay
        self.workoutMinutesPerWeek = workoutMinutesPerWeek
        self.activeKcalPerDay = activeKcalPerDay
        self.targetWeightKg = targetWeightKg
        self.paceKgPerWeek = paceKgPerWeek
        self.origin = origin
        self.note = note
    }

    /// The first plan, taken over from the single goals of the settings. The protein goal only counts when it was switched on.
    public static func migrated(validFrom: PlanDay, kcal: Int, waterMilliliters: Int, proteinGoalEnabled: Bool, proteinGrams: Int,
                                stepsPerDay: Int, workoutMinutesPerWeek: Int) -> GoalPlan {
        GoalPlan(validFrom: validFrom, kcal: kcal, proteinGrams: proteinGoalEnabled ? proteinGrams : nil,
                 waterMilliliters: waterMilliliters, stepsPerDay: stepsPerDay, workoutMinutesPerWeek: workoutMinutesPerWeek)
    }
}

/// Which goal plan applies on which day.
public struct GoalTimeline: Sendable, Hashable {
    /// Oldest first; at most one plan per `validFrom` day.
    public private(set) var plans: [GoalPlan]

    /// Plans of the same day collapse into the last one given.
    public init(plans: [GoalPlan]) {
        var byDay: [PlanDay: GoalPlan] = [:]
        for plan in plans { byDay[plan.validFrom] = plan }
        self.plans = byDay.values.sorted { $0.validFrom < $1.validFrom }
    }

    /// The plan with the latest `validFrom` not after `day`. A day before the first plan uses the first plan, because there is
    /// nothing older to ask; no plan at all gives `nil`.
    public func plan(on day: PlanDay) -> GoalPlan? {
        plans.last { $0.validFrom <= day } ?? plans.first
    }

    /// The timeline with `plan` added; a plan of the same day is replaced.
    public func adopting(_ plan: GoalPlan) -> GoalTimeline {
        GoalTimeline(plans: plans + [plan])
    }
}
