import Foundation
import Testing
@testable import TagwerkCore

struct WeekReviewTests {
    let calendar = makeCalendar()
    /// Monday, 16 Nov 2026.
    let monday = PlanDay(year: 2026, month: 11, day: 16)
    let goals = WeekReview.Goals(kcal: 2300, waterMilliliters: 2000, workoutMinutesPerWeek: 150, stepsPerDay: 8000, proteinGrams: nil)

    private func meal(day: Int, kcal: Double, estimated: Bool = true, protein: Double = 0, carbs: Double = 0,
                      fat: Double = 0) -> MealValue {
        let item = MealItem(name: "x", amount: "1", kcalMin: kcal, kcal: kcal, kcalMax: kcal, protein: protein, carbs: carbs, fat: fat,
                            isEstimated: estimated)
        return MealValue(id: UUID(), date: instant(2026, 11, day, 12, 0, in: calendar), kind: .lunch, title: "x", items: [item],
                         origin: estimated ? .estimated : .manual)
    }

    private func drink(day: Int, ml: Int) -> DrinkValue {
        DrinkValue(id: UUID(), date: instant(2026, 11, day, 10, 0, in: calendar), milliliters: ml)
    }

    private func workout(day: Int, minutes: Int) -> WorkoutValue {
        WorkoutValue(id: UUID().uuidString, activity: .running, start: instant(2026, 11, day, 7, 0, in: calendar),
                     minutes: minutes, kilocalories: nil, sourceName: nil, isOwn: true)
    }

    private func review(meals: [MealValue] = [], drinks: [DrinkValue] = [], workouts: [WorkoutValue] = [],
                        steps: [PlanDay: Int] = [:], completed: [Date] = [], now: Date? = nil,
                        goals: WeekReview.Goals? = nil) -> WeekReview {
        WeekReview.make(weekStart: monday, now: now ?? instant(2026, 11, 25, 9, 0, in: calendar), meals: meals, drinks: drinks,
                        workouts: workouts, steps: steps, completedDates: completed, goals: goals ?? self.goals,
                        calendar: calendar)
    }

    private func day(_ day: Int) -> PlanDay { PlanDay(year: 2026, month: 11, day: day) }

    @Test func review_daysWithoutMeals_areNil() {
        let result = review(meals: [meal(day: 16, kcal: 2000)])
        #expect(result.days.count == 7)
        #expect(result.days[0].kcal == 2000)
        #expect(result.days[1].kcal == nil)
    }

    @Test func review_averageOnlyDaysWithMeals() {
        let result = review(meals: [meal(day: 16, kcal: 2000), meal(day: 17, kcal: 1000), meal(day: 17, kcal: 1500, estimated: false)])
        #expect(result.daysWithMeals == 2)
        #expect(result.averageKcal == 2250)
        #expect(result.hasEstimate)
    }

    @Test func review_ignoresEntriesOutsideTheWeek() {
        let result = review(meals: [meal(day: 15, kcal: 900), meal(day: 23, kcal: 900)], drinks: [drink(day: 23, ml: 500)])
        #expect(result.daysWithMeals == 0)
        #expect(result.averageKcal == nil)
        #expect(result.isEmpty)
    }

    @Test func review_waterGoalDays() {
        let result = review(drinks: [drink(day: 16, ml: 1500), drink(day: 16, ml: 500), drink(day: 17, ml: 1000)])
        #expect(result.waterGoalDays == 1)
        #expect(result.daysWithWater == 2)
        #expect(result.averageWaterMilliliters == 1500)
    }

    @Test func workoutMinutes_countAllWorkouts_workoutCountKeepsThreshold() {
        let result = review(workouts: [workout(day: 16, minutes: 45), workout(day: 18, minutes: 9), workout(day: 22, minutes: 60),
                                       workout(day: 23, minutes: 30)])
        #expect(result.workoutCount == 2)
        #expect(result.workoutMinutes == 114)
    }

    @Test func onlyShortWorkout_isNotEmpty() {
        let result = review(workouts: [workout(day: 17, minutes: 5)])
        #expect(result.workoutCount == 0)
        #expect(result.workoutMinutes == 5)
        #expect(!result.isEmpty)
    }

