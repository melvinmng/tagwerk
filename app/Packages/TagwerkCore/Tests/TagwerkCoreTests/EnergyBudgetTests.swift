import Foundation
import Testing
@testable import TagwerkCore

struct EnergyBudgetTests {
    private func plan(kcal: Int = 2300, carbs: Int? = nil, fat: Int? = nil) -> GoalPlan {
        GoalPlan(validFrom: PlanDay(year: 2026, month: 11, day: 21), kcal: kcal, proteinGrams: 140, carbsGrams: carbs, fatGrams: fat,
                 waterMilliliters: 2000, stepsPerDay: 8000, workoutMinutesPerWeek: 150)
    }

    private func budget(active: Double? = 520, own: Double = 0, percent: Int = 50, eaten: Double = 1340, estimated: Bool = true,
                        plan: GoalPlan? = nil) -> EnergyBudget {
        EnergyBudget.make(plan: plan ?? self.plan(), active: ActiveEnergy(healthKcal: active, unsyncedOwnKcal: own),
                          creditPercent: percent, eatenKcal: eaten, eatenIsEstimated: estimated)
    }

    @Test func credited_roundsToTens() {
        #expect(budget(active: 523, percent: 100).credited == 520)
        #expect(budget(active: 525, percent: 100).credited == 530)
        #expect(budget(active: 417, percent: 50).credited == 210)
    }

    @Test func credited_shareZero_isZero() {
        let result = budget(percent: 0)
        #expect(result.credited == 0)
        #expect(result.budget == 2300)
    }

    @Test func credited_share75() { #expect(budget(percent: 75).credited == 390) }

    @Test func credited_defaultShareIsHalf() {
        #expect(EnergyBudget.defaultCreditPercent == 50)
        #expect(budget(percent: EnergyBudget.defaultCreditPercent).credited == 260)
    }

    @Test func credited_percentIsClamped() {
        #expect(budget(percent: 150).credited == 520)
        #expect(budget(percent: -5).credited == 0)
    }

    @Test func budget_exampleDay_fullCredit() {
        let result = budget(percent: 100)
        #expect(result.budget == 2820)
        #expect(result.remaining == 1480)
        #expect(!result.isOver)
    }

    @Test func budget_exampleDay_defaultCredit() {
        let result = budget(percent: 50)
        #expect(result.budget == 2560)
        #expect(result.remaining == 1220)
    }

    @Test func macros_proteinFixed_restScales() {
        let result = budget(percent: 100, plan: plan(carbs: 250, fat: 78))
        #expect(result.scaledCarbs == 326)
        #expect(result.scaledFat == 102)
    }

    @Test func macros_noCredit_keepBaseGoals() {
        let result = budget(percent: 0, plan: plan(carbs: 250, fat: 78))
        #expect(result.scaledCarbs == 250 && result.scaledFat == 78)
    }

    @Test func macros_withoutCarbOrFatGoal_staysNil() {
        let none = budget(plan: plan())
        #expect(none.scaledCarbs == nil && none.scaledFat == nil)
        // One goal alone cannot be split; it stays as it is and the missing one stays nil.
        let onlyCarbs = budget(percent: 100, plan: plan(carbs: 250))
        #expect(onlyCarbs.scaledCarbs == 250 && onlyCarbs.scaledFat == nil)
        let onlyFat = budget(percent: 100, plan: plan(fat: 78))
        #expect(onlyFat.scaledCarbs == nil && onlyFat.scaledFat == 78)
    }

    @Test func remaining_over_isNegativeAndMarked() {
        let result = budget(percent: 100, eaten: 2940)
        #expect(result.remaining == -120)
        #expect(result.isOver)
    }

    @Test func activeUnknown_usesOwnWorkoutsOnly() {
        let result = budget(active: nil, own: 300, percent: 100)
        #expect(result.active.total == 300)
        #expect(!result.active.isFromHealth)
        #expect(result.credited == 300)
        // Neither Health nor own workouts: nothing is credited, never a negative or invented value.
        #expect(budget(active: nil, own: 0, percent: 100).credited == 0)
    }

    @Test func active_healthSumPlusUnsyncedOwn() {
        let active = ActiveEnergy(healthKcal: 400, unsyncedOwnKcal: 120)
        #expect(active.total == 520)
        #expect(active.isFromHealth)
    }

    @Test func active_syncedOwnWorkout_isCountedOnce() {
        // A mirrored workout is inside the Health sum; the caller passes 0 for it, so the sum does not grow.
        #expect(ActiveEnergy(healthKcal: 520, unsyncedOwnKcal: 0).total == 520)
    }

    @Test func eaten_includesForeignIntake() {
        let own = DayIntake(kcal: 1000, kcalMin: 900, kcalMax: 1100, protein: 30, carbs: 100, fat: 40, waterMilliliters: 500,
                            hasEstimate: true)
        let foreign = ForeignIntake(kcal: 340, protein: 10, waterMilliliters: 250, sources: ["Yazio"])
        let totals = IntakeTotals.make(own: own, foreign: foreign, countsForeign: true)
        #expect(totals.kcal == 1340)
        #expect(totals.protein == 40 && totals.carbs == 100 && totals.fat == 40)
        #expect(totals.waterMilliliters == 750)
        #expect(budget(percent: 100, eaten: totals.kcal).remaining == 1480)
    }

    @Test func eaten_ownOnly_whenSwitchedOff_orNothingForeign() {
        let own = DayIntake(kcal: 1000, kcalMin: 900, kcalMax: 1100, protein: 30, carbs: 100, fat: 40, waterMilliliters: 500,
                            hasEstimate: false)
        let foreign = ForeignIntake(kcal: 340)
        #expect(IntakeTotals.make(own: own, foreign: foreign, countsForeign: false).kcal == 1000)
        #expect(IntakeTotals.make(own: own, foreign: ForeignIntake(), countsForeign: true).foreign == nil)
        #expect(IntakeTotals.make(own: own, foreign: nil, countsForeign: true).kcal == 1000)
    }

    @Test func foreignNutrient_addsValueWithoutChangingOwnCoverage() {
        let own = DayIntake(kcal: 0, kcalMin: 0, kcalMax: 0, protein: 0, carbs: 0, fat: 0, waterMilliliters: 0, hasEstimate: false,
                            fiber: NutrientSum(value: 10, known: 1, total: 2))
        let totals = IntakeTotals(own: own, foreign: ForeignIntake(nutrients: NutrientValues(fiber: 5, sugar: 8)))
        #expect(totals.nutrient(.fiber) == NutrientSum(value: 15, known: 1, total: 2))
        #expect(totals.nutrient(.sugar).value == 8)
        #expect(totals.nutrient(.salt).value == nil)
    }

    @Test func format_budgetRemaining() {
        #expect(IntakeFormat.budgetRemaining(budget(percent: 100)) == .init(text: "noch ~1.480", isOver: false))
        #expect(IntakeFormat.budgetRemaining(budget(percent: 100, estimated: false)) == .init(text: "noch 1.480", isOver: false))
        #expect(IntakeFormat.budgetRemaining(budget(percent: 100, eaten: 2940)) == .init(text: "~120 über Budget", isOver: true))
    }

    @Test func format_planHeaderLine_showsRemainingBudget() {
        let result = budget(percent: 100)
        #expect(IntakeFormat.planHeaderLine(budget: result, waterMilliliters: 1200, goalWaterMilliliters: 2000, hasEntries: true,
                                            steps: 6412) == "noch ~1.480 kcal · 1,2 / 2,0 l · 6.412 Schritte")
        #expect(IntakeFormat.planHeaderLine(budget: budget(percent: 100, eaten: 2940), waterMilliliters: 0, goalWaterMilliliters: 2000,
                                            hasEntries: true) == "~120 kcal über Budget · 0 / 2,0 l")
        #expect(IntakeFormat.planHeaderLine(budget: result, waterMilliliters: 0, goalWaterMilliliters: 2000, hasEntries: false) == nil)
    }
}

