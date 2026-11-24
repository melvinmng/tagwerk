import Foundation
import SwiftData
import TagwerkCore

// Goal plans of the "Erfassen" tab: one record per day from which a set of goals holds (`GoalPlan.validFrom`).
// Schema rule: later attributes must be optional or have a default value.

@Model
final class GoalPlanRecord {
    var id: UUID = UUID()
    /// "YYYY-MM-DD" of `GoalPlan.validFrom`; unique, so a day has one plan and adopting twice on a day replaces it.
    @Attribute(.unique) var validFromKey: String = ""
    var kcal: Int = 2300
    var proteinGrams: Int?
    var carbsGrams: Int?
    var fatGrams: Int?
    var fiberGrams: Int?
    var sugarLimitGrams: Int?
    var waterMilliliters: Int = 2000
    var stepsPerDay: Int = 8000
    var workoutMinutesPerWeek: Int = 150
    var activeKcalPerDay: Int = 0
    var targetWeightKg: Double?
    var paceKgPerWeek: Double?
    var originRaw: String = GoalOrigin.manual.rawValue
    var note: String = ""

    init(_ plan: GoalPlan) {
        id = plan.id
        validFromKey = plan.validFrom.dayKey
        apply(plan)
    }

    var value: GoalPlan {
        GoalPlan(id: id, validFrom: PlanDay(dayKey: validFromKey) ?? PlanDay(year: 1970, month: 1, day: 1), kcal: kcal,
                 proteinGrams: proteinGrams, carbsGrams: carbsGrams, fatGrams: fatGrams, fiberGrams: fiberGrams,
                 sugarLimitGrams: sugarLimitGrams, waterMilliliters: waterMilliliters, stepsPerDay: stepsPerDay,
                 workoutMinutesPerWeek: workoutMinutesPerWeek, activeKcalPerDay: activeKcalPerDay,
                 targetWeightKg: targetWeightKg, paceKgPerWeek: paceKgPerWeek,
                 origin: GoalOrigin(rawValue: originRaw) ?? .manual, note: note)
    }

    /// Overwrites every value except the day; used when a plan of the same day is adopted again.
    func apply(_ plan: GoalPlan) {
        id = plan.id
        kcal = plan.kcal
        proteinGrams = plan.proteinGrams
        carbsGrams = plan.carbsGrams
        fatGrams = plan.fatGrams
        fiberGrams = plan.fiberGrams
        sugarLimitGrams = plan.sugarLimitGrams
        waterMilliliters = plan.waterMilliliters
        stepsPerDay = plan.stepsPerDay
        workoutMinutesPerWeek = plan.workoutMinutesPerWeek
        activeKcalPerDay = plan.activeKcalPerDay
        targetWeightKg = plan.targetWeightKg
        paceKgPerWeek = plan.paceKgPerWeek
        originRaw = plan.origin.rawValue
        note = plan.note
    }
}