    @Test func steps_averageOverDaysWithValue_futureDaysExcluded() {
        let result = review(steps: [day(16): 8240, day(17): 5750, day(18): 6412, day(19): 3000, day(15): 20_000],
                            now: instant(2026, 11, 18, 13, 0, in: calendar))
        #expect(result.days.map(\.steps) == [8240, 5750, 6412, nil, nil, nil, nil])
        #expect(result.daysWithSteps == 3)
        #expect(result.averageSteps == 6801)
    }

    @Test func steps_goalDays_countDaysAtOrAboveGoal_zeroGoalGivesNone() {
        let steps = [day(16): 8000, day(17): 7999, day(18): 12_000]
        #expect(review(steps: steps).stepGoalDays == 2)
        let noGoal = WeekReview.Goals(kcal: 2300, waterMilliliters: 2000, workoutMinutesPerWeek: 150, stepsPerDay: 0, proteinGrams: nil)
        #expect(review(steps: steps, goals: noGoal).stepGoalDays == 0)
    }

    @Test func steps_missingDay_isNil_notZero() {
        let result = review(steps: [day(16): 4000])
        #expect(result.days[0].steps == 4000)
        #expect(result.days[1].steps == nil)
        #expect(review().averageSteps == nil)
        #expect(review().daysWithSteps == 0)
    }

    @Test func isEmpty_ignoresSteps() {
        #expect(review(steps: [day(16): 9000]).isEmpty)
    }

    @Test func review_currentWeek_futureDays() {
        let result = review(meals: [meal(day: 16, kcal: 2000)], now: instant(2026, 11, 18, 9, 0, in: calendar))
        #expect(result.isCurrentWeek)
        #expect(result.days.filter(\.isFuture).count == 4)
        #expect(result.days[2].isFuture == false)
    }

    @Test func review_completedCount_inWeekOnly() {
        let result = review(completed: [instant(2026, 11, 16, 8, 0, in: calendar), instant(2026, 11, 22, 23, 59, in: calendar),
                                        instant(2026, 11, 23, 0, 0, in: calendar)])
        #expect(result.completedTasks == 2)
        #expect(result.isEmpty == false)
    }

    @Test func review_proteinMean_isKnownWithoutAGoal() {
        // Protein sits in the combined nutrient group next to carbohydrates and fat, so its mean does not depend on a goal.
        let meals = [meal(day: 16, kcal: 2000, protein: 100), meal(day: 17, kcal: 2000, protein: 60)]
        let result = review(meals: meals)
        #expect(result.averageProtein == 80)
        #expect(result.proteinDays == 2)
        #expect(result.goals.proteinGrams == nil)
        #expect(review().averageProtein == nil)
        #expect(review().proteinDays == 0)
    }

    @Test func review_weekTitle() {
        #expect(WeekReview.title(weekStart: monday, calendar: calendar) == "KW 47 · 16.–22. Nov")
        let crossing = PlanDay(year: 2026, month: 11, day: 30)
        #expect(WeekReview.title(weekStart: crossing, calendar: calendar) == "KW 49 · 30. Nov – 6. Dez")
        // Month names follow the locale; the words around them stay German until the English texts exist.
        #expect(WeekReview.title(weekStart: crossing, calendar: calendar, locale: Locale(identifier: "en_US")) == "KW 49 · 30. Nov – 6. Dec")
    }

    @Test func weekTraining_minutesAgainstGoal_countAsAddition() {
        #expect(IntakeFormat.weekTraining(minutes: 127, count: 3, goal: 150) == "2 h 7 min / 2 h 30 min · 3 Trainings")
        #expect(IntakeFormat.weekTraining(minutes: 45, count: 1, goal: 0) == "45 min · 1 Training")
        #expect(IntakeFormat.weekTraining(minutes: 5, count: 0, goal: 150) == "5 min / 2 h 30 min")
        #expect(IntakeFormat.weekTraining(minutes: 0, count: 0, goal: 150) == "Kein Training")
    }

    @Test func weekSteps_averageAndGoalDays() {
        #expect(IntakeFormat.weekSteps(average: 6801, goalDays: 1, elapsedDays: 3, goal: 8000) == "Ø 6.801 pro Tag · Ziel an 1 von 3 Tagen")
        #expect(IntakeFormat.weekSteps(average: 6801, goalDays: 0, elapsedDays: 3, goal: 0) == "Ø 6.801 pro Tag")
        #expect(IntakeFormat.weekSteps(average: nil, goalDays: 0, elapsedDays: 3, goal: 8000) == "Keine Schritte aus Health")
    }