struct ActiveEnergyMakeTests {
    private func own(_ kcal: Double?, mirrored: Bool) -> OwnWorkoutEnergy { OwnWorkoutEnergy(kilocalories: kcal, isMirrored: mirrored) }

    @Test func ownWorkoutEnergy_countedOnce() {
        // Mirrored with calories: inside the Health sum already, so the sum alone counts.
        let mirrored = ActiveEnergy.make(healthKcal: 520, ownWorkouts: [own(310, mirrored: true)], healthAcceptsEnergy: true)
        #expect(mirrored.total == 520)
        // Not mirrored yet: the Health sum plus the own workout.
        let pending = ActiveEnergy.make(healthKcal: 520, ownWorkouts: [own(310, mirrored: false)], healthAcceptsEnergy: true)
        #expect(pending.total == 830)
        // The same workout after the mirror run: still counted once, now through Health.
        let after = ActiveEnergy.make(healthKcal: 830, ownWorkouts: [own(310, mirrored: true)], healthAcceptsEnergy: true)
        #expect(after.total == 830)
    }

    @Test func ownWorkoutEnergy_healthRefusedTheCalories_staysAGapFiller() {
        let result = ActiveEnergy.make(healthKcal: 520, ownWorkouts: [own(310, mirrored: true)], healthAcceptsEnergy: false)
        #expect(result.total == 830)
    }

    @Test func ownWorkoutEnergy_withoutHealthSum_allCount() {
        let result = ActiveEnergy.make(healthKcal: nil, ownWorkouts: [own(310, mirrored: true), own(100, mirrored: false), own(nil, mirrored: false)],
                                       healthAcceptsEnergy: true)
        #expect(result.total == 410)
        #expect(!result.isFromHealth)
    }

    @Test func ownWorkoutEnergy_withoutCalories_addsNothing() {
        #expect(ActiveEnergy.make(healthKcal: 400, ownWorkouts: [own(nil, mirrored: false)], healthAcceptsEnergy: true).total == 400)
    }
}
