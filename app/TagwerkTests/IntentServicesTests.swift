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
                                             health: health, snapshotWriter: WidgetSnapshotWriter(directory: directory, reload: {}),
                                             focusNotificationCenter: FakeFocusNotificationCenter())
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

    @Test func logWater_marksTheTipAsDone() async throws {
        let (services, environment) = try make()
        #expect(!environment.settings.siriTipWaterDone)
        _ = await services.logWater(milliliters: 250)
        #expect(environment.settings.siriTipWaterDone)
        #expect(!environment.settings.siriTipShoppingDone, "running one shortcut must not close the other tip")
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

    // MARK: Focus and dictation (#167)

    @Test func startFocus_freeSession() async throws {
        let (services, environment) = try make()
        let reply = await services.setFocus(true)
        #expect(String(localized: reply) == "Fokus gestartet.")
        #expect(environment.focus.isRunning)
        #expect(environment.focus.session?.title == "")
        #expect(String(localized: await services.setFocus(true)) == "Der Fokus läuft schon.")
        _ = await services.setFocus(false)
    }

    @Test func stopFocus_endsTheSession() async throws {
        let (services, environment) = try make()
        _ = await services.setFocus(true)
        #expect(String(localized: await services.setFocus(false)) == "Fokus beendet.")
        #expect(environment.focus.isRunning == false)
    }

    @Test func stopFocus_whenIdle_repliesNothingRunning() async throws {
        let (services, _) = try make()
        #expect(String(localized: await services.setFocus(false)) == "Es läuft gerade kein Fokus.")
    }

    @Test func openDictation_onlyNavigates() throws {
        let (services, environment) = try make()
        services.openDictation()
        #expect(environment.router.takeRequest(setupCompleted: true)?.route == .notesDictate)
        #expect(environment.router.takeDictationRequest())
    }

    @Test func openDictatedNote_withBrainDump_showsItsList() throws {
        let (_, environment) = try make()
        let folder = try #require(environment.notes.folder(role: .brainDump))
        environment.router.open(.notesDictate)
        _ = environment.router.takeRequest(setupCompleted: true)
        environment.openDictatedNote()
        #expect(environment.tasksPath == [.notes, .notesFolder(.folder(folder.id))])
        #expect(environment.router.dictationRequested)
    }

    @Test func openNewBrainDumpNote_pushesNotesAndNote() throws {
        let (_, environment) = try make()
        let folder = try #require(environment.notes.folder(role: .brainDump))
        environment.tasksPath = [.shopping]
        environment.openNewBrainDumpNote()
        let note = try #require(environment.notes.notes(.folder(folder.id)).first)
        #expect(environment.tasksPath == [.notes, .notesFolder(.folder(folder.id)), .note(note.id)])
        #expect(environment.requestedTab == 1)
        #expect(note.text.isEmpty && note.kind == .free)
        // Nothing starts a recording.
        #expect(!environment.router.dictationRequested)
    }

    @Test func openNewBrainDumpNote_withoutFolder_createsItFirst() throws {
        let (_, environment) = try make()
        for folder in environment.notes.folders() where folder.role == .brainDump {
            environment.notes.context.delete(folder)
        }
        #expect(environment.notes.folder(role: .brainDump) == nil)
        environment.openNewBrainDumpNote()
        let folder = try #require(environment.notes.folder(role: .brainDump))
        #expect(environment.tasksPath.count == 3 && environment.tasksPath.first == .notes)
        #expect(environment.notes.notes(.folder(folder.id)).count == 1)
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

    // MARK: Habit list for the control (#167)

    @Test func habitList_writtenOnChange_withoutStats() throws {
        let suite = "test.habits.\(UUID().uuidString)"
        let state = ControlState(defaults: UserDefaults(suiteName: suite)!)
        let container = try ModelContainerFactory.make(inMemory: true)
        let environment = try AppEnvironment(modelContainer: container, notificationCenter: FakeNotificationCenter(), health: health,
                                             snapshotWriter: WidgetSnapshotWriter(directory: directory, reload: {}), controlState: state)
        environment.startSnapshotUpdates()
        #expect(state.habits().isEmpty)
        let habit = addHabit(environment, name: "Lesen 20 min")
        #expect(state.habits() == [ControlHabit(id: habit.id, name: "Lesen 20 min", symbol: "book")])
        let paused = addHabit(environment, name: "Pausiert", pausedSince: environment.habits.today)
        #expect(state.habits().map(\.id) == [habit.id])
        #expect(!state.habits().map(\.id).contains(paused.id))
        environment.habits.delete(habit.id)
        #expect(state.habits().isEmpty)
    }
}