    // MARK: Budget, stored goals and further nutrients (nutrition plan, C4)

    private func plan(kcal: Int, water: Int = 2000, steps: Int = 8000) -> GoalPlan {
        GoalPlan(validFrom: monday, kcal: kcal, waterMilliliters: water, stepsPerDay: steps, workoutMinutesPerWeek: 150)
    }

    private func budget(_ plan: GoalPlan, active: Double?, eaten: Double) -> EnergyBudget {
        EnergyBudget.make(plan: plan, active: ActiveEnergy(healthKcal: active), creditPercent: 100, eatenKcal: eaten)
    }

    private func reviewWithBudgets(meals: [MealValue] = [], totals: [PlanDay: IntakeTotals] = [:], budgets: [PlanDay: EnergyBudget] = [:],
                                   plans: [PlanDay: GoalPlan] = [:], steps: [PlanDay: Int] = [:], drinks: [DrinkValue] = []) -> WeekReview {
        WeekReview.make(weekStart: monday, now: instant(2026, 11, 25, 9, 0, in: calendar), meals: meals, drinks: drinks, workouts: [],
                        steps: steps, completedDates: [], goals: goals, totals: totals, budgets: budgets, plans: plans, calendar: calendar)
    }

    @Test func weekReview_dayWithinBudget_usesPlanAndStoredHealthOfThatDay() {
        let earlier = plan(kcal: 2000)
        let later = plan(kcal: 2600)
        let result = reviewWithBudgets(meals: [meal(day: 16, kcal: 2400), meal(day: 17, kcal: 2400)],
                                       budgets: [day(16): budget(earlier, active: 600, eaten: 2400), day(17): budget(later, active: nil, eaten: 2400)],
                                       plans: [day(16): earlier, day(17): later])
        #expect(result.days[0].goalKcal == 2600, "2.000 base plus 600 credited")
        #expect(result.days[1].goalKcal == 2600)
        // Day 16 was within its budget (2.400 < 2.600); against today's single goal of 2.300 it would not have been.
        #expect(result.days[0].kcal.map { $0 <= Double(result.days[0].goalKcal) } == true)
    }

    @Test func weekReview_unknownActivity_fallsBackToBaseGoal() {
        let base = plan(kcal: 2200)
        let result = reviewWithBudgets(meals: [meal(day: 16, kcal: 1000)], budgets: [day(16): budget(base, active: nil, eaten: 1000)],
                                       plans: [day(16): base])
        #expect(result.days[0].goalKcal == 2200)
        // A day the caller knows nothing about uses the single goals.
        #expect(result.days[1].goalKcal == 2300)
    }

    @Test func weekReview_foreignEntriesCountAsEaten_andOpenTheDay() {
        let own = DayIntake(kcal: 0, kcalMin: 0, kcalMax: 0, protein: 0, carbs: 0, fat: 0, waterMilliliters: 0, hasEstimate: false)
        let totals = IntakeTotals(own: own, foreign: ForeignIntake(kcal: 700, protein: 30, waterMilliliters: 400, sources: ["Yazio"]))
        let result = reviewWithBudgets(totals: [day(16): totals])
        #expect(result.days[0].kcal == 700 && result.days[0].protein == 30 && result.days[0].waterMilliliters == 400)
        #expect(result.daysWithMeals == 1)
        #expect(result.days[1].kcal == nil, "a day without any entry stays empty, not 0")
    }

    @Test func weekReview_goalDaysUseTheGoalOfEachDay() {
        let low = plan(kcal: 2300, water: 1000, steps: 4000)
        let high = plan(kcal: 2300, water: 3000, steps: 12_000)
        let result = reviewWithBudgets(plans: [day(16): low, day(17): high], steps: [day(16): 5000, day(17): 5000],
                                       drinks: [drink(day: 16, ml: 1500), drink(day: 17, ml: 1500)])
        #expect(result.waterGoalDays == 1 && result.stepGoalDays == 1)
    }

