import Foundation
import Testing
@testable import TagwerkCore

struct NutrientCardTests {
    private let german = Locale(identifier: "de_DE")

    private func plan(protein: Int? = 140, carbs: Int? = 250, fat: Int? = 78, fiber: Int? = 30, sugar: Int? = 50) -> GoalPlan {
        GoalPlan(validFrom: PlanDay(year: 2026, month: 11, day: 21), kcal: 2300, proteinGrams: protein, carbsGrams: carbs, fatGrams: fat,
                 fiberGrams: fiber, sugarLimitGrams: sugar, waterMilliliters: 2000, stepsPerDay: 8000, workoutMinutesPerWeek: 150)
    }

    private func own(protein: Double = 68, carbs: Double = 152, fat: Double = 44, estimated: Bool = true,
                     fiber: NutrientSum = .empty, sugar: NutrientSum = .empty, saturated: NutrientSum = .empty,
                     salt: NutrientSum = .empty) -> DayIntake {
        DayIntake(kcal: 1340, kcalMin: 1200, kcalMax: 1500, protein: protein, carbs: carbs, fat: fat, waterMilliliters: 0,
                  hasEstimate: estimated, fiber: fiber, sugar: sugar, saturatedFat: saturated, salt: salt)
    }

    private func budget(_ plan: GoalPlan, credited kcal: Double = 0) -> EnergyBudget {
        EnergyBudget.make(plan: plan, active: ActiveEnergy(healthKcal: kcal), creditPercent: 100, eatenKcal: 1340)
    }

    private func rows(_ intake: DayIntake, plan: GoalPlan? = nil, credited: Double = 0, visible: [Nutrient] = [.fiber, .sugar],
                      foreign: ForeignIntake? = nil) -> [NutrientRow] {
        let plan = plan ?? self.plan()
        return NutrientCard.rows(totals: IntakeTotals(own: intake, foreign: foreign), plan: plan, budget: budget(plan, credited: credited),
                                 visible: visible, locale: german)
    }

    @Test func card_rows_followGoalPlanAndSwitches() {
        let basic = rows(own())
        #expect(basic.map(\.kind) == [.protein, .carbohydrates, .fat, .further(.fiber), .further(.sugar)])
        let all = rows(own(), visible: Nutrient.allCases)
        #expect(all.count == 7 && all.last?.kind == .further(.salt))
        // Without goals there is no bar; the value stands alone.
        let noGoals = rows(own(), plan: plan(protein: nil, carbs: nil, fat: nil, fiber: nil, sugar: nil))
        #expect(noGoals.allSatisfy { $0.progress == nil || $0.kind.isMacro && $0.progress == nil })
        #expect(noGoals[0].valueText == "~68 g")
    }

    @Test func macroRows_showTheValueAgainstTheGoal() {
        let result = rows(own(estimated: true))
        #expect(result[0].valueText == "~68 / 140 g" && result[0].progress == 68.0 / 140)
        #expect(rows(own(estimated: false))[0].valueText == "68 / 140 g", "typed values carry no tilde")
    }

    @Test func macroGoals_scaleWithBudget() {
        // 250 g and 78 g with full credit of 520 kcal: 326 g and 102 g (calculation rule BU3c); protein stays.
        let result = rows(own(), credited: 520)
        #expect(result[0].valueText == "~68 / 140 g")
        #expect(result[1].valueText == "~152 / 326 g")
        #expect(result[2].valueText == "~44 / 102 g")
    }

    @Test func fiber_isATarget_sugar_isALimit() {
        let result = rows(own(fiber: NutrientSum(value: 14, known: 3, total: 3), sugar: NutrientSum(value: 38, known: 3, total: 3)))
        #expect(result[3].valueText == "14 / 30 g" && !result[3].isOverLimit)
        #expect(result[4].valueText == "38 / max. 50 g" && !result[4].isOverLimit)
    }

    @Test func sugar_overLimit_isMarked() {
        let result = rows(own(sugar: NutrientSum(value: 62, known: 2, total: 2)))
        #expect(result[4].isOverLimit)
        #expect(result[4].spokenValue == "62 von höchstens 50 Gramm")
        // Exactly at the limit is not over it.
        #expect(!rows(own(sugar: NutrientSum(value: 50, known: 2, total: 2)))[4].isOverLimit)
    }

    @Test func row_showsCoverageWhenIncomplete() {
        let result = rows(own(fiber: NutrientSum(value: 14, known: 2, total: 3)))
        #expect(result[3].valueText == "mind. 14 / 30 g · 2 von 3 Mahlzeiten")
        #expect(result[3].spokenValue.hasPrefix("mindestens 14 von 30 Gramm"))
    }

    @Test func unknownNutrient_isADash_neverZero() {
        let result = rows(own())
        #expect(result[3].valueText == "–" && result[3].progress == nil)
        #expect(result[3].spokenValue == "keine Angabe")
    }

    @Test func nutrientWithoutGoal_showsTheValueAlone() {
        let result = rows(own(saturated: NutrientSum(value: 9, known: 1, total: 1), salt: NutrientSum(value: 4.26, known: 1, total: 1)),
                          visible: [.saturatedFat, .salt])
        #expect(result[3].valueText == "9 g" && result[3].progress == nil)
        #expect(result[4].valueText == "4,3 g")
    }

    @Test func foreignEntries_addToTheRows_withoutChangingTheCoverageOfOwnMeals() {
        let foreign = ForeignIntake(kcal: 300, protein: 20, nutrients: NutrientValues(fiber: 6), sources: ["Yazio"])
        let result = rows(own(fiber: NutrientSum(value: 10, known: 1, total: 2)), foreign: foreign)
        #expect(result[0].valueText == "~88 / 140 g")
        // The value adds the 6 g of the other app; the coverage still counts the own meals only.
        #expect(result[3].valueText == "mind. 16 / 30 g · 1 von 2 Mahlzeiten")
    }

    @Test func foreignRow_namesSources() {
        #expect(IntakeFormat.foreignSources(["Yazio", "Lose It"]) == "Yazio, Lose It")
        #expect(IntakeFormat.foreignSources([]) == "")
    }
}
