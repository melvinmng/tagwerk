import Foundation
import HealthBridge
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct IntakeStoreTests {
    let container: ModelContainer
    let store: IntakeStore
    let calendar = Calendar.tagwerk
    let today = PlanDay(year: 2026, month: 11, day: 18)
    var noon: Date { today.startDate(in: calendar).addingTimeInterval(12 * 3600) }

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        store = IntakeStore(context: container.mainContext)
    }

    func meal(_ title: String = "Müsli", at date: Date? = nil, kcal: Double = 400) -> MealValue {
        MealValue(id: UUID(), date: date ?? noon, kind: .lunch, title: title,
                  items: [MealItem(name: title, amount: "1 Schale", kcalMin: kcal - 50, kcal: kcal, kcalMax: kcal + 50,
                                   protein: 12, carbs: 60, fat: 8, isEstimated: true)],
                  origin: .estimated)
    }

    @Test func addMeal_thenDay_returnsIt_otherDayNot() {
        let lunch = meal()
        store.addMeal(lunch, estimatedAt: noon)
        #expect(store.meals(on: today, calendar: calendar) == [lunch])
        #expect(store.meals(on: today.adding(days: 1, calendar: calendar), calendar: calendar).isEmpty)
        #expect(store.estimatedAt(meal: lunch.id) == noon)
    }

    @Test func update_bumpsVersion_marksUnsynced() {
        var lunch = meal()
        store.addMeal(lunch, estimatedAt: nil)
        store.markSynced(lunch.id, version: 1)
        #expect(store.unsyncedEntries().isEmpty)
        lunch.title = "Porridge"
        store.updateMeal(lunch, estimatedAt: nil)
        let unsynced = store.unsyncedEntries()
        #expect(unsynced.count == 1)
        #expect(unsynced.first?.version == 2)
        // A sync of the old version does not mark the edited entry as mirrored.
        store.markSynced(lunch.id, version: 1)
        #expect(store.unsyncedEntries().count == 1)
    }

    @Test func delete_queuesHealthDeletion_restore_dropsIt() throws {
        let drink = DrinkValue(id: UUID(), date: noon, milliliters: 250)
        store.addDrink(drink)
        let deleted = try #require(store.delete(drink.id, healthNotBefore: noon.addingTimeInterval(4)))
        #expect(store.drinks(on: today, calendar: calendar).isEmpty)
        #expect(store.dueDeletions(now: noon).isEmpty)
        #expect(store.dueDeletions(now: noon.addingTimeInterval(5)) == [drink.id])
        store.restore(deleted)
        #expect(store.drinks(on: today, calendar: calendar) == [drink])
        #expect(store.dueDeletions(now: noon.addingTimeInterval(5)).isEmpty)
        #expect(store.unsyncedEntries().first?.version == 2)
    }

    @Test func mealsSince_newestFirst() {
        let older = meal("Pizza", at: noon.addingTimeInterval(-86_400))
        let newer = meal("Salat", at: noon)
        store.addMeal(older, estimatedAt: nil)
        store.addMeal(newer, estimatedAt: nil)
        #expect(store.meals(since: noon.addingTimeInterval(-2 * 86_400)).map(\.title) == ["Salat", "Pizza"])
    }

    @Test func workouts_inInterval_andLatest() {
        let run = WorkoutValue(id: UUID().uuidString, activity: .running, start: noon, minutes: 30, kilocalories: 250,
                               sourceName: nil, isOwn: true)
        store.addWorkout(run)
        #expect(store.workouts(in: DateInterval(start: noon.addingTimeInterval(-60), duration: 3600)) == [run])
        #expect(store.latestWorkout() == run)
    }

    @Test func drinksInInterval_returnsOnlyDrinksInside() {
        let inside = DrinkValue(id: UUID(), date: noon, milliliters: 250)
        let before = DrinkValue(id: UUID(), date: today.adding(days: -1, calendar: calendar).startDate(in: calendar).addingTimeInterval(-60), milliliters: 300)
        let after = DrinkValue(id: UUID(), date: today.adding(days: 1, calendar: calendar).startDate(in: calendar), milliliters: 400)
        [inside, before, after].forEach { store.addDrink($0) }
        let interval = DateInterval(start: today.startDate(in: calendar), end: today.adding(days: 1, calendar: calendar).startDate(in: calendar))
        #expect(store.drinks(in: interval).map(\.milliliters) == [250])
    }
}