    @Test func weekReview_nutrientAverages_useOnlyDaysThatKnowTheValue() {
        func item(fiber: Double?) -> MealItem {
            MealItem(name: "x", amount: "1", kcalMin: 500, kcal: 500, kcalMax: 500, protein: 0, carbs: 0, fat: 0, fiber: fiber)
        }
        func meal(day: Int, fiber: Double?) -> MealValue {
            MealValue(id: UUID(), date: instant(2026, 11, day, 12, 0, in: calendar), kind: .lunch, title: "x", items: [item(fiber: fiber)], origin: .manual)
        }
        let result = review(meals: [meal(day: 16, fiber: 20), meal(day: 17, fiber: 30), meal(day: 18, fiber: nil)])
        #expect(result.averageNutrients.fiber == 25)
        #expect(result.nutrientDays[.fiber] == 2)
        #expect(result.averageNutrients.sugar == nil && result.nutrientDays[.sugar] == 0, "unknown is not 0")
    }

    // MARK: Budget days, macro means and goals (C4)

    private func budgetedReview(meals: [MealValue], budgets: [PlanDay: EnergyBudget] = [:],
                                now: Date? = nil) -> WeekReview {
        WeekReview.make(weekStart: monday, now: now ?? instant(2026, 11, 25, 9, 0, in: calendar), meals: meals, drinks: [],
                        workouts: [], completedDates: [], goals: goals, budgets: budgets, calendar: calendar)
    }

    @Test func daysWithinBudget_countsOnlyDaysWithMeals() {
        // Single goal of 2.300: Monday and Tuesday are within it, Wednesday is over; the empty days do not count either way.
        let result = review(meals: [meal(day: 16, kcal: 2000), meal(day: 17, kcal: 2300), meal(day: 18, kcal: 2400)])
        #expect(result.daysWithMeals == 3)
        #expect(result.daysWithinBudget == 2)
        #expect(review().daysWithinBudget == 0)
    }

    @Test func daysWithinBudget_usesBudgetOfEachDay() {
        let base = plan(kcal: 2000)
        // Monday credits 600 kcal of activity (budget 2.600), Tuesday has no activity (budget 2.000); both eat 2.400.
        let budgets = [day(16): budget(base, active: 600, eaten: 2400), day(17): budget(base, active: nil, eaten: 2400)]
        let result = budgetedReview(meals: [meal(day: 16, kcal: 2400), meal(day: 17, kcal: 2400)], budgets: budgets)
        #expect(result.days[0].goalKcal == 2600)
        #expect(result.days[1].goalKcal == 2000)
        #expect(result.daysWithinBudget == 1)
    }

    @Test func daysWithinBudget_futureDaysNeverCount() {
        let result = review(meals: [meal(day: 16, kcal: 1000)], now: instant(2026, 11, 17, 9, 0, in: calendar))
        #expect(result.daysWithinBudget == 1)
        #expect(result.days.filter { $0.isFuture && $0.kcal != nil }.isEmpty)
    }

    @Test func averageBudget_overDaysWithMeals() {
        let base = plan(kcal: 2000)
        let budgets = [day(16): budget(base, active: 600, eaten: 2400), day(17): budget(base, active: nil, eaten: 2400),
                       day(18): budget(base, active: 1000, eaten: 0)]
        // Wednesday has a large budget but no meal: it must not pull the mean of the days with meals up.
        let result = budgetedReview(meals: [meal(day: 16, kcal: 2400), meal(day: 17, kcal: 2400)], budgets: budgets)
        #expect(result.averageBudgetKcal == 2300)
        #expect(review().averageBudgetKcal == nil)
    }

    @Test func carbsAndFat_meanOverDaysWithMeals() {
        let result = review(meals: [meal(day: 16, kcal: 2000, carbs: 200, fat: 60), meal(day: 17, kcal: 2000, carbs: 300, fat: 80)])
        #expect(result.averageCarbs == 250)
        #expect(result.averageFat == 70)
        #expect(result.carbsDays == 2 && result.fatDays == 2)
        #expect(result.days[2].carbs == nil && result.days[2].fat == nil, "a day without meals stays unknown, not 0")
        #expect(review().averageCarbs == nil && review().averageFat == nil)
        #expect(review().carbsDays == 0)
    }

    @Test func carbsAndFat_foreignValueAloneOpensTheDay() {
        let own = DayIntake(kcal: 0, kcalMin: 0, kcalMax: 0, protein: 0, carbs: 0, fat: 0, waterMilliliters: 0, hasEstimate: false)
        let foreign = ForeignIntake(kcal: 700, carbs: 90, sources: ["Yazio"])
        let result = WeekReview.make(weekStart: monday, now: instant(2026, 11, 25, 9, 0, in: calendar), meals: [], drinks: [],
                                     workouts: [], completedDates: [], goals: goals,
                                     totals: [day(16): IntakeTotals(own: own, foreign: foreign)], calendar: calendar)
        #expect(result.days[0].carbs == 90)
        #expect(result.days[0].fat == nil, "the other app gave no fat value")
        #expect(result.averageCarbs == 90)
        #expect(result.averageFat == nil)
    }

