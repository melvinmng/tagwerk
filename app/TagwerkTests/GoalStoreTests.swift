import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct GoalStoreTests {
    let container: ModelContainer
    let settings: AppSettings
    let calendar = Calendar.tagwerk
    let today = PlanDay(year: 2026, month: 11, day: 22)
    var noon: Date { today.startDate(in: calendar).addingTimeInterval(12 * 3600) }

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
    }

    private func makeStore() -> GoalStore {
        let noon = self.noon
        return GoalStore(context: container.mainContext, settings: settings, calendar: calendar, now: { noon })
    }

    private func plan(on day: PlanDay, kcal: Int, protein: Int? = nil) -> GoalPlan {
        GoalPlan(validFrom: day, kcal: kcal, proteinGrams: protein, waterMilliliters: 2000, stepsPerDay: 8000, workoutMinutesPerWeek: 150)
    }

    @Test func migration_createsOnePlanFromSettings() {
        settings.goalKilocalories = 2150
        settings.goalWaterMilliliters = 2400
        settings.goalStepsPerDay = 9000
        settings.goalWorkoutMinutesPerWeek = 120
        settings.proteinGoalEnabled = true
        settings.goalProteinGrams = 130
        let store = makeStore()
        store.migrateIfNeeded()
        let plans = store.plans()
        #expect(plans.count == 1)
        #expect(plans.first?.kcal == 2150 && plans.first?.waterMilliliters == 2400)
        #expect(plans.first?.stepsPerDay == 9000 && plans.first?.workoutMinutesPerWeek == 120)
        #expect(plans.first?.proteinGrams == 130)
        #expect(plans.first?.validFrom == today, "without meals the plan holds from today")
        #expect(settings.goalPlansMigrated)
    }

    @Test func migration_proteinGoalOffMeansNoProteinGoal() {
        settings.proteinGoalEnabled = false
        let store = makeStore()
        store.migrateIfNeeded()
        #expect(store.plans().first?.proteinGrams == nil)
    }

    @Test func migration_startsAtTheOldestMeal() {
        let oldDay = PlanDay(year: 2026, month: 10, day: 3)
        let oldMeal = MealValue(id: UUID(), date: oldDay.startDate(in: calendar).addingTimeInterval(8 * 3600), kind: .breakfast,
                                title: "Müsli", items: [], origin: .manual)
        container.mainContext.insert(MealRecord(oldMeal, estimatedAt: nil))
        let store = makeStore()
        store.migrateIfNeeded()
        #expect(store.plans().first?.validFrom == oldDay)
        // Every day since then reads the same goals.
        #expect(store.current(on: PlanDay(year: 2026, month: 10, day: 20))?.kcal == settings.goalKilocalories)
    }

    @Test func migration_runsOnce() {
        let store = makeStore()
        store.migrateIfNeeded()
        settings.goalKilocalories = 1800
        store.migrateIfNeeded()
        #expect(store.plans().count == 1)
        #expect(store.plans().first?.kcal == 2300)
    }

    @Test func migration_keepsExistingPlans() {
        let store = makeStore()
        store.adopt(plan(on: today, kcal: 1900))
        store.migrateIfNeeded()
        #expect(store.plans().map(\.kcal) == [1900])
        #expect(settings.goalPlansMigrated)
    }

    @Test func store_adopt_sameDayReplaces() {
        let store = makeStore()
        store.adopt(plan(on: today, kcal: 2000))
        store.adopt(plan(on: today, kcal: 1800))
        #expect(store.plans().map(\.kcal) == [1800])
    }

    @Test func store_current_usesThePlanOfTheDay() {
        let store = makeStore()
        let earlier = today.adding(days: -10, calendar: calendar)
        store.adopt(plan(on: earlier, kcal: 2300))
        store.adopt(plan(on: today, kcal: 2000))
        #expect(store.current(on: today.adding(days: -1, calendar: calendar))?.kcal == 2300)
        #expect(store.current(on: today)?.kcal == 2000)
        #expect(store.current(on: today.adding(days: 5, calendar: calendar))?.kcal == 2000)
    }

    @Test func store_adopt_writesTheCurrentPlanBackToTheSettings() {
        let store = makeStore()
        store.adopt(plan(on: today, kcal: 1950, protein: 140))
        #expect(settings.goalKilocalories == 1950)
        #expect(settings.proteinGoalEnabled && settings.goalProteinGrams == 140)
        store.adopt(plan(on: today, kcal: 1950, protein: nil))
        #expect(!settings.proteinGoalEnabled)
    }

    @Test func store_adopt_futurePlanDoesNotChangeTheSettingsYet() {
        let store = makeStore()
        store.adopt(plan(on: today, kcal: 2000))
        store.adopt(plan(on: today.adding(days: 7, calendar: calendar), kcal: 1700))
        #expect(settings.goalKilocalories == 2000)
    }

    @Test func store_delete_removesThePlan() {
        let store = makeStore()
        let first = plan(on: today.adding(days: -10, calendar: calendar), kcal: 2300)
        store.adopt(first)
        store.adopt(plan(on: today, kcal: 2000))
        store.delete(store.plans().last!.id)
        #expect(store.plans().map(\.kcal) == [2300])
        #expect(settings.goalKilocalories == 2300)
    }

    @Test func record_roundTripsEveryValue() {
        let value = GoalPlan(validFrom: today, kcal: 2100, proteinGrams: 100, carbsGrams: 230, fatGrams: 70, fiberGrams: 30,
                             sugarLimitGrams: 50, waterMilliliters: 2500, stepsPerDay: 9000, workoutMinutesPerWeek: 180,
                             activeKcalPerDay: 400, targetWeightKg: 70, paceKgPerWeek: -0.3, origin: .assistant, note: "Plan")
        #expect(GoalPlanRecord(value).value == value)
    }

    // MARK: Reconciliation with the single goal fields

    @Test func reconcile_equalValues_changeNothing() {
        let store = makeStore()
        store.migrateIfNeeded()
        let before = store.plans()
        store.reconcileWithSettings()
        #expect(store.plans() == before)
    }

    @Test func reconcile_editedSettings_adoptAPlanFromToday() {
        let store = makeStore()
        store.adopt(GoalPlan(validFrom: today.adding(days: -30, calendar: calendar), kcal: 2300, proteinGrams: 120, carbsGrams: 250,
                             fatGrams: 78, fiberGrams: 30, sugarLimitGrams: 50, waterMilliliters: 2000, stepsPerDay: 8000,
                             workoutMinutesPerWeek: 150))
        // The user changed the goals in the old settings screen after the plan was made.
        settings.goalKilocalories = 2000
        settings.goalStepsPerDay = 10_000
        settings.proteinGoalEnabled = false
        store.reconcileWithSettings()
        let plans = store.plans()
        #expect(plans.count == 2)
        let adopted = plans.last
        #expect(adopted?.validFrom == today && adopted?.kcal == 2000 && adopted?.stepsPerDay == 10_000)
        #expect(adopted?.proteinGrams == nil)
        // Macro, fibre and sugar goals of the former plan survive; the old plan keeps its days.
        #expect(adopted?.carbsGrams == 250 && adopted?.fatGrams == 78 && adopted?.fiberGrams == 30 && adopted?.sugarLimitGrams == 50)
        #expect(plans.first?.kcal == 2300)
        #expect(store.current(on: today.adding(days: -1, calendar: calendar))?.kcal == 2300)
    }

    @Test func reconcile_samePlanDay_replacesInsteadOfAddingAPlan() {
        let store = makeStore()
        store.migrateIfNeeded()
        settings.goalWaterMilliliters = 3000
        store.reconcileWithSettings()
        #expect(store.plans().count == 1)
        #expect(store.plans().first?.waterMilliliters == 3000)
    }

    @Test func reconcile_isIdempotent() {
        let store = makeStore()
        store.migrateIfNeeded()
        settings.goalKilocalories = 1900
        store.reconcileWithSettings()
        store.reconcileWithSettings()
        #expect(store.plans().count == 1 && store.plans().first?.kcal == 1900)
    }
}
