import Foundation
import Testing
@testable import TagwerkCore

struct WeekReviewTests {
    let calendar = makeCalendar()
    /// Monday, 16 Nov 2026.
    let monday = PlanDay(year: 2026, month: 11, day: 16)
    let goals = WeekReview.Goals(kcal: 2300, waterMilliliters: 2000, workoutMinutesPerWeek: 150, stepsPerDay: 8000, proteinGrams: nil)

    private func meal(day: Int, kcal: Double, estimated: Bool = true, protein: Double = 0) -> MealValue {
        let item = MealItem(name: "x", amount: "1", kcalMin: kcal, kcal: kcal, kcalMax: kcal, protein: protein, carbs: 0, fat: 0,
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

    @Test func review_proteinOnlyWhenGoalEnabled() {
        let meals = [meal(day: 16, kcal: 2000, protein: 100), meal(day: 17, kcal: 2000, protein: 60)]
        #expect(review(meals: meals).averageProtein == nil)
        let withGoal = review(meals: meals, goals: WeekReview.Goals(kcal: 2300, waterMilliliters: 2000, workoutMinutesPerWeek: 150,
                                                                     stepsPerDay: 8000, proteinGrams: 120))
        #expect(withGoal.averageProtein == 80)
    }

    @Test func review_weekTitle() {
        #expect(WeekReview.title(weekStart: monday, calendar: calendar) == "KW 47 · 16.–22. Nov")
        let crossing = PlanDay(year: 2026, month: 11, day: 30)
        #expect(WeekReview.title(weekStart: crossing, calendar: calendar) == "KW 49 · 30. Nov – 6. Dez")
        // Month names follow the locale; the words around them stay German until the English texts exist.
        #expect(WeekReview.title(weekStart: crossing, calendar: calendar, locale: Locale(identifier: "en_US")) == "KW 49 · 30. Nov – 6. Dec")
    }

    @Test func planHeaderLine_estimatedTilde() {
        let intake = DayIntake(kcal: 1243, kcalMin: 1100, kcalMax: 1400, protein: 0, carbs: 0, fat: 0, waterMilliliters: 1200,
                               hasEstimate: true)
        #expect(IntakeFormat.planHeaderLine(intake: intake, goalKcal: 2300, goalWaterMilliliters: 2000, hasEntries: true)
            == "~1.240 / 2.300 kcal · 1,2 / 2,0 l")
    }

    @Test func planHeaderLine_manualNoTilde() {
        let intake = DayIntake(kcal: 1243, kcalMin: 1243, kcalMax: 1243, protein: 0, carbs: 0, fat: 0, waterMilliliters: 0,
                               hasEstimate: false)
        #expect(IntakeFormat.planHeaderLine(intake: intake, goalKcal: 2300, goalWaterMilliliters: 2000, hasEntries: true)
            == "1.243 / 2.300 kcal · 0 / 2,0 l")
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

    @Test func planHeaderLine_appendsTodaysSteps() {
        let intake = DayIntake(kcal: 1243, kcalMin: 1100, kcalMax: 1400, protein: 0, carbs: 0, fat: 0, waterMilliliters: 1200,
                               hasEstimate: true)
        #expect(IntakeFormat.planHeaderLine(intake: intake, goalKcal: 2300, goalWaterMilliliters: 2000, hasEntries: true, steps: 6412)
            == "~1.240 / 2.300 kcal · 1,2 / 2,0 l · 6.412 Schritte")
        // Steps alone do not open the line: it still starts with the first entry of the day.
        #expect(IntakeFormat.planHeaderLine(intake: .empty, goalKcal: 2300, goalWaterMilliliters: 2000, hasEntries: false,
                                            steps: 6412) == nil)
    }

    @Test func planHeaderLine_nilWhenNoEntries() {
        #expect(IntakeFormat.planHeaderLine(intake: .empty, goalKcal: 2300, goalWaterMilliliters: 2000, hasEntries: false) == nil)
    }
}
