import Foundation
import HealthBridge
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The budget of a day from its plan, its entries and its stored Health values (nutrition plan, strand C1).
@MainActor
struct DayBudgetsTests {
    let container: ModelContainer
    let intake: IntakeStore
    let goals: GoalStore
    let dayHealth: DayHealthStore
    let settings: AppSettings
    let calendar = Calendar.tagwerk
    let today = PlanDay(year: 2026, month: 11, day: 18)
    var noon: Date { today.startDate(in: calendar).addingTimeInterval(12 * 3600 + 40 * 60) }

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        let noon = PlanDay(year: 2026, month: 11, day: 18).startDate(in: .tagwerk).addingTimeInterval(12 * 3600 + 40 * 60)
        settings = try AppSettings.current(in: container.mainContext)
        intake = IntakeStore(context: container.mainContext)
        goals = GoalStore(context: container.mainContext, settings: settings, calendar: .tagwerk, now: { noon })
        dayHealth = DayHealthStore(context: container.mainContext, now: { noon })
        goals.adopt(GoalPlan(validFrom: PlanDay(year: 2026, month: 10, day: 1), kcal: 2300, carbsGrams: 250, fatGrams: 78,
                             waterMilliliters: 2000, stepsPerDay: 8000, workoutMinutesPerWeek: 150))
    }

    private func makeBudgets(_ health: FakeHealthStore) -> DayBudgets {
        let noon = self.noon
        return DayBudgets(intake: intake, goals: goals, dayHealth: dayHealth, health: health, settings: settings,
                          calendar: calendar, now: { noon })
    }

    private func week(of day: PlanDay) -> DateInterval {
        let start = IntakeRules.weekStart(containing: day.startDate(in: calendar), calendar: calendar)
        return DateInterval(start: start, end: PlanDay(date: start, calendar: calendar).adding(days: 7, calendar: calendar).startDate(in: calendar))
    }

    private func energy(_ kcal: Double, on day: PlanDay) -> DailyActiveEnergy {
        DailyActiveEnergy(start: day.startDate(in: calendar), kilocalories: kcal)
    }

    private func ownWorkout(kcal: Double, on day: PlanDay, synced: Bool, energyInHealth: Bool?) {
        let id = UUID()
        let start = day.startDate(in: calendar).addingTimeInterval(8 * 3600)
        intake.addWorkout(WorkoutValue(id: id.uuidString, activity: .running, start: start, minutes: 40, kilocalories: kcal,
                                       sourceName: nil, isOwn: true))
        if synced { intake.markSynced(id, version: 1, energyInHealth: energyInHealth) }
    }

    private func meal(kcal: Double, on day: PlanDay) -> DayIntake {
        let item = MealItem(name: "Essen", amount: "1", kcalMin: kcal, kcal: kcal, kcalMax: kcal, protein: 20, carbs: 40, fat: 10)
        return IntakeRules.dayIntake(meals: [MealValue(id: UUID(), date: day.startDate(in: calendar).addingTimeInterval(9 * 3600),
                                                       kind: .breakfast, title: "Essen", items: [item], origin: .manual)], drinks: [])
    }

    // MARK: Plan and credit

    @Test func budget_usesPlanOfShownDay() {
        goals.adopt(GoalPlan(validFrom: today, kcal: 2000, waterMilliliters: 2000, stepsPerDay: 8000, workoutMinutesPerWeek: 150))
        let budgets = makeBudgets(FakeHealthStore())
        let yesterday = today.adding(days: -1, calendar: calendar)
        #expect(budgets.figures(on: yesterday, own: .empty).budget.base == 2300)
        #expect(budgets.figures(on: today, own: .empty).budget.base == 2000)
    }

    @Test func budget_healthSumPlusUnsyncedOwn() async {
        let health = FakeHealthStore()
        health.setGroupAccess(.asked, for: .activeEnergy)
        health.activeEnergy = [energy(520, on: today)]
        ownWorkout(kcal: 300, on: today, synced: false, energyInHealth: nil)
        settings.activityCreditPercent = 100
        let budgets = makeBudgets(health)
        await budgets.refreshHealth(in: week(of: today))
        let figures = budgets.figures(on: today, own: meal(kcal: 1340, on: today))
        #expect(figures.active.total == 820, "the Health sum plus the workout Health does not hold yet")
        #expect(figures.budget.credited == 820 && figures.budget.budget == 3120)
        #expect(Int(figures.budget.remaining.rounded()) == 1780)
    }

    @Test func budget_ownWorkoutMirroredWithCalories_countsOnce() async {
        let health = FakeHealthStore()
        health.setGroupAccess(.asked, for: .activeEnergy)
        health.activeEnergy = [energy(820, on: today)]
        ownWorkout(kcal: 300, on: today, synced: true, energyInHealth: true)
        let budgets = makeBudgets(health)
        await budgets.refreshHealth(in: week(of: today))
        #expect(budgets.figures(on: today, own: .empty).active.total == 820)
    }

    @Test func budget_workoutMirroredWhileCaloriesWereRefused_staysAGapFillerEvenIfAllowedLater() async {
        let health = FakeHealthStore(access: .authorized)
        health.setGroupAccess(.asked, for: .activeEnergy)
        health.activeEnergy = [energy(520, on: today)]
        // Mirrored when the calories type was denied; the user allowed it afterwards.
        ownWorkout(kcal: 300, on: today, synced: true, energyInHealth: false)
        let budgets = makeBudgets(health)
        await budgets.refreshHealth(in: week(of: today))
        #expect(budgets.figures(on: today, own: .empty).active.total == 820)
    }

    @Test func budget_workoutMirroredWithCalories_staysInsideWhenPermissionIsRevokedLater() async {
        let health = FakeHealthStore(access: .partial([.activeEnergy]))
        health.setGroupAccess(.asked, for: .activeEnergy)
        health.activeEnergy = [energy(820, on: today)]
        ownWorkout(kcal: 300, on: today, synced: true, energyInHealth: true)
        let budgets = makeBudgets(health)
        await budgets.refreshHealth(in: week(of: today))
        #expect(budgets.figures(on: today, own: .empty).active.total == 820, "the sample is still in Health")
    }

    @Test func budget_workoutMirroredBeforeTheFlagExisted_followsTheCurrentPermission() async {
        let health = FakeHealthStore(access: .partial([.activeEnergy]))
        health.setGroupAccess(.asked, for: .activeEnergy)
        health.activeEnergy = [energy(520, on: today)]
        ownWorkout(kcal: 300, on: today, synced: true, energyInHealth: nil)
        let denied = makeBudgets(health)
        await denied.refreshHealth(in: week(of: today))
        #expect(denied.figures(on: today, own: .empty).active.total == 820)
        health.currentAccess = .authorized
        let allowed = makeBudgets(health)
        await allowed.refreshHealth(in: week(of: today))
        #expect(allowed.figures(on: today, own: .empty).active.total == 520)
    }

    @Test func budget_withoutHealth_ownWorkoutsOnly() async {
        let health = FakeHealthStore()
        ownWorkout(kcal: 300, on: today, synced: true, energyInHealth: true)
        let budgets = makeBudgets(health)
        await budgets.refreshHealth(in: week(of: today))
        let figures = budgets.figures(on: today, own: .empty)
        #expect(figures.active.total == 300 && !figures.active.isFromHealth)
        #expect(health.activeEnergyReads.isEmpty, "the group was never asked, so nothing is read")
    }

    @Test func budget_defaultCreditIsHalf() async {
        let health = FakeHealthStore()
        health.setGroupAccess(.asked, for: .activeEnergy)
        health.activeEnergy = [energy(520, on: today)]
        let budgets = makeBudgets(health)
        await budgets.refreshHealth(in: week(of: today))
        let figures = budgets.figures(on: today, own: .empty)
        #expect(figures.budget.credited == 260 && figures.budget.budget == 2560)
    }

    // MARK: Foreign entries

    @Test func eaten_ownPlusForeign_whenSwitchedOn() async {
        let health = FakeHealthStore()
        health.setGroupAccess(.asked, for: .foreignNutrition)
        health.addForeignNutrition(day: today.startDate(in: calendar).addingTimeInterval(10 * 3600), kilocalories: 400, source: "Yazio")
        settings.countsForeignNutrition = true
        let budgets = makeBudgets(health)
        await budgets.refreshHealth(in: week(of: today))
        let figures = budgets.figures(on: today, own: meal(kcal: 600, on: today))
        #expect(figures.totals.kcal == 1000)
        #expect(figures.totals.foreign?.sources == ["Yazio"])
        #expect(figures.budget.eatenKcal == 1000)
    }

    @Test func eaten_ownOnly_whenSwitchedOff_andNoForeignReadHappens() async {
        let health = FakeHealthStore()
        health.setGroupAccess(.asked, for: .foreignNutrition)
        health.addForeignNutrition(day: today.startDate(in: calendar).addingTimeInterval(10 * 3600), kilocalories: 400, source: "Yazio")
        settings.countsForeignNutrition = false
        let budgets = makeBudgets(health)
        await budgets.refreshHealth(in: week(of: today))
        #expect(health.nutritionReads.isEmpty, "a switched-off feature never asks Health")
        let figures = budgets.figures(on: today, own: meal(kcal: 600, on: today))
        #expect(figures.totals.kcal == 600 && figures.totals.foreign == nil)
    }

    @Test func eaten_foreignStoredButSwitchedOff_isIgnored() async {
        let health = FakeHealthStore()
        health.setGroupAccess(.asked, for: .foreignNutrition)
        health.addForeignNutrition(day: today.startDate(in: calendar).addingTimeInterval(10 * 3600), kilocalories: 400, source: "Yazio")
        settings.countsForeignNutrition = true
        let budgets = makeBudgets(health)
        await budgets.refreshHealth(in: week(of: today))
        settings.countsForeignNutrition = false
        #expect(budgets.figures(on: today, own: meal(kcal: 600, on: today)).totals.kcal == 600)
    }

    @Test func foreignRead_withoutTheGroupAsked_isSkipped() async {
        let health = FakeHealthStore()
        settings.countsForeignNutrition = true
        await makeBudgets(health).refreshHealth(in: week(of: today))
        #expect(health.nutritionReads.isEmpty)
    }

    // MARK: Stored values of past days

    @Test func pastDay_usesStoredDayHealthWhenHealthSilent() async {
        let health = FakeHealthStore()
        health.setGroupAccess(.asked, for: .activeEnergy)
        let yesterday = today.adding(days: -1, calendar: calendar)
        health.activeEnergy = [energy(600, on: yesterday)]
        let budgets = makeBudgets(health)
        await budgets.refreshHealth(in: week(of: today))
        #expect(budgets.figures(on: yesterday, own: .empty).active.healthKcal == 600)
        // Health now delivers nothing for that day (denied, locked or deleted): the stored value stays.
        health.activeEnergy = []
        await budgets.refreshHealth(in: week(of: today))
        #expect(budgets.figures(on: yesterday, own: .empty).active.healthKcal == 600)
    }

    @Test func today_isReplacedByEachRead() async {
        let health = FakeHealthStore()
        health.setGroupAccess(.asked, for: .activeEnergy)
        health.activeEnergy = [energy(300, on: today)]
        let budgets = makeBudgets(health)
        await budgets.refreshHealth(in: week(of: today))
        health.activeEnergy = [energy(450, on: today)]
        await budgets.refreshHealth(in: week(of: today))
        #expect(budgets.figures(on: today, own: .empty).active.healthKcal == 450)
    }

    @Test func failedRead_changesNothing() async {
        let health = FakeHealthStore()
        health.setGroupAccess(.asked, for: .activeEnergy)
        health.activeEnergy = [energy(300, on: today)]
        let budgets = makeBudgets(health)
        await budgets.refreshHealth(in: week(of: today))
        health.failActiveEnergyReads = true
        await budgets.refreshHealth(in: week(of: today))
        #expect(budgets.figures(on: today, own: .empty).active.healthKcal == 300)
    }

    @Test func pastDay_keepsItsCreditShare() async {
        let health = FakeHealthStore()
        health.setGroupAccess(.asked, for: .activeEnergy)
        let yesterday = today.adding(days: -1, calendar: calendar)
        health.activeEnergy = [energy(600, on: yesterday)]
        settings.activityCreditPercent = 100
        let budgets = makeBudgets(health)
        await budgets.refreshHealth(in: week(of: today))
        settings.activityCreditPercent = 50
        #expect(budgets.figures(on: yesterday, own: .empty).budget.credited == 600, "the day keeps the share that counted on it")
        #expect(budgets.figures(on: today, own: .empty).budget.creditPercent == 50, "today follows the current setting")
    }

    @Test func futureDays_areNeverStored() async {
        let health = FakeHealthStore()
        health.setGroupAccess(.asked, for: .activeEnergy)
        let tomorrow = today.adding(days: 1, calendar: calendar)
        health.activeEnergy = [energy(100, on: tomorrow)]
        let budgets = makeBudgets(health)
        await budgets.refreshHealth(in: week(of: today))
        #expect(dayHealth.value(on: tomorrow) == nil)
    }
}