    @Test func macroGoals_followTheScaledGoalOfEachDay() {
        let base = GoalPlan(validFrom: monday, kcal: 2000, carbsGrams: 250, fatGrams: 70, waterMilliliters: 2000, stepsPerDay: 8000,
                            workoutMinutesPerWeek: 150)
        let active = budget(base, active: 800, eaten: 2000)
        let rest = budget(base, active: nil, eaten: 2000)
        let meals = [meal(day: 16, kcal: 2000, carbs: 200, fat: 60), meal(day: 17, kcal: 2000, carbs: 200, fat: 60)]
        let result = budgetedReview(meals: meals, budgets: [day(16): active, day(17): rest])
        let carbGoals = [active.scaledCarbs!, rest.scaledCarbs!]
        let fatGoals = [active.scaledFat!, rest.scaledFat!]
        #expect(carbGoals[0] > 250 && carbGoals[1] == 250, "activity grows the carbohydrate goal of that day only")
        #expect(result.averageGoalCarbs == Int((Double(carbGoals.reduce(0, +)) / 2).rounded()))
        #expect(result.averageGoalFat == Int((Double(fatGoals.reduce(0, +)) / 2).rounded()))
    }

    @Test func macroGoals_withoutAGoal_areUnknown() {
        let base = plan(kcal: 2000)
        let result = budgetedReview(meals: [meal(day: 16, kcal: 2000, carbs: 200)], budgets: [day(16): budget(base, active: nil, eaten: 2000)])
        #expect(result.averageGoalCarbs == nil)
        #expect(result.averageGoalFat == nil)
    }

    @Test func oldCallersWithoutNewParameters_unchanged() {
        let result = review(meals: [meal(day: 16, kcal: 2000)])
        #expect(result.days[0].goalKcal == 2300)
        #expect(result.daysWithinBudget == 1)
        #expect(result.averageBudgetKcal == 2300)
        #expect(result.goals.fiberGrams == nil && result.goals.sugarLimitGrams == nil)
    }

    // MARK: Texts

    private let german = Locale(identifier: "de_DE")

    @Test func weekBudgetDays_text() {
        #expect(IntakeFormat.weekBudgetDays(within: 4, of: 5) == "Im Budget an 4 von 5 Tagen")
        #expect(IntakeFormat.weekBudgetDays(within: 0, of: 1) == "Im Budget an 0 von 1 Tagen")
    }

    @Test func weekBudgetAverage_text() {
        #expect(IntakeFormat.weekBudgetAverage(2450, locale: german) == "Ø Budget 2.450 kcal")
    }

    @Test func weekMacro_meanAgainstGoal_unknownStaysDash() {
        #expect(IntakeFormat.weekMacro(mean: 118.4, days: 5, goal: 140, estimated: true) == "Ø ~118 g / 140 g an 5 Tagen")
        #expect(IntakeFormat.weekMacro(mean: 218, days: 5, goal: nil, estimated: false) == "Ø 218 g an 5 Tagen")
        #expect(IntakeFormat.weekMacro(mean: nil, days: 0, goal: 140, estimated: true) == "–")
        #expect(IntakeFormat.weekMacro(mean: 0, days: 0, goal: nil, estimated: false) == "–", "no day knows the value")
    }

    @Test func weekNutrient_withAndWithoutGoal() {
        #expect(IntakeFormat.weekNutrient(.fiber, mean: 22.3, days: 4, goal: 30, locale: german) == "Ø 22 / 30 g an 4 Tagen")
        #expect(IntakeFormat.weekNutrient(.sugar, mean: 61, days: 3, goal: 50, locale: german) == "Ø 61 / max. 50 g an 3 Tagen")
        #expect(IntakeFormat.weekNutrient(.salt, mean: 5.4, days: 2, goal: nil, locale: german) == "Ø 5,4 g an 2 Tagen")
        #expect(IntakeFormat.weekNutrient(.sugar, mean: nil, days: 0, goal: 50, locale: german) == "–")
    }
}
