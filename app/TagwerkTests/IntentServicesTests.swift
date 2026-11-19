import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct IntentServicesTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "intents-\(UUID().uuidString)")
    let health = FakeHealthStore()

    private func make() throws -> (IntentServices, AppEnvironment) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let environment = try AppEnvironment(modelContainer: container, notificationCenter: FakeNotificationCenter(),
                                             health: health, snapshotWriter: WidgetSnapshotWriter(directory: directory, reload: {}))
        environment.settings.setupCompleted = true
        return (IntentServices(environment: environment), environment)
    }

    @Test func focusFilter_remembersStartAndEnd_forTheNotificationPlan() async throws {
        let (services, environment) = try make()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        await services.setFocusQuiet(active: true, now: start)
        #expect(environment.settings.focusQuietState == FocusQuiet.State(since: start))
        // A second run with the same value keeps the first start.
        await services.setFocusQuiet(active: true, now: start.addingTimeInterval(600))
        #expect(environment.settings.focusQuietSince == start)
        await services.setFocusQuiet(active: false, now: start.addingTimeInterval(3600))
        #expect(environment.settings.focusQuietSince == nil)
        #expect(environment.settings.focusQuietCatchUpFrom == start)
    }

    @Test func logWater_savesDrinkNow_writesSnapshot_replyWithoutTotal() async throws {
        let (services, environment) = try make()
        let today = PlanDay(date: .now, calendar: environment.planning.calendar)
        environment.snapshotWriter.write(WidgetSnapshot(createdAt: .now, days: [SnapshotDay(day: today, entries: [], deadlineCount: 0,
                                                                                            intake: nil)]))
        let reply = await services.logWater(milliliters: 330)
        #expect(String(localized: reply) == "330 ml Wasser erfasst.")
        #expect(environment.capture.todayIntake.waterMilliliters == 330)
        #expect(environment.snapshotWriter.current()?.days.first?.intake?.waterMilliliters == 330)
        _ = await services.logWater(milliliters: 250)
        #expect(environment.capture.todayIntake.waterMilliliters == 580)
        #expect(environment.capture.undo == nil)  // no "Widerrufen" bar from Siri
    }

    @Test func logWater_withoutFileAndSources_writesNoPlan() async throws {
        let (services, environment) = try make()
        _ = await services.logWater(milliliters: 250)
        #expect(environment.snapshotWriter.current() == nil)
    }

    @Test func logWater_clampsAmount_defaultsTo250() async throws {
        let (services, environment) = try make()
        #expect(String(localized: await services.logWater(milliliters: nil)) == "250 ml Wasser erfasst.")
        #expect(String(localized: await services.logWater(milliliters: 9000)) == "2000 ml Wasser erfasst.")
        #expect(String(localized: await services.logWater(milliliters: 10)) == "50 ml Wasser erfasst.")
        #expect(environment.capture.todayIntake.waterMilliliters == 2300)
    }

    @Test func logWater_capturedOnPastDay_savesNow() async throws {
        let (services, environment) = try make()
        await environment.capture.reload()
        await environment.capture.goBack(days: 2)
        await environment.capture.reload()
        _ = await services.logWater(milliliters: 500)
        #expect(environment.capture.todayIntake.waterMilliliters == 500)
    }

    @Test func todayOverview_fromSnapshot_noNutrition() async throws {
        let (services, environment) = try make()
        let calendar = environment.planning.calendar
        let now = Date.now
        let entry = SnapshotEntry(id: "e", title: "Vorlesung", start: now.addingTimeInterval(600), end: now.addingTimeInterval(4200),
                                  kind: .event, colorHex: nil, isAllDay: false)
        let intake = SnapshotIntake(kcal: 1200, hasEstimate: true, goalKcal: 2300, waterMilliliters: 900, goalWaterMilliliters: 2000)
        environment.snapshotWriter.write(WidgetSnapshot(createdAt: now, days: [
            SnapshotDay(day: PlanDay(date: now, calendar: calendar), entries: [entry], deadlineCount: 0, intake: intake),
        ]))
        let overview = services.todayOverview(now: now)
        #expect(overview.text.hasPrefix("Heute: 1 Termin."))
        #expect(overview.text.contains("Vorlesung"))
        #expect(!overview.text.contains("kcal"))
        #expect(!overview.text.contains(" l"))
        #expect(overview.entries.map(\.title) == ["Vorlesung"])
    }

    @Test func todayOverview_staleSnapshot_asksToOpenApp() throws {
        let (services, _) = try make()
        let overview = services.todayOverview(now: .now)
        #expect(overview.text == "Öffne Tagwerk, um den Plan zu laden.")
        #expect(overview.entries.isEmpty)
    }

    @Test func openMeal_setsRouteWithText() throws {
        let (services, environment) = try make()
        services.openMeal(text: "Zwei Brötchen mit Käse")
        _ = environment.router.takeRequest(setupCompleted: true)
        #expect(environment.router.takeCapturePrefill() == .meal(text: "Zwei Brötchen mit Käse"))
    }

    @Test func openWorkout_setsRoute() throws {
        let (services, environment) = try make()
        services.openWorkout(activity: .running, minutes: 30)
        #expect(environment.router.takeRequest(setupCompleted: true)?.route == .captureWorkout)
        #expect(environment.router.takeCapturePrefill() == .workout(activity: .running, minutes: 30))
    }

    // MARK: Habits (phase 7)

    private func addHabit(_ environment: AppEnvironment, name: String = "Lesen 20 min", source: HabitSource = .manual,
                          pausedSince: PlanDay? = nil) -> Habit {
        let habit = Habit(name: name, symbol: "book", order: environment.habits.habits.count, source: source,
                          start: environment.habits.today, pausedSince: pausedSince)
        environment.habits.save(habit)
        return habit
    }

    private func seedSnapshot(_ environment: AppEnvironment) {
        let today = environment.habits.today
        environment.snapshotWriter.write(WidgetSnapshot(createdAt: .now, days: [SnapshotDay(day: today, entries: [], deadlineCount: 0,
                                                                                            intake: nil)]))
    }

    @Test func checkHabit_addsManualCheckForToday_writesSnapshot() async throws {
        let (services, environment) = try make()
        seedSnapshot(environment)
        let habit = addHabit(environment)
        let reply = await services.checkHabit(id: habit.id)
        #expect(String(localized: reply) == "Lesen 20 min ist für heute abgehakt.")
        #expect(environment.snapshotWriter.current()?.days.first?.habits == SnapshotHabits(done: 1, total: 1))
    }

    @Test func checkHabit_twice_saysAlreadyChecked() async throws {
        let (services, environment) = try make()
        let habit = addHabit(environment)
        _ = await services.checkHabit(id: habit.id)
        #expect(String(localized: await services.checkHabit(id: habit.id)) == "Lesen 20 min war heute schon abgehakt.")
    }

    @Test func checkHabit_onAutomaticHabit_stillStoresTheManualCheck() async throws {
        let (services, environment) = try make()
        let habit = addHabit(environment, name: "Wasser", source: .water)
        let reply = await services.checkHabit(id: habit.id)
        #expect(String(localized: reply) == "Wasser ist für heute abgehakt.")
        #expect(environment.habits.facts.manualChecks[habit.id] == [environment.habits.today])
    }

    @Test func checkHabit_unknownOrPausedHabit_changesNothing() async throws {
        let (services, environment) = try make()
        let paused = addHabit(environment, pausedSince: environment.habits.today)
        #expect(String(localized: await services.checkHabit(id: paused.id)) == "Diese Gewohnheit gibt es nicht mehr.")
        #expect(String(localized: await services.checkHabit(id: UUID())) == "Diese Gewohnheit gibt es nicht mehr.")
        #expect(environment.habits.facts.manualChecks.isEmpty)
    }

    @Test func activeHabits_listsOnlyActiveOnes() throws {
        let (services, environment) = try make()
        let active = addHabit(environment, name: "Lesen")
        _ = addHabit(environment, name: "Pausiert", pausedSince: environment.habits.today)
        #expect(services.activeHabits().map(\.id) == [active.id])
    }

    @Test func checkHabit_keepsTheDayShownInCapture() async throws {
        let (services, environment) = try make()
        let habit = addHabit(environment)
        let past = environment.habits.today.adding(days: -1, calendar: environment.habits.calendar)
        environment.habits.show(past)
        _ = await services.checkHabit(id: habit.id)
        // Siri checks today; the section keeps showing the day the tab shows.
        #expect(environment.habits.day == past)
        #expect(environment.habits.facts.manualChecks[habit.id] == [environment.habits.today])
    }

    @Test func backgroundSnapshot_withoutHealthFacts_neverLowersTheCounter() async throws {
        let (services, environment) = try make()
        let today = environment.habits.today
        _ = addHabit(environment, name: "Schritte", source: .steps)
        let manual = addHabit(environment, name: "Lesen")
        // The file was written while Health values were known: both habits counted.
        environment.snapshotWriter.write(WidgetSnapshot(createdAt: .now, days: [
            SnapshotDay(day: today, entries: [], deadlineCount: 0, intake: nil, habits: SnapshotHabits(done: 2, total: 2))]))
        // A background run while Health cannot be read: the step habit cannot be calculated, the counter must not fall.
        health.failStepReads = true
        _ = await services.checkHabit(id: manual.id)
        #expect(environment.snapshotWriter.current()?.days.first?.habits == SnapshotHabits(done: 2, total: 2))
    }
}