@MainActor
struct HealthMirrorTests {
    let container: ModelContainer
    let store: IntakeStore
    let health = FakeHealthStore()
    var current = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        store = IntakeStore(context: container.mainContext)
    }

    func mirror(_ health: FakeHealthStore? = nil, at date: Date? = nil) -> HealthMirror {
        let instant = date ?? current
        return HealthMirror(store: store, health: health ?? self.health, now: { instant })
    }

    func drink(_ ml: Int = 250) -> DrinkValue { DrinkValue(id: UUID(), date: current, milliliters: ml) }

    @Test func save_success_marksSynced() async {
        store.addDrink(drink())
        await mirror().sync()
        #expect(health.drinks.count == 1)
        #expect(store.unsyncedEntries().isEmpty)
    }

    @Test func save_failure_keepsLocal_unsynced_thenRetried() async {
        let entry = drink()
        store.addDrink(entry)
        health.failWrites = true
        await mirror().sync()
        #expect(store.unsyncedEntries().count == 1)
        #expect(store.exists(entry.id))
        health.failWrites = false
        await mirror().sync()
        #expect(health.drinks.count == 1)
        #expect(store.unsyncedEntries().isEmpty)
    }

    private func workout() -> WorkoutValue {
        WorkoutValue(id: UUID().uuidString, activity: .running, start: current, minutes: 30, kilocalories: 250, sourceName: nil, isOwn: true)
    }

    @Test func workoutMirrored_remembersThatTheCaloriesWentToHealth() async {
        let entry = workout()
        store.addWorkout(entry)
        await mirror().sync()
        let energy = store.ownWorkoutEnergy(on: PlanDay(date: current, calendar: .tagwerk), calendar: .tagwerk, mayWriteEnergy: false)
        // The flag decides, not the permission at the time of the question.
        #expect(energy.map(\.energyInHealth) == [true])
    }

    @Test func workoutMirroredWhileCaloriesAreRefused_remembersThat() async {
        let refused = FakeHealthStore(access: .partial([.activeEnergy]))
        let entry = workout()
        store.addWorkout(entry)
        await mirror(refused).sync()
        let energy = store.ownWorkoutEnergy(on: PlanDay(date: current, calendar: .tagwerk), calendar: .tagwerk, mayWriteEnergy: true)
        #expect(energy.map(\.energyInHealth) == [false])
        #expect(store.unsyncedEntries().isEmpty, "the workout itself counts as mirrored")
    }

    @Test func unsyncedWorkout_isNeverInsideHealth() {
        store.addWorkout(workout())
        let energy = store.ownWorkoutEnergy(on: PlanDay(date: current, calendar: .tagwerk), calendar: .tagwerk, mayWriteEnergy: true)
        #expect(energy.map(\.energyInHealth) == [false])
    }

    private func mealWithFibre(fibre: Double?, salt: Double? = nil) -> MealValue {
        MealValue(id: UUID(), date: current, kind: .lunch, title: "Brot",
                  items: [MealItem(name: "Brot", amount: "2 Scheiben", kcalMin: 200, kcal: 200, kcalMax: 200, protein: 6, carbs: 36, fat: 2,
                                   fiber: fibre, salt: salt)],
                  origin: .manual)
    }

    @Test func healthValue_carriesTheFurtherNutrientsOnlyWhenEveryItemKnowsThem() {
        let known = IntakeEntry.meal(mealWithFibre(fibre: 4, salt: 1.2)).healthValue(version: 1)
        guard case .meal(let meal) = known else { Issue.record("meal expected"); return }
        #expect(meal.fiber == 4 && meal.salt == 1.2 && meal.sugar == nil && meal.saturatedFat == nil)
        // A partially known meal is not written: the partial sum would look like the whole meal in Health.
        var partial = mealWithFibre(fibre: 4)
        partial.items.append(MealItem(name: "Aufstrich", amount: "", kcalMin: 50, kcal: 50, kcalMax: 50, protein: 0, carbs: 0, fat: 5))
        guard case .meal(let half) = IntakeEntry.meal(partial).healthValue(version: 1) else { Issue.record("meal expected"); return }
        #expect(half.fiber == nil)
    }

    @Test func furtherNutrientsGranted_mirrorsMealsWithSuchValuesAgain_withAHigherVersion() async {
        let withFibre = mealWithFibre(fibre: 4)
        let without = mealWithFibre(fibre: nil)
        store.addMeal(withFibre, estimatedAt: nil)
        store.addMeal(without, estimatedAt: nil)
        await mirror().sync()
        #expect(store.unsyncedEntries().isEmpty)
        #expect(health.meals.count == 2)
        await mirror().furtherNutrientsGranted()
        #expect(health.meals.count == 3, "only the meal with a further nutrient is written again")
        let again = health.meals.last
        #expect(again?.id == withFibre.id && again?.version == 2 && again?.fiber == 4)
        #expect(store.unsyncedEntries().isEmpty)
    }

    @Test func markMealsWithFurtherNutrientsUnsynced_countsAndLeavesOthersAlone() async {
        store.addMeal(mealWithFibre(fibre: 3), estimatedAt: nil)
        store.addMeal(mealWithFibre(fibre: nil), estimatedAt: nil)
        await mirror().sync()
        #expect(store.markMealsWithFurtherNutrientsUnsynced() == 1)
        #expect(store.unsyncedEntries().count == 1)
    }

    @Test func deniedType_skippedWithoutError_staysUnsynced() async {
        store.addDrink(drink())
        health.incompleteWrites = true
        await mirror().sync()
        #expect(store.unsyncedEntries().count == 1)
    }

    @Test func notDetermined_sendsNothing() async {
        let undetermined = FakeHealthStore(access: .notDetermined)
        store.addDrink(drink())
        await mirror(undetermined).sync()
        #expect(undetermined.drinks.isEmpty)
        #expect(undetermined.authorizationRequests == 0)
    }

    @Test func update_sendsHigherVersion() async {
        var entry = drink()
        store.addDrink(entry)
        await mirror().sync()
        entry.milliliters = 500
        store.updateDrink(entry)
        await mirror().sync()
        #expect(health.drinks.map(\.version) == [1, 2])
        #expect(health.drinks.last?.milliliters == 500)
    }

    @Test func concurrentSync_writesOnce() async {
        store.addDrink(drink())
        let mirror = mirror()
        async let first: Void = mirror.sync()
        async let second: Void = mirror.sync()
        _ = await (first, second)
        #expect(health.drinks.count == 1)
    }

    @Test func delete_waitsForUndoWindow_thenDeletes() async {
        let entry = drink()
        store.addDrink(entry)
        await mirror().sync()
        store.delete(entry.id, healthNotBefore: current.addingTimeInterval(HealthMirror.undoWindow))
        await mirror().sync()
        #expect(health.deleted.isEmpty)
        await mirror(at: current.addingTimeInterval(5)).sync()
        #expect(health.deleted == [entry.id])
        #expect(store.dueDeletions(now: current.addingTimeInterval(5)).isEmpty)
    }

    @Test func delete_failure_queued_thenRetried() async {
        let entry = drink()
        store.addDrink(entry)
        store.delete(entry.id, healthNotBefore: current)
        health.failWrites = true
        await mirror().sync()
        #expect(store.dueDeletions(now: current) == [entry.id])
        health.failWrites = false
        await mirror().sync()
        #expect(health.deleted == [entry.id])
    }

    @Test func deletion_survivesRestart() async throws {
        let entry = drink()
        store.addDrink(entry)
        store.delete(entry.id, healthNotBefore: current)
        let reopened = IntakeStore(context: ModelContext(container))
        await HealthMirror(store: reopened, health: health, now: { [current] in current }).sync()
        #expect(health.deleted == [entry.id])
    }

    @Test func restoredEntry_isNotDeletedInHealth() async throws {
        let entry = drink()
        store.addDrink(entry)
        let deleted = try #require(store.delete(entry.id, healthNotBefore: current))
        store.restore(deleted)
        await mirror().sync()
        #expect(health.deleted.isEmpty)
        #expect(health.drinks.map(\.version) == [2])
    }
}

@MainActor
struct HealthMirrorQueueTests {
    @Test func notAsked_dropsQueuedDeletions() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = IntakeStore(context: container.mainContext)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let drink = DrinkValue(id: UUID(), date: now, milliliters: 250)
        store.addDrink(drink)
        store.delete(drink.id, healthNotBefore: now)
        let health = FakeHealthStore(access: .notDetermined)
        await HealthMirror(store: store, health: health, now: { now }).sync()
        #expect(store.dueDeletions(now: now).isEmpty)
        #expect(health.deleted.isEmpty)
    }

    @Test func deletion_passesEntryKind() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = IntakeStore(context: container.mainContext)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let drink = DrinkValue(id: UUID(), date: now, milliliters: 250)
        store.addDrink(drink)
        store.delete(drink.id, healthNotBefore: now)
        #expect(store.dueDeletionEntries(now: now).first?.kind == .drink)
    }

    @Test func entryKinds_coverTheirTypesOnly() {
        #expect(HealthEntryKind.drink.shareKinds == [.water])
        #expect(HealthEntryKind.workout.shareKinds == [.workouts, .activeEnergy])
        #expect(HealthEntryKind.meal.shareKinds.count == 4)
    }
}
