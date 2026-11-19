import Foundation
import HealthBridge
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct WeekReviewModelTests {
    let container: ModelContainer
    let store: IntakeStore
    let settings: AppSettings
    let calendar = Calendar.tagwerk
    /// Wednesday, 18 Nov 2026, 12:00.
    let now = PlanDay(year: 2026, month: 11, day: 18).startDate(in: .tagwerk).addingTimeInterval(12 * 3600)

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        store = IntakeStore(context: container.mainContext)
        settings = try AppSettings.current(in: container.mainContext)
    }

    final class Calls { var reminderIntervals: [DateInterval] = [] }

    private func make(_ health: FakeHealthStore, calls: Calls = Calls(), reminders: [Date] = [], local: [Date] = []) -> WeekReviewModel {
        let now = self.now
        return WeekReviewModel(store: store, health: health, settings: settings, calendar: calendar, now: { now },
                               completedReminders: { interval in
                                   calls.reminderIntervals.append(interval)
                                   return reminders.filter { interval.contains($0) }
                               },
                               completedLocalTasks: { interval in local.filter { interval.contains($0) } })
    }

    @Test func review_readsHealthOnlyWhenAsked() async {
        let notAsked = FakeHealthStore(access: .notDetermined)
        let model = make(notAsked)
        await model.reload()
        #expect(notAsked.foreignReads.isEmpty)
        #expect(notAsked.authorizationRequests == 0)

        let asked = FakeHealthStore(access: .authorized)
        asked.foreign = [ForeignWorkout(id: UUID(), activityName: "Laufen", activity: .running, start: now.addingTimeInterval(-3600),
                                        end: now.addingTimeInterval(-1200), kilocalories: nil, sourceName: "Apple Watch")]
        let withHealth = make(asked)
        await withHealth.reload()
        #expect(asked.foreignReads.count == 1)
        #expect(withHealth.review?.workoutCount == 1)
    }

    @Test func steps_readOnlyWhenAsked() async {
        let monday = PlanDay(year: 2026, month: 11, day: 16)
        let notAsked = FakeHealthStore(stepsAccess: .notAsked)
        notAsked.steps = [DailySteps(start: monday.startDate(in: calendar), count: 9000)]
        let model = make(notAsked)
        await model.reload()
        #expect(notAsked.stepsReads.isEmpty)
        #expect(notAsked.stepsAuthorizationRequests == 0)
        #expect(model.review?.daysWithSteps == 0)
        #expect(model.showsSteps == false)

        let asked = FakeHealthStore(access: .notDetermined, stepsAccess: .asked)
        asked.steps = [DailySteps(start: monday.startDate(in: calendar), count: 9000),
                       DailySteps(start: monday.adding(days: 1, calendar: calendar).startDate(in: calendar), count: 5000)]
        let withSteps = make(asked)
        await withSteps.reload()
        #expect(asked.stepsReads.count == 1)
        #expect(asked.stepsReads.first?.start == monday.startDate(in: calendar))
        #expect(withSteps.review?.days.prefix(3).map(\.steps) == [9000, 5000, nil])
        #expect(withSteps.review?.stepGoalDays == 1)
        #expect(withSteps.showsSteps)
    }

    @Test func review_usesMinuteGoalFromSettings() async {
        settings.goalWorkoutMinutesPerWeek = 90
        settings.goalStepsPerDay = 10_000
        let model = make(FakeHealthStore())
        await model.reload()
        #expect(model.review?.goals.workoutMinutesPerWeek == 90)
        #expect(model.review?.goals.stepsPerDay == 10_000)
    }

    @Test func review_countsIntakeAndCompletions() async {
        store.addDrink(DrinkValue(id: UUID(), date: now, milliliters: 2000))
        let model = make(FakeHealthStore(), reminders: [now.addingTimeInterval(-86_400)], local: [now, now.addingTimeInterval(-30 * 86_400)])
        await model.reload()
        #expect(model.review?.waterGoalDays == 1)
        #expect(model.review?.completedTasks == 2)
        #expect(model.review?.isCurrentWeek == true)
    }

    @Test func review_goBack_onlyPast() async {
        let calls = Calls()
        let model = make(FakeHealthStore(), calls: calls)
        await model.reload()
        #expect(model.canGoForward == false)
        await model.goForward()
        #expect(model.weekStart == PlanDay(year: 2026, month: 11, day: 16))
        await model.goBack()
        #expect(model.weekStart == PlanDay(year: 2026, month: 11, day: 9))
        #expect(model.title == "KW 46 · 9.–15. Nov")
        #expect(model.canGoForward)
        #expect(calls.reminderIntervals.last?.start == PlanDay(year: 2026, month: 11, day: 9).startDate(in: calendar))
    }

    @Test func review_goToDay_showsItsWeek() async {
        let model = make(FakeHealthStore())
        await model.reload()
        // Thursday 22 Oct 2026 belongs to the week starting Monday 19 Oct.
        await model.go(toWeekOf: PlanDay(year: 2026, month: 10, day: 22))
        #expect(model.weekStart == PlanDay(year: 2026, month: 10, day: 19))
        #expect(model.review?.weekStart == PlanDay(year: 2026, month: 10, day: 19))
    }

    @Test func review_goToFutureDay_staysCurrentWeek() async {
        let model = make(FakeHealthStore())
        await model.reload()
        await model.goBack()
        await model.go(toWeekOf: PlanDay(year: 2026, month: 12, day: 2))
        #expect(model.weekStart == PlanDay(year: 2026, month: 11, day: 16))
    }

    @Test func proteinOnlyWithGoal() async {
        let item = MealItem(name: "x", amount: "1", kcalMin: 500, kcal: 500, kcalMax: 500, protein: 40, carbs: 0, fat: 0, isEstimated: false)
        store.addMeal(MealValue(id: UUID(), date: now, kind: .lunch, title: "x", items: [item], origin: .manual), estimatedAt: nil)
        let model = make(FakeHealthStore())
        await model.reload()
        #expect(model.review?.averageProtein == nil)
        settings.proteinGoalEnabled = true
        await model.reload()
        #expect(model.review?.averageProtein == 40)
    }

    // MARK: Habits and reflection (phase 7)

    private func makePhase7(_ habits: HabitsModel, routines: RoutineStore, opened: Opened = Opened()) -> WeekReviewModel {
        let now = self.now
        return WeekReviewModel(store: store, health: FakeHealthStore(), settings: settings, calendar: calendar, now: { now },
                               completedReminders: { _ in [] }, completedLocalTasks: { _ in [] },
                               habits: habits, routineStore: routines, openPlanWeek: { opened.days.append($0) })
    }

    final class Opened { var days: [PlanDay] = [] }

    @Test func reload_loadsHabitSummariesAndTheReflectionOfTheShownWeek() async {
        let now = self.now
        let habitStore = HabitStore(context: container.mainContext, now: { now })
        let habit = Habit(name: "Lesen", symbol: "book", order: 0, start: PlanDay(year: 2026, month: 11, day: 1))
        habitStore.save(habit)
        habitStore.setCheck(habit.id, on: PlanDay(year: 2026, month: 11, day: 16), checked: true, at: now)
        let habits = HabitsModel(store: habitStore, intake: store, health: FakeHealthStore(), settings: settings, calendar: calendar,
                                 now: { now })
        let routines = RoutineStore(context: container.mainContext, now: { now })
        routines.saveReflection(WeekReflection(wentWell: "Sport"), weekStart: PlanDay(year: 2026, month: 11, day: 16), at: now)
        let model = makePhase7(habits, routines: routines)
        await model.reload()
        #expect(model.habitSummaries.count == 1)
        #expect(model.habitSummaries[0].done == 1 && model.habitSummaries[0].isRunning)
        #expect(model.reflection.wentWell == "Sport")
        // The previous week has no reflection and no active habit days before the start.
        await model.goBack()
        #expect(model.reflection == WeekReflection())
    }

    @Test func saveReflection_writesTheShownWeek() async {
        let now = self.now
        let habits = HabitsModel(store: HabitStore(context: container.mainContext, now: { now }), intake: store,
                                 health: FakeHealthStore(), settings: settings, calendar: calendar, now: { now })
        let routines = RoutineStore(context: container.mainContext, now: { now })
        let model = makePhase7(habits, routines: routines)
        await model.reload()
        model.reflection.burdens = "Viel los"
        model.reflection.tasksPlanned = true
        model.saveReflection()
        #expect(routines.reflection(weekStart: PlanDay(year: 2026, month: 11, day: 16)).burdens == "Viel los")
        #expect(routines.reflection(weekStart: PlanDay(year: 2026, month: 11, day: 16)).tasksPlanned)
    }

    @Test func planNextWeek_showsTheWeekViewOfTheFollowingWeek() async {
        let now = self.now
        let habits = HabitsModel(store: HabitStore(context: container.mainContext, now: { now }), intake: store,
                                 health: FakeHealthStore(), settings: settings, calendar: calendar, now: { now })
        let opened = Opened()
        let model = makePhase7(habits, routines: RoutineStore(context: container.mainContext, now: { now }), opened: opened)
        await model.reload()
        model.planNextWeek()
        #expect(opened.days == [PlanDay(year: 2026, month: 11, day: 23)])
    }
}

