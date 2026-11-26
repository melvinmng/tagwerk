import Foundation
import HealthBridge
import Observation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// Set from the `onChange` closure of `withObservationTracking`, which is `@Sendable`.
final class ChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var fired: Bool { lock.withLock { value } }
    func fire() { lock.withLock { value = true } }
}

@MainActor
struct CaptureModelTests {
    let container: ModelContainer
    let store: IntakeStore
    let settings: AppSettings
    let calendar = Calendar.tagwerk
    /// Wednesday, 18 Nov 2026, 12:40.
    var now: Date { clock.now }
    let clock = Clock()

    final class Clock { var now = Date() }

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        store = IntakeStore(context: container.mainContext)
        settings = try AppSettings.current(in: container.mainContext)
        clock.now = PlanDay(year: 2026, month: 11, day: 18).startDate(in: .tagwerk).addingTimeInterval(12 * 3600 + 40 * 60)
    }

    func make(_ health: FakeHealthStore = FakeHealthStore()) -> CaptureModel {
        let clock = self.clock
        let mirror = HealthMirror(store: store, health: health, now: { clock.now })
        return CaptureModel(store: store, mirror: mirror, health: health, settings: settings, calendar: calendar,
                            now: { clock.now }, waitsForHealth: true)
    }

    /// A model with stored goal plans and stored Health values, like the app builds it.
    func makeWithBudget(_ health: FakeHealthStore, plans: [GoalPlan] = []) -> CaptureModel {
        let clock = self.clock
        let context = container.mainContext
        let goals = GoalStore(context: context, settings: settings, calendar: calendar, now: { clock.now })
        for plan in plans { goals.adopt(plan) }
        let budgets = DayBudgets(intake: store, goals: goals, dayHealth: DayHealthStore(context: context, now: { clock.now }),
                                 health: health, settings: settings, calendar: calendar, now: { clock.now })
        let mirror = HealthMirror(store: store, health: health, now: { clock.now })
        return CaptureModel(store: store, mirror: mirror, health: health, settings: settings, budgets: budgets, calendar: calendar,
                            now: { clock.now }, waitsForHealth: true)
    }

    func plan(from day: PlanDay, kcal: Int) -> GoalPlan {
        GoalPlan(validFrom: day, kcal: kcal, waterMilliliters: 2000, stepsPerDay: 8000, workoutMinutesPerWeek: 150)
    }

    // MARK: Budget (nutrition plan, C1)

    @Test func budget_usesPlanOfShownDay() async {
        let today = PlanDay(year: 2026, month: 11, day: 18)
        let model = makeWithBudget(FakeHealthStore(), plans: [plan(from: today.adding(days: -30, calendar: calendar), kcal: 2300),
                                                              plan(from: today, kcal: 2000)])
        await model.reload()
        #expect(model.figures.budget.base == 2000)
        await model.goBack()
        #expect(model.figures.budget.base == 2300)
        #expect(model.todayFigures.budget.base == 2000, "today's figures do not follow the shown day")
    }

    @Test func budget_healthSumArrivesWithTheReload_andPagesShareIt() async {
        let health = FakeHealthStore()
        health.setGroupAccess(.asked, for: .activeEnergy)
        let today = PlanDay(year: 2026, month: 11, day: 18)
        let yesterday = today.adding(days: -1, calendar: calendar)
        health.activeEnergy = [DailyActiveEnergy(start: today.startDate(in: calendar), kilocalories: 520),
                               DailyActiveEnergy(start: yesterday.startDate(in: calendar), kilocalories: 400)]
        settings.activityCreditPercent = 100
        let model = makeWithBudget(health, plans: [plan(from: today.adding(days: -30, calendar: calendar), kcal: 2300)])
        #expect(model.figures.active.healthKcal == nil, "before the first read there is no Health value, and no 0")
        await model.reload()
        #expect(model.figures.budget.credited == 520 && model.figures.budget.budget == 2820)
        // The neighbour page reads the stored value of that day, so it shows what it will show once it arrives.
        let neighbour = model.page(for: yesterday)
        #expect(neighbour.figures.active.healthKcal == 400)
        await model.goBack()
        #expect(model.current.figures == neighbour.figures)
    }

    @Test func eaten_ownPlusForeign_whenSwitchedOn_otherwiseOwnOnly() async {
        let health = FakeHealthStore()
        health.setGroupAccess(.asked, for: .foreignNutrition)
        health.addForeignNutrition(day: clock.now.addingTimeInterval(-3600), kilocalories: 400, source: "Yazio")
        let model = makeWithBudget(health, plans: [plan(from: PlanDay(year: 2026, month: 11, day: 1), kcal: 2300)])
        await model.saveMeal(meal("Müsli", at: clock.now.addingTimeInterval(-7200)), estimatedAt: nil, isNew: true)
        settings.countsForeignNutrition = false
        await model.reload()
        #expect(model.figures.totals.kcal == 400, "own meal only (the 400 kcal meal helper)")
        settings.countsForeignNutrition = true
        await model.reload()
        #expect(model.figures.totals.kcal == 800)
        #expect(model.figures.totals.foreign?.sources == ["Yazio"])
    }

    @Test func activeEnergyNote_showsUntilTheGroupWasAsked_andAllowingAsksOnce() async {
        let health = FakeHealthStore()
        let model = makeWithBudget(health, plans: [plan(from: PlanDay(year: 2026, month: 11, day: 1), kcal: 2300)])
        await model.reload()
        #expect(model.activeEnergyNeedsAccess(for: model.figures.budget))
        await model.allowActiveEnergy()
        #expect(health.groupRequests(.activeEnergy) == 1)
        #expect(!model.activeEnergyNeedsAccess(for: model.figures.budget))
        await model.reload()
        #expect(health.groupRequests(.activeEnergy) == 1, "a reload never asks again")
    }

    @Test func activeEnergyNote_isHiddenWhenCreditingIsOff() async {
        settings.activityCreditPercent = 0
        let model = makeWithBudget(FakeHealthStore(), plans: [plan(from: PlanDay(year: 2026, month: 11, day: 1), kcal: 2300)])
        await model.reload()
        #expect(!model.activeEnergyNeedsAccess(for: model.figures.budget))
    }

    // MARK: Health consent (#314)

    @Test func connectHealth_asksForEverythingInOneSheet() async {
        let health = FakeHealthStore(access: .notDetermined, stepsAccess: .notAsked)
        let model = make(health)
        await model.reload()
        #expect(model.showsHealthCard)
        #expect(model.activeEnergyAccess == .notAsked)
        await model.connectHealth()
        #expect(health.authorizationRequests == 1)
        #expect(health.groupRequests(.activeEnergy) == 0 && health.groupRequests(.body) == 0, "no second sheet for a group")
        #expect(health.stepsAuthorizationRequests == 0)
        #expect(model.access == .authorized)
        #expect(model.stepsAccess == .asked)
        #expect(model.activeEnergyAccess == .asked)
        #expect(model.bodyAccess == .asked)
        #expect(model.weightWriteAccess == .allowed && model.heightWriteAccess == .allowed)
        #expect(!model.showsHealthCard)
    }

    @Test func healthCard_doesNotComeBack_afterTheAnswer() async {
        let health = FakeHealthStore(access: .notDetermined, stepsAccess: .notAsked)
        let model = make(health)
        await model.reload()
        await model.connectHealth()
        for _ in 0..<3 {
            await model.reload()
            #expect(!model.showsHealthCard)
        }
        #expect(health.authorizationRequests == 1 && health.groupRequests(.activeEnergy) == 0)
    }

    /// Starts the first Health request and returns once its sheet is open (held by the fake), so the requests that follow
    /// certainly arrive while a sheet is open. Without the hold the sheet closes after one scheduler yield, and a request that starts later
    /// would be a legitimate second sheet, which made these tests depend on the order and the timing of the child tasks.
    private func openFirstSheet(_ health: FakeHealthStore, _ request: @escaping @MainActor () async -> Void) async -> Task<Void, Never> {
        health.holdsSheets = true
        let first = Task { await request() }
        var spins = 0
        while health.sheetsOpened == 0, spins < 10_000 {
            await Task.yield()
            spins += 1
        }
        #expect(health.sheetsOpened == 1, "the first request opens its sheet")
        return first
    }

    @Test func concurrentConnects_showOneSheet() async {
        let health = FakeHealthStore(access: .notDetermined, stepsAccess: .notAsked)
        let model = make(health)
        await model.reload()
        let first = await openFirstSheet(health) { await model.connectHealth() }
        await model.connectHealth()
        #expect(health.authorizationRequests == 1, "the second request is dropped while the sheet is open")
        health.releaseHeldSheets()
        await first.value
        #expect(health.authorizationRequests == 1)
    }

    @Test func otherRequests_whileTheCardSheetIsOpen_areDropped() async {
        let health = FakeHealthStore(access: .notDetermined, stepsAccess: .notAsked)
        let model = make(health)
        await model.reload()
        let first = await openFirstSheet(health) { await model.connectHealth() }
        await model.allowActiveEnergy()
        await model.connectSteps()
        #expect(health.sheetsOpened == 1, "only one Health sheet opens at a time")
        health.releaseHeldSheets()
        await first.value
        #expect(health.authorizationRequests == 1 && health.groupRequests(.activeEnergy) == 0 && health.stepsAuthorizationRequests == 0)
        // The flag is released with the first sheet: a later request opens its own sheet again.
        await model.connectSteps()
        #expect(health.sheetsOpened == 2)
    }

    @Test func whileTheCardShows_stepsTileOffersNoSecondPrompt() async {
        let health = FakeHealthStore(access: .notDetermined, stepsAccess: .notAsked)
        let model = makeWithBudget(health, plans: [plan(from: PlanDay(year: 2026, month: 11, day: 1), kcal: 2300)])
        await model.reload()
        #expect(model.showsHealthCard)
        #expect(model.stepsTile != .allow)
        // After "Nicht jetzt" the card is gone and the tile may offer the one entry again.
        model.dismissHealthCard()
        #expect(model.stepsTile == .allow)
    }

    @Test func connectedUser_withoutSteps_keepsTheStepsTileOffer() async {
        let model = make(FakeHealthStore(access: .authorized, stepsAccess: .notAsked))
        await model.reload()
        #expect(!model.showsHealthCard)
        #expect(model.stepsTile == .allow)
    }

    @Test func failingRequest_isNotSwallowed_staysRetryable() async {
        let health = FakeHealthStore(access: .notDetermined, stepsAccess: .notAsked)
        health.failRequests = true
        let model = make(health)
        await model.reload()
        await model.connectHealth()
        #expect(health.authorizationRequests == 1)
        #expect(model.access == .notDetermined, "the state stays as it was")
        #expect(model.showsHealthCard)
        health.failRequests = false
        await model.connectHealth()
        #expect(health.authorizationRequests == 2, "the guard is released after a failure")
        #expect(model.access == .authorized)
    }

    @Test func summaryRows_followThePlanOfThePage() async {
        let today = PlanDay(year: 2026, month: 11, day: 18)
        let old = GoalPlan(validFrom: today.adding(days: -30, calendar: calendar), kcal: 2300, waterMilliliters: 2000, stepsPerDay: 8000,
                           workoutMinutesPerWeek: 150)
        var current = old
        current.validFrom = today
        current.workoutMinutesPerWeek = 0
        current.id = UUID()
        let model = makeWithBudget(FakeHealthStore(), plans: [old, current])
        await model.reload()
        #expect(model.summaryRows(steps: nil, plan: model.figures.plan).flatMap { $0 }.contains(.training) == false)
        let yesterday = model.page(for: today.adding(days: -1, calendar: calendar))
        #expect(model.summaryRows(steps: nil, plan: yesterday.figures.plan).flatMap { $0 }.contains(.training))
    }

    // MARK: Card "Nährwerte" and the row of other apps (D3)

    @Test func nutrientRows_followThePlanAndTheSwitches() async {
        let today = PlanDay(year: 2026, month: 11, day: 18)
        let plan = GoalPlan(validFrom: today.adding(days: -30, calendar: calendar), kcal: 2300, proteinGrams: 140, carbsGrams: 250,
                            fatGrams: 78, fiberGrams: 30, sugarLimitGrams: 50, waterMilliliters: 2000, stepsPerDay: 8000,
                            workoutMinutesPerWeek: 150)
        let model = makeWithBudget(FakeHealthStore(), plans: [plan])
        await model.reload()
        #expect(model.nutrientRows(for: model.figures).map(\.kind) == [.protein, .carbohydrates, .fat, .further(.fiber), .further(.sugar)])
        settings.saltEnabled = true
        #expect(model.nutrientRows(for: model.figures).last?.kind == .further(.salt))
        settings.saltEnabled = false
    }

    @Test func foreignRow_hiddenWithoutForeignValues() async {
        let health = FakeHealthStore()
        health.setGroupAccess(.asked, for: .foreignNutrition)
        let model = makeWithBudget(health, plans: [plan(from: PlanDay(year: 2026, month: 11, day: 1), kcal: 2300)])
        await model.setCountsForeignNutrition(true)
        #expect(model.figures.totals.foreign == nil, "switched on but nothing there: no row, no error")
    }

    @Test func foreignRow_namesSources() async {
        let health = FakeHealthStore()
        health.addForeignNutrition(day: clock.now.addingTimeInterval(-3600), kilocalories: 400, source: "Yazio")
        health.addForeignNutrition(day: clock.now.addingTimeInterval(-7200), kilocalories: 200, source: "Lose It")
        let model = makeWithBudget(health, plans: [plan(from: PlanDay(year: 2026, month: 11, day: 1), kcal: 2300)])
        await model.setCountsForeignNutrition(true)
        let foreign = model.figures.totals.foreign
        #expect(foreign?.kcal == 600)
        #expect(IntakeFormat.foreignSources(foreign?.sources ?? []) == "Lose It, Yazio")
    }

    @Test func reload_keepsBudgetWhileHealthAnswers() async {
        let health = FakeHealthStore()
        health.setGroupAccess(.asked, for: .activeEnergy)
        let today = PlanDay(year: 2026, month: 11, day: 18)
        health.activeEnergy = [DailyActiveEnergy(start: today.startDate(in: calendar), kilocalories: 500)]
        let model = makeWithBudget(health, plans: [plan(from: today.adding(days: -30, calendar: calendar), kcal: 2300)])
        await model.reload()
        let before = model.figures
        health.failActiveEnergyReads = true
        await model.reload()
        #expect(model.figures == before, "a failed read (locked device) leaves the budget as it was")
    }

    @Test func pastDay_usesStoredDayHealthWhenHealthSilent() async {
        let health = FakeHealthStore()
        health.setGroupAccess(.asked, for: .activeEnergy)
        let today = PlanDay(year: 2026, month: 11, day: 18)
        let yesterday = today.adding(days: -1, calendar: calendar)
        health.activeEnergy = [DailyActiveEnergy(start: yesterday.startDate(in: calendar), kilocalories: 700)]
        let model = makeWithBudget(health, plans: [plan(from: today.adding(days: -30, calendar: calendar), kcal: 2300)])
        await model.reload()
        health.activeEnergy = []
        await model.goBack()
        #expect(model.figures.active.healthKcal == 700)
    }

    @Test func drinkPresets_ofTheSettings_driveTheQuickButtons() async {
        let model = make()
        await model.reload()
        #expect(model.settings.drinkPresets == [250, 330, 500])
        settings.drinkPresets = [800, 330, 500]
        // The quick buttons read these values and add exactly the tapped portion.
        #expect(model.settings.drinkPresets == [800, 330, 500])
        await model.addWater(model.settings.drinkPresets[0], offersUndo: false)
        #expect(model.drinks.map(\.milliliters) == [800])
    }

    @Test func newDay_whileShowingToday_followsToday() async {
        let model = make()
        await model.reload()
        clock.now = clock.now.addingTimeInterval(86_400)
        await model.reload()
        #expect(model.day == PlanDay(date: clock.now, calendar: calendar))
        await model.addWater(250)
        #expect(model.drinks.first?.date == clock.now)
    }

    @Test func newDay_whileShowingPastDay_staysThere() async {
        let model = make()
        await model.reload()
        await model.goBack(days: 2)
        let shown = model.day
        clock.now = clock.now.addingTimeInterval(86_400)
        await model.reload()
        #expect(model.day == shown)
    }

    @Test func healthCard_hiddenBeforeFirstQuery() {
        let model = make(FakeHealthStore(access: .notDetermined))
        #expect(!model.showsHealthCard)
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

    @Test func weekMinutes_includeOwnAndForeignWorkouts() async {
        let health = FakeHealthStore()
        health.foreign = [ForeignWorkout(id: UUID(), activityName: "Rudern", activity: nil, start: now.addingTimeInterval(-5 * 3600),
                                         end: now.addingTimeInterval(-4 * 3600), kilocalories: 300, sourceName: "Apple Watch")]
        let model = make(health)
        await model.reload()
        await model.saveWorkout(WorkoutValue(id: UUID().uuidString, activity: .strength, start: now.addingTimeInterval(-3600),
                                             minutes: 45, kilocalories: nil, sourceName: nil, isOwn: true), isNew: true)
        #expect(model.workouts.map(\.displayName) == ["Rudern", "Krafttraining"])
        #expect(model.workouts.first?.isOwn == false)
        #expect(model.weekMinutes == 105)
    }

    @Test func dayMinutes_followDisplayedDay() async {
        let health = FakeHealthStore()
        health.foreign = [ForeignWorkout(id: UUID(), activityName: "Laufen", activity: .running,
                                         start: now.addingTimeInterval(-5 * 3600 - 35 * 60), end: now.addingTimeInterval(-5 * 3600 - 3 * 60),
                                         kilocalories: 310, sourceName: "Apple Watch")]
        let monday = now.addingTimeInterval(-2 * 86_400)
        store.addWorkout(WorkoutValue(id: UUID().uuidString, activity: .strength, start: monday, minutes: 50, kilocalories: nil,
                                      sourceName: nil, isOwn: true))
        store.addWorkout(WorkoutValue(id: UUID().uuidString, activity: .strength, start: now.addingTimeInterval(-25 * 60),
                                      minutes: 45, kilocalories: nil, sourceName: nil, isOwn: true))
        // A short session counts too, so the list and its sum agree.
        store.addWorkout(WorkoutValue(id: UUID().uuidString, activity: .yoga, start: now.addingTimeInterval(-2 * 3600),
                                      minutes: 5, kilocalories: nil, sourceName: nil, isOwn: true))
        let model = make(health)
        await model.reload()
        #expect(model.dayMinutes == 82)
        #expect(model.weekMinutes == 132)
        await model.goBack(days: 2)
        #expect(model.dayMinutes == 50)
        #expect(model.weekMinutes == 132)
    }

    // MARK: Steps

    private func steps(_ count: Int, daysAgo: Int = 0) -> DailySteps {
        DailySteps(start: PlanDay(date: now, calendar: calendar).adding(days: -daysAgo, calendar: calendar).startDate(in: calendar),
                   count: count)
    }

    @Test func steps_loadedForDisplayedDay_whenStepsAccessAsked() async {
        let health = FakeHealthStore()
        health.steps = [steps(6412), steps(8240, daysAgo: 1)]
        let model = make(health)
        await model.reload()
        #expect(model.stepsAccess == .asked)
        #expect(model.steps == 6412)
        await model.goBack()
        #expect(model.steps == 8240)
        await model.goBack()
        // No statistics for that day: no value, never 0.
        #expect(model.steps == nil)
    }

    @Test func steps_notRead_whenStepsNotAsked() async {
        let health = FakeHealthStore(stepsAccess: .notAsked)
        health.steps = [steps(6412)]
        let model = make(health)
        await model.reload()
        #expect(health.stepsReads.isEmpty)
        #expect(health.stepsAuthorizationRequests == 0)
        #expect(model.steps == nil)
        #expect(model.stepsTile == .allow)
    }

    @Test func steps_staleResultOfEarlierDay_isDiscarded() async {
        let health = FakeHealthStore()
        health.steps = [steps(6412), steps(8240, daysAgo: 1)]
        let model = make(health)
        await model.reload()
        let yesterday = model.day.adding(days: -1, calendar: calendar)
        let today = model.day
        model.show(yesterday)
        // Yesterday's steps were read after the reload, so they are there at once.
        #expect(model.steps == 8240)
        // While yesterday's query runs, the user swipes back to today.
        let once = Once()
        health.onStepsRead = { _ in
            if once.fire() { model.show(today) }
        }
        await model.reload(refreshingLocalFirst: false)
        #expect(model.day == today)
        #expect(model.steps == 6412)
    }

    final class Once: @unchecked Sendable {
        private var fired = false
        func fire() -> Bool {
            defer { fired = true }
            return !fired
        }
    }

    @Test func connectSteps_requestsOnlySteps_andReloads() async {
        let health = FakeHealthStore(stepsAccess: .notAsked)
        health.steps = [steps(6412)]
        let model = make(health)
        await model.reload()
        await model.allowSteps()
        #expect(health.stepsAuthorizationRequests == 1)
        #expect(health.authorizationRequests == 0)
        #expect(model.stepsAccess == .asked)
        #expect(model.steps == 6412)
        #expect(model.stepsTile == .value(6412))
    }

    /// A new user taps "In Health erlauben" before connecting Health: one sheet for everything, not a steps-only one.
    @Test func allowSteps_whileHealthNotAsked_connectsHealth() async {
        let health = FakeHealthStore(access: .notDetermined, stepsAccess: .notAsked)
        health.steps = [steps(6412)]
        let model = make(health)
        await model.reload()
        await model.allowSteps()
        #expect(health.authorizationRequests == 1)
        #expect(health.stepsAuthorizationRequests == 0)
        #expect(model.access == .authorized)
        #expect(model.steps == 6412)
    }

    @Test func coreAccess_unchanged_whenStepsNotAsked() async {
        let health = FakeHealthStore(access: .authorized, stepsAccess: .notAsked)
        let model = make(health)
        await model.reload()
        await model.addWater(250)
        #expect(model.access == .authorized)
        #expect(!model.showsHealthCard)
        #expect(health.foreignReads.count >= 1)
        #expect(health.drinks.count == 1)
    }

    @Test func stepsTile_hiddenWithoutHealth_dashBeforeFirstQuery() async {
        let health = FakeHealthStore(access: .unavailable, stepsAccess: .unavailable)
        let model = make(health)
        #expect(model.stepsTile == .value(nil))
        await model.reload()
        #expect(model.stepsTile == .hidden)
        #expect(health.stepsReads.isEmpty)
    }

    @Test func todaySteps_keptWhileShowingPastDay_forHeaderAndWidget() async {
        let health = FakeHealthStore()
        health.steps = [steps(6412), steps(8240, daysAgo: 1)]
        let model = make(health)
        await model.reload()
        await model.addWater(500)
        await model.goBack()
        #expect(model.steps == 8240)
        #expect(model.todaySteps == 6412)
        #expect(model.planHeaderLine == "noch 2.300 kcal · 0,5 / 2,0 l · 6.412 Schritte")
    }

    @Test func todaySteps_dropAfterMidnight() async {
        let health = FakeHealthStore()
        health.steps = [steps(6412)]
        let model = make(health)
        await model.reload()
        #expect(model.todaySteps == 6412)
        clock.now = clock.now.addingTimeInterval(86_400)
        // Before the next reload, yesterday's count is never shown as today's.
        #expect(model.todaySteps == nil)
    }

    /// A failed read (Health is locked once the phone locks, e.g. during the reload when the app goes to the background)
    /// keeps today's known count for the widget; "no data" still clears it.
    @Test func todaySteps_keptWhenReadFails_clearedWithoutData() async {
        let health = FakeHealthStore()
        health.steps = [steps(6412)]
        let model = make(health)
        await model.reload()
        health.failStepReads = true
        await model.reload()
        #expect(model.todaySteps == 6412)
        #expect(model.steps == 6412)
        health.failStepReads = false
        health.steps = []
        await model.reload()
        #expect(model.todaySteps == nil)
        #expect(model.steps == nil)
    }

    @Test func todaySteps_onlyWhenStepsAsked() async {
        let health = FakeHealthStore(stepsAccess: .notAsked)
        health.steps = [steps(6412)]
        let model = make(health)
        await model.reload()
        #expect(model.todaySteps == nil)
    }

    // MARK: Summary layout

    @Test func summaryRows_layout() {
        // Protein is on the card "Nährwerte" now: water, steps and training make the tiles, two to a row at most.
        #expect(CaptureModel.summaryRows(steps: true, training: true) == [[.water, .steps], [.training]])
        #expect(CaptureModel.summaryRows(steps: false, training: true) == [[.water, .training]])
        #expect(CaptureModel.summaryRows(steps: true, training: false) == [[.water, .steps]])
        #expect(CaptureModel.summaryRows(steps: false, training: false) == [[.water]])
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

    /// Swipes and arrows change the day synchronously, so the change can be animated; entries follow at once.
    @Test func show_isSynchronous_andClamped() async {
        let model = make()
        await model.reload()
        await model.addWater(250)
        model.show(PlanDay(date: now, calendar: calendar).adding(days: -1, calendar: calendar))
        #expect(model.drinks.isEmpty)
        #expect(model.show(PlanDay(year: 2026, month: 12, day: 24)))
        #expect(model.day == PlanDay(date: now, calendar: calendar))
        // Already on today: nothing changes, so the view can signal the limit.
        #expect(!model.show(PlanDay(year: 2026, month: 12, day: 24)))
        #expect(model.drinks.count == 1)
    }

    @Test func goTo_pastDay_showsIt() async {
        let model = make()
        await model.reload()
        await model.go(to: PlanDay(year: 2026, month: 10, day: 3))
        #expect(model.day == PlanDay(year: 2026, month: 10, day: 3))
        #expect(model.canGoForward)
    }

    @Test func goTo_futureDay_staysToday() async {
        let model = make()
        await model.reload()
        await model.goBack(days: 3)
        await model.go(to: PlanDay(year: 2026, month: 12, day: 24))
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

    // MARK: Phase 4: today's intake for the plan header and the widget

    @Test func todayIntake_countsTodayOnly_notDisplayedDay() async {
        let model = make()
        await model.reload()
        await model.addWater(500)
        await model.goBack()
        await model.reload()
        await model.addWater(250)  // back-filled on yesterday
        #expect(model.todayIntake.waterMilliliters == 500)
        #expect(model.todayHasEntries)
    }

    @Test func todayIntake_updatesAfterDeleteAndUndo() async {
        let model = make()
        await model.reload()
        await model.addWater(330)
        let id = model.drinks[0].id
        await model.delete(id)
        #expect(model.todayIntake.waterMilliliters == 0)
        #expect(model.todayHasEntries == false)
        await model.undoLast()
        #expect(model.todayIntake.waterMilliliters == 330)
    }

    @Test func planHeaderLine_hiddenWhenSettingOff() async {
        let model = make()
        await model.reload()
        await model.addWater(500)
        #expect(model.planHeaderLine == "noch 2.300 kcal · 0,5 / 2,0 l")
        settings.showsIntakeInPlan = false
        #expect(model.planHeaderLine == nil)
    }

    @Test func planHeaderLine_hiddenWhenNoEntriesToday() async {
        let model = make()
        await model.reload()
        #expect(model.planHeaderLine == nil)
    }

    // MARK: Neighbour page

    @Test func pageForNeighbourDay_readsStoredEntriesAndLeavesTheShownDayAlone() async {
        let health = FakeHealthStore(stepsAccess: .asked)
        health.steps = [steps(6412)]
        let model = make(health)
        await model.reload()
        let yesterday = model.day.adding(days: -1, calendar: calendar)
        let noon = yesterday.startDate(in: calendar).addingTimeInterval(12 * 3600)
        store.addDrink(DrinkValue(id: UUID(), date: noon, milliliters: 400))
        store.addDrink(DrinkValue(id: UUID(), date: noon.addingTimeInterval(3600), milliliters: 250))
        let page = model.page(for: yesterday)
        #expect(page.day == yesterday)
        #expect(page.drinks.count == 2)
        #expect(page.intake.waterMilliliters == 650)
        // The shown day is untouched, and a day without entries is empty.
        #expect(model.intake == .empty)
        let before = model.page(for: yesterday.adding(days: -1, calendar: calendar))
        #expect(before.intake == .empty)
        #expect(!before.hasEntries)
    }

    @Test func pageForShownDay_isTheShownPage() async {
        let model = make(FakeHealthStore())
        await model.reload()
        #expect(model.page(for: model.day) == model.current)
    }

    @Test func pageForNeighbourDay_carriesTheStepsAndHealthWorkoutsReadAfterTheReload() async {
        let health = FakeHealthStore()
        health.steps = [steps(6412), steps(8240, daysAgo: 1)]
        let yesterdayStart = now.addingTimeInterval(-86_400)
        health.foreign = [ForeignWorkout(id: UUID(), activityName: "Rudern", activity: nil, start: yesterdayStart,
                                         end: yesterdayStart.addingTimeInterval(3600), kilocalories: 300, sourceName: "Apple Watch")]
        let model = make(health)
        await model.reload()
        let yesterday = model.day.adding(days: -1, calendar: calendar)
        let page = model.page(for: yesterday)
        #expect(page.steps == 8240)
        #expect(page.workouts.map(\.displayName) == ["Rudern"])
        #expect(page.dayMinutes == 60)
        // A day far outside what was read has no numbers rather than wrong ones.
        #expect(model.page(for: yesterday.adding(days: -20, calendar: calendar)).steps == nil)
    }

    // #310: the preview calls `page(for:)` on every body evaluation, so the page is built once per state of the model.

    @Test func pageForNeighbourDay_isBuiltOnceUntilTheModelChanges() async {
        let model = make(FakeHealthStore())
        await model.reload()
        let yesterday = model.day.adding(days: -1, calendar: calendar)
        let noon = yesterday.startDate(in: calendar).addingTimeInterval(12 * 3600)
        let first = model.page(for: yesterday)
        // A direct store edit is invisible to the cached page; every change through the model passes `refreshLocal` and rebuilds it.
        store.addDrink(DrinkValue(id: UUID(), date: noon, milliliters: 300))
        #expect(model.page(for: yesterday) == first, "the second call returns the cached page")
        await model.reload()
        #expect(model.page(for: yesterday).intake.waterMilliliters == 300, "a reload rebuilds it")
    }

    @Test func pageForNeighbourDay_followsAnEntryAddedThroughTheModel() async {
        let model = make(FakeHealthStore())
        await model.reload()
        await model.goBack()
        let beforeYesterday = model.day.adding(days: -1, calendar: calendar)
        #expect(model.page(for: beforeYesterday).intake == .empty)
        let today = model.day.adding(days: 1, calendar: calendar)
        let cachedToday = model.page(for: today)
        await model.addWater(250, at: model.day.startDate(in: calendar).addingTimeInterval(9 * 3600))
        #expect(model.page(for: today) == cachedToday, "an entry of the shown day leaves the neighbour as it was")
        #expect(model.page(for: model.day) == model.current)
        #expect(model.current.intake.waterMilliliters == 250)
    }

    /// The neighbour prefetch runs after `reload()` has returned; a page built in between must not stay cached without its numbers.
    @Test func pageForNeighbourDay_isRebuiltWhenThePrefetchArrives() async {
        let health = FakeHealthStore()
        health.steps = [steps(6412), steps(8240, daysAgo: 1)]
        let clock = self.clock
        let mirror = HealthMirror(store: store, health: health, now: { clock.now })
        let model = CaptureModel(store: store, mirror: mirror, health: health, settings: settings, calendar: calendar,
                                 now: { clock.now }, waitsForHealth: false)
        await model.reload()
        let yesterday = model.day.adding(days: -1, calendar: calendar)
        let early = model.page(for: yesterday)
        await model.waitForPrefetch()
        #expect(early.steps == nil, "the prefetch had not arrived when the first page was built")
        #expect(model.page(for: yesterday).steps == 8240)
    }

    /// The preview is rendered again when the prefetch drops the cached pages, although no other observed value changes.
    @Test func pageForNeighbourDay_announcesItsInvalidationToTheView() async {
        let health = FakeHealthStore()
        health.steps = [steps(6412), steps(8240, daysAgo: 1)]
        let clock = self.clock
        let mirror = HealthMirror(store: store, health: health, now: { clock.now })
        let model = CaptureModel(store: store, mirror: mirror, health: health, settings: settings, calendar: calendar,
                                 now: { clock.now }, waitsForHealth: false)
        await model.reload()
        let yesterday = model.day.adding(days: -1, calendar: calendar)
        let flag = ChangeFlag()
        withObservationTracking { _ = model.page(for: yesterday) } onChange: { flag.fire() }
        await model.waitForPrefetch()
        #expect(flag.fired, "a view that shows the preview must be rendered again when the neighbour numbers arrive")
    }

    @Test func reload_readsTheIndependentStatusesAndStillFillsEverything() async {
        let health = FakeHealthStore(access: .authorized, stepsAccess: .asked)
        health.steps = [steps(6412)]
        health.setGroupAccess(.asked, for: .activeEnergy)
        health.setWriteAccess(.denied, for: .weight)
        let model = make(health)
        await model.reload()
        #expect(model.access == .authorized && model.stepsAccess == .asked)
        #expect(model.activeEnergyAccess == .asked && model.bodyAccess == .notAsked)
        #expect(model.weightWriteAccess == .denied && model.heightWriteAccess == .notAsked)
        #expect(model.healthConnected)
        #expect(model.steps == 6412 && model.todaySteps == 6412)
    }

    @Test func show_withReadNeighbour_hasItsHealthNumbersAtOnce() async {
        let health = FakeHealthStore()
        health.steps = [steps(6412), steps(8240, daysAgo: 1)]
        let yesterdayStart = now.addingTimeInterval(-86_400)
        health.foreign = [ForeignWorkout(id: UUID(), activityName: "Rudern", activity: nil, start: yesterdayStart,
                                         end: yesterdayStart.addingTimeInterval(3600), kilocalories: 300, sourceName: "Apple Watch")]
        let model = make(health)
        await model.reload()
        let stepReads = health.stepsReads.count
        let page = model.page(for: model.day.adding(days: -1, calendar: calendar))
        model.show(model.day.adding(days: -1, calendar: calendar))
        // No Health query and no wait: the shown page equals the preview that was dragged in.
        #expect(health.stepsReads.count == stepReads)
        #expect(model.current == page)
        #expect(model.steps == 8240)
    }
}
