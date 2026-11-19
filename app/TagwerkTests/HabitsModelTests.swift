import Foundation
import HealthBridge
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct HabitsModelTests {
    final class Clock { var now = testNow() }
    let container: ModelContainer
    let habitStore: HabitStore
    let intake: IntakeStore
    let settings: AppSettings
    let health: FakeHealthStore
    let clock = Clock()
    let calendar = testCalendar()
    var today: PlanDay { PlanDay(year: 2026, month: 11, day: 18) }

    init(access: HealthAccess = .authorized, stepsAccess: StepsAccess = .asked) throws {
        container = try ModelContainerFactory.make(inMemory: true)
        habitStore = HabitStore(context: container.mainContext, now: { testNow() })
        intake = IntakeStore(context: container.mainContext)
        settings = try AppSettings.current(in: container.mainContext)
        settings.goalWaterMilliliters = 2000
        settings.goalStepsPerDay = 8000
        health = FakeHealthStore(access: access, stepsAccess: stepsAccess)
    }

    private func makeModel() -> HabitsModel {
        let clock = self.clock
        return HabitsModel(store: habitStore, intake: intake, health: health, settings: settings, calendar: calendar,
                           now: { clock.now })
    }

    private func day(_ month: Int, _ day: Int) -> PlanDay { PlanDay(year: 2026, month: month, day: day) }

    @discardableResult
    private func addHabit(_ source: HabitSource, name: String = "Gewohnheit") -> Habit {
        let habit = Habit(name: name, symbol: "book", order: habitStore.habits().count, source: source, start: day(11, 1))
        habitStore.save(habit)
        return habit
    }

    @Test func waterHabit_isAutomaticOnceTheGoalIsReached() async throws {
        addHabit(.water)
        intake.addDrink(DrinkValue(id: UUID(), date: testNow().addingTimeInterval(-3600), milliliters: 1000))
        intake.addDrink(DrinkValue(id: UUID(), date: testNow().addingTimeInterval(-1800), milliliters: 1100))
        let model = makeModel()
        await model.reload()
        let row = try #require(model.rows.first)
        #expect(row.isFulfilled && row.isAutomatic)
        #expect(model.todayCounter == HabitCounter(done: 1, total: 1))
    }

    @Test func workoutHabit_countsOwnAndHealthWorkoutsFromTenMinutes() async throws {
        addHabit(.workout)
        let morning = testNow().addingTimeInterval(-3600)
        intake.addWorkout(WorkoutValue(id: UUID().uuidString, activity: .running, start: morning, minutes: 9, kilocalories: nil,
                                       sourceName: nil, isOwn: true))
        let yesterdayEvening = day(11, 17).startDate(in: calendar).addingTimeInterval(18 * 3600)
        health.foreign = [ForeignWorkout(id: UUID(), activityName: "Laufen", activity: .running, start: yesterdayEvening,
                                         end: yesterdayEvening.addingTimeInterval(42 * 60), kilocalories: nil, sourceName: "Apple Watch")]
        let model = makeModel()
        await model.reload()
        #expect(try #require(model.rows.first).isFulfilled == false)
        await model.reload(day: day(11, 17))
        #expect(try #require(model.rows.first).isFulfilled)
    }

    @Test func stepsHabit_staysOpenWithoutStepAccessAndCanBeCheckedByHand() async throws {
        let notAsked = try HabitsModelTests(stepsAccess: .notAsked)
        notAsked.addHabit(.steps)
        let model = notAsked.makeModel()
        await model.reload()
        #expect(try #require(model.rows.first).isFulfilled == false)
        #expect(notAsked.health.stepsReads.isEmpty)
        await model.toggle(try #require(model.rows.first).id)
        let row = try #require(model.rows.first)
        #expect(row.isFulfilled && !row.isAutomatic)
    }

    @Test func reload_readsHealthAtMostThreeTimesOverNinetyDays() async {
        addHabit(.steps)
        let model = makeModel()
        await model.reload()
        let expected = DateInterval(start: day(8, 21).startDate(in: calendar), end: day(11, 19).startDate(in: calendar))
        #expect(health.foreignReads == [expected])
        #expect(health.stepsReads == [expected])
    }

    @Test func failedHealthRead_keepsLastFactsOfTheSameDay() async throws {
        addHabit(.steps)
        health.steps = [DailySteps(start: today.startDate(in: calendar), count: 9000)]
        let model = makeModel()
        await model.reload()
        #expect(try #require(model.rows.first).isFulfilled)
        health.failStepReads = true
        await model.reload()
        #expect(try #require(model.rows.first).isFulfilled)
        // On the next day the old reading no longer counts.
        clock.now = clock.now.addingTimeInterval(86_400)
        await model.reload()
        #expect(try #require(model.rows.first).isFulfilled == false)
    }

    @Test func toggle_onAutomaticRowOrFutureDay_changesNothing() async throws {
        addHabit(.water)
        intake.addDrink(DrinkValue(id: UUID(), date: testNow(), milliliters: 2500))
        let model = makeModel()
        await model.reload()
        await model.toggle(try #require(model.rows.first).id)
        #expect(habitStore.checks(in: day(11, 1)...day(11, 30)).isEmpty)
        await model.reload(day: day(11, 19))
        #expect(model.day == today)
    }

    @Test func toggle_twice_removesTheManualCheck() async throws {
        let habit = addHabit(.manual)
        let model = makeModel()
        await model.reload()
        await model.toggle(habit.id)
        #expect(try #require(model.rows.first).isFulfilled)
        #expect(model.todayCounter == HabitCounter(done: 1, total: 1))
        await model.toggle(habit.id)
        #expect(try #require(model.rows.first).isFulfilled == false)
        #expect(habitStore.checks(in: day(11, 1)...day(11, 30)).isEmpty)
    }

    @Test func toggle_pastDay_canBeBackfilled() async throws {
        let habit = addHabit(.manual)
        let model = makeModel()
        await model.reload(day: day(11, 16))
        await model.toggle(habit.id)
        #expect(habitStore.checks(in: day(11, 1)...day(11, 30)) == [habit.id: [day(11, 16)]])
    }

    @Test func checkToday_reportsAnExistingManualCheck() async {
        let habit = addHabit(.manual)
        let model = makeModel()
        await model.reload()
        #expect(await model.checkToday(habit.id))
        #expect(await model.checkToday(habit.id) == false)
    }

    @Test func goalChange_changesPastDaysToo() async throws {
        addHabit(.water)
        intake.addDrink(DrinkValue(id: UUID(), date: day(11, 17).startDate(in: calendar).addingTimeInterval(36_000), milliliters: 2100))
        let model = makeModel()
        await model.reload(day: day(11, 17))
        #expect(try #require(model.rows.first).isFulfilled)
        settings.goalWaterMilliliters = 3000
        model.refreshLocal()
        #expect(try #require(model.rows.first).isFulfilled == false)
    }

    @Test func limits_tenUnpausedHabitsAndOneHabitPerSource() {
        let model = makeModel()
        let water = addHabit(.water)
        model.refreshLocal()
        #expect(model.takenSources(excluding: nil) == [.water])
        #expect(model.takenSources(excluding: water.id).isEmpty)
        for index in 0..<9 { addHabit(.manual, name: "Nr. \(index)") }
        model.refreshLocal()
        #expect(model.habits.count == 10 && !model.canAddHabit)
        habitStore.setPaused(water.id, true, today: today, calendar: calendar)
        model.refreshLocal()
        #expect(model.canAddHabit)
    }

    @Test func onChanged_firesAfterChanges() async {
        let habit = addHabit(.manual)
        let model = makeModel()
        var calls = 0
        model.onChanged = { calls += 1 }
        await model.reload()
        await model.toggle(habit.id)
        #expect(calls >= 1)
    }
}
