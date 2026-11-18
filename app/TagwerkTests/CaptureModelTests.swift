import Foundation
import HealthBridge
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct CaptureModelTests {
    let container: ModelContainer
    let store: IntakeStore
    let settings: AppSettings
    let calendar = Calendar.tagwerk
    /// Wednesday, 18 Nov 2026, 12:40.
    let now: Date

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        store = IntakeStore(context: container.mainContext)
        settings = try AppSettings.current(in: container.mainContext)
        now = PlanDay(year: 2026, month: 11, day: 18).startDate(in: .tagwerk).addingTimeInterval(12 * 3600 + 40 * 60)
    }

    func make(_ health: FakeHealthStore = FakeHealthStore()) -> CaptureModel {
        let instant = now
        let mirror = HealthMirror(store: store, health: health, now: { instant })
        return CaptureModel(store: store, mirror: mirror, health: health, settings: settings, calendar: calendar,
                            now: { instant })
    }

    func meal(_ title: String, at date: Date) -> MealValue {
        MealValue(id: UUID(), date: date, kind: .breakfast, title: title,
                  items: [MealItem(name: title, amount: "1 Schale", kcalMin: 350, kcal: 400, kcalMax: 450, protein: 12,
                                   carbs: 60, fat: 8, isEstimated: true)],
                  origin: .estimated)
    }

    @Test func addWater_updatesTotal_andUndoRemovesIt() async {
        let model = make()
        await model.reload()
        await model.addWater(250)
        await model.addWater(500)
        #expect(model.intake.waterMilliliters == 750)
        #expect(model.undo?.text == "500 ml Wasser erfasst")
        await model.undoLast()
        #expect(model.intake.waterMilliliters == 250)
        #expect(model.undo == nil)
    }

    @Test func repeatMeal_usesNow_kindByTime_copiesItems() async {
        let breakfast = meal("Müsli", at: now.addingTimeInterval(-86_400 - 5 * 3600))
        store.addMeal(breakfast, estimatedAt: nil)
        let model = make()
        await model.reload()
        await model.repeatMeal(breakfast)
        let copy = try? #require(model.meals.first)
        #expect(copy?.id != breakfast.id)
        #expect(copy?.date == now)
        #expect(copy?.kind == .lunch)
        #expect(copy?.items == breakfast.items)
        #expect(copy?.origin == .estimated)
        #expect(model.undo?.text == "Müsli erfasst")
    }

    @Test func delete_thenUndo_restores() async {
        let lunch = meal("Salat", at: now)
        store.addMeal(lunch, estimatedAt: nil)
        let model = make()
        await model.reload()
        await model.delete(lunch.id)
        #expect(model.meals.isEmpty)
        #expect(model.undo?.text == "Eintrag gelöscht")
        await model.undoLast()
        #expect(model.meals.map(\.id) == [lunch.id])
    }

    @Test func foreignWorkouts_merged_weekCountIncludesThem() async {
        let health = FakeHealthStore()
        health.foreign = [ForeignWorkout(id: UUID(), activityName: "Rudern", activity: nil, start: now.addingTimeInterval(-5 * 3600),
                                         end: now.addingTimeInterval(-4 * 3600), kilocalories: 300, sourceName: "Apple Watch")]
        let model = make(health)
        await model.reload()
        await model.saveWorkout(WorkoutValue(id: UUID().uuidString, activity: .strength, start: now.addingTimeInterval(-3600),
                                             minutes: 45, kilocalories: nil, sourceName: nil, isOwn: true), isNew: true)
        #expect(model.workouts.map(\.displayName) == ["Rudern", "Krafttraining"])
        #expect(model.workouts.first?.isOwn == false)
        #expect(model.weekCount == 2)
    }

    @Test func pastDay_readsThatWeek() async {
        let health = FakeHealthStore()
        let model = make(health)
        await model.reload()
        await model.goBack(days: 7)
        let interval = try? #require(health.foreignReads.last)
        // Week of Wednesday 11 Nov: Monday 9 Nov to Monday 16 Nov.
        #expect(interval?.start == PlanDay(year: 2026, month: 11, day: 9).startDate(in: calendar))
        #expect(interval?.end == PlanDay(year: 2026, month: 11, day: 16).startDate(in: calendar))
    }

    @Test func cannotGoPastToday() async {
        let model = make()
        await model.reload()
        #expect(!model.canGoForward)
        await model.goBack(days: 1)
        #expect(model.canGoForward)
        await model.goForward()
        await model.goForward()
        #expect(model.day == PlanDay(date: now, calendar: calendar))
    }

    @Test func pastDay_entriesGetThatDay() async {
        let model = make()
        await model.reload()
        await model.goBack(days: 1)
        await model.addWater(250)
        #expect(model.drinks.first?.date == now.addingTimeInterval(-86_400))
    }

    @Test func healthCard_onlyWhileNotAsked_andNotDismissed() async {
        let undetermined = FakeHealthStore(access: .notDetermined)
        let model = make(undetermined)
        await model.reload()
        #expect(model.showsHealthCard)
        model.dismissHealthCard()
        #expect(!model.showsHealthCard)
        settings.healthCardDismissed = false
        for access in [HealthAccess.authorized, .denied, .partial([.water]), .unavailable] {
            let model = make(FakeHealthStore(access: access))
            await model.reload()
            #expect(!model.showsHealthCard)
        }
    }

    @Test func reload_notAsked_readsNothing_requestsNothing() async {
        let undetermined = FakeHealthStore(access: .notDetermined)
        let model = make(undetermined)
        await model.reload()
        await model.addWater(250)
        #expect(undetermined.foreignReads.isEmpty)
        #expect(undetermined.authorizationRequests == 0)
        #expect(undetermined.drinks.isEmpty)
    }

    @Test func connectHealth_requests_thenMirrorsPending() async {
        let undetermined = FakeHealthStore(access: .notDetermined)
        let model = make(undetermined)
        await model.reload()
        await model.addWater(250)
        await model.connectHealth()
        #expect(undetermined.authorizationRequests == 1)
        #expect(undetermined.drinks.count == 1)
        #expect(model.access == .authorized)
    }

    @Test func overlapWarning_namesHealthWorkout() async {
        let health = FakeHealthStore()
        health.foreign = [ForeignWorkout(id: UUID(), activityName: "Laufen", activity: .running,
                                         start: now.addingTimeInterval(-5 * 3600 - 35 * 60), end: now.addingTimeInterval(-5 * 3600),
                                         kilocalories: nil, sourceName: "Apple Watch")]
        let model = make(health)
        await model.reload()
        let warning = model.overlapWarning(start: now.addingTimeInterval(-5 * 3600 - 20 * 60), minutes: 30)
        #expect(warning == "Überschneidet sich mit „Laufen“ (07:05, Apple Watch). Das Training würde doppelt gezählt.")
        #expect(model.overlapWarning(start: now.addingTimeInterval(-3600), minutes: 30) == nil)
    }

    @Test func workoutDefaults_fromLatest() async {
        let model = make()
        #expect(model.workoutDefaults.activity == .strength)
        #expect(model.workoutDefaults.minutes == 45)
        await model.saveWorkout(WorkoutValue(id: UUID().uuidString, activity: .running, start: now, minutes: 30,
                                             kilocalories: nil, sourceName: nil, isOwn: true), isNew: true)
        #expect(model.workoutDefaults.activity == .running)
        #expect(model.workoutDefaults.minutes == 30)
    }

    @Test func repeatSuggestions_fromStore() async {
        store.addMeal(meal("Müsli", at: now.addingTimeInterval(-86_400)), estimatedAt: nil)
        store.addMeal(meal("Müsli", at: now.addingTimeInterval(-2 * 86_400)), estimatedAt: nil)
        store.addMeal(meal("Pizza", at: now.addingTimeInterval(-86_400)), estimatedAt: nil)
        let model = make()
        #expect(model.repeatSuggestions(filter: "").map(\.title) == ["Müsli", "Pizza"])
        #expect(model.repeatSuggestions(filter: "piz").map(\.title) == ["Pizza"])
    }
}