struct PageSwipeTests {
    @Test func swipeRight_goesBack() {
        #expect(PageSwipe.direction(start: CGPoint(x: 100, y: 300), translation: CGSize(width: 90, height: 10)) == .back)
    }

    @Test func swipeLeft_goesForward() {
        #expect(PageSwipe.direction(start: CGPoint(x: 300, y: 300), translation: CGSize(width: -90, height: -12)) == .forward)
    }

    /// Same thresholds as the swipe in "Planen": at least 80 pt sideways.
    @Test func shortSwipe_ignored() {
        #expect(PageSwipe.direction(start: CGPoint(x: 100, y: 300), translation: CGSize(width: 70, height: 0)) == nil)
    }

    /// Twice as far sideways as up or down, so list scrolling wins otherwise.
    @Test func diagonalDrag_ignored() {
        #expect(PageSwipe.direction(start: CGPoint(x: 100, y: 300), translation: CGSize(width: 100, height: 60)) == nil)
    }

    /// In pushed screens the system back gesture starts at the leading edge; it must not also switch the page.
    @Test func edgeSwipe_onlyIgnoredWhenRequested() {
        let start = CGPoint(x: 12, y: 300), translation = CGSize(width: 120, height: 0)
        #expect(PageSwipe.direction(start: start, translation: translation, excludesLeadingEdge: true) == nil)
        #expect(PageSwipe.direction(start: start, translation: translation, excludesLeadingEdge: false) == .back)
    }
}
