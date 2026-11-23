import Testing
@testable import TagwerkCore

struct GoalProposalTests {
    private let plan = GoalPlan(validFrom: PlanDay(year: 2026, month: 11, day: 21), kcal: 2300, proteinGrams: 120, carbsGrams: 250, fatGrams: 70,
                                waterMilliliters: 2000, stepsPerDay: 8000, workoutMinutesPerWeek: 150, targetWeightKg: 80, paceKgPerWeek: -0.2)

    @Test func applying_nutrition_nilKeepsTheCurrentValue() {
        let updated = plan.applying(NutritionGoalProposal(kcal: 1900, proteinGrams: 140))
        #expect(updated.kcal == 1900 && updated.proteinGrams == 140)
        #expect(updated.carbsGrams == 250 && updated.fatGrams == 70 && updated.waterMilliliters == 2000)
        #expect(updated.targetWeightKg == 80 && updated.paceKgPerWeek == -0.2)
        #expect(updated.stepsPerDay == 8000, "activity values are not touched by a nutrition proposal")
    }

    @Test func applying_activity_changesOnlyTheActivityValues() {
        let updated = plan.applying(ActivityGoalProposal(stepsPerDay: 9000, workoutMinutesPerWeek: 180))
        #expect(updated.stepsPerDay == 9000 && updated.workoutMinutesPerWeek == 180 && updated.activeKcalPerDay == 0)
        #expect(updated.kcal == 2300)
    }

    @Test func applying_bothProposals_buildOnEachOther() {
        let both = plan.applying(NutritionGoalProposal(kcal: 2000)).applying(ActivityGoalProposal(stepsPerDay: 10000))
        #expect(both.kcal == 2000 && both.stepsPerDay == 10000)
    }

    @Test func violations_listEveryValueOutsideItsRange() {
        let proposal = NutritionGoalProposal(kcal: 900, proteinGrams: 9000, carbsGrams: 250, waterMilliliters: 100, targetWeightKg: 5, paceKgPerWeek: -5)
        #expect(Set(proposal.violations.map(\.field)) == ["kcal", "protein_g", "water_ml", "target_weight_kg", "pace_kg_per_week"])
        #expect(NutritionGoalProposal(kcal: 1000, proteinGrams: 20).violations.isEmpty, "the limits themselves are allowed")
        #expect(Set(ActivityGoalProposal(stepsPerDay: 99999, workoutMinutesPerWeek: -1, activeKcalPerDay: 0).violations.map(\.field))
                == ["steps_per_day", "workout_minutes_per_week"])
    }

    @Test func isEmpty_withoutValues() {
        #expect(NutritionGoalProposal(reason: "x").isEmpty)
        #expect(!NutritionGoalProposal(kcal: 2000).isEmpty)
        #expect(ActivityGoalProposal().isEmpty)
    }
}
