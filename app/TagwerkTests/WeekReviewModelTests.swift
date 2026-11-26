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

    private func make(_ health: FakeHealthStore, calls: Calls = Calls(), reminders: [Date] = [], local: [Date] = [],
                      closedIssueDates: (@MainActor (DateInterval) async throws -> [Date])? = nil,
                      withWeights: Bool = false) -> WeekReviewModel {
        let now = self.now
        let weights = withWeights ? WeightStore(intake: store, health: health, calendar: calendar) : nil
        return WeekReviewModel(store: store, health: health, settings: settings, calendar: calendar, now: { now }, weights: weights,
                               completedReminders: { interval in
                                   calls.reminderIntervals.append(interval)
                                   return reminders.filter { interval.contains($0) }
                               },
                               completedLocalTasks: { interval in local.filter { interval.contains($0) } },
                               closedIssueDates: closedIssueDates)
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

    // MARK: Closed GitHub issues (D6)

    private struct GitHubDown: Error {}

    /// Calls of the closed-issues reader, in order.
    final class ClosedCalls { var intervals: [DateInterval] = [] }

    /// Lets a test hold an answer of GitHub back until it decides to deliver it.
    @MainActor final class Gate {
        var continuation: CheckedContinuation<[Date], Never>?
        func wait() async -> [Date] { await withCheckedContinuation { continuation = $0 } }
        func open(_ dates: [Date]) { continuation?.resume(returning: dates); continuation = nil }
    }

    @Test func reload_withoutGitHub_isNotConnected_countsLocalOnly() async {
        let model = make(FakeHealthStore(), reminders: [now], local: [now])
        await model.reload()
        #expect(model.gitHub == .notConnected)
        #expect(model.review?.completedTasks == 2)
    }

    @Test func reload_withGitHub_addsClosedIssuesToCompletedTasks() async {
        let closed = [now, now.addingTimeInterval(-86_400)]
        let model = make(FakeHealthStore(), reminders: [now], local: [now], closedIssueDates: { _ in closed })
        await model.reload()
        #expect(model.gitHub == .counted(2))
        #expect(model.review?.completedTasks == 4)
    }

    @Test func reload_gitHubFails_isUnavailable_keepsLocalNumbers() async {
        let model = make(FakeHealthStore(), reminders: [now], local: [now], closedIssueDates: { _ in throw GitHubDown() })
        await model.reload()
        #expect(model.gitHub == .unavailable)
        #expect(model.review?.completedTasks == 2)
    }

    @Test func reload_showsLocalNumbersFirst_thenAddsGitHub() async {
        let gate = Gate()
        let model = make(FakeHealthStore(), reminders: [now], local: [now], closedIssueDates: { _ in await gate.wait() })
        let loading = Task { await model.reload() }
        while gate.continuation == nil { await Task.yield() }
        #expect(model.gitHub == .loading)
        #expect(model.review?.completedTasks == 2)
        gate.open([now])
        await loading.value
        #expect(model.gitHub == .counted(1))
        #expect(model.review?.completedTasks == 3)
    }

    @Test func reload_usesIntervalOfTheShownWeek() async {
        let calls = ClosedCalls()
        let model = make(FakeHealthStore(), closedIssueDates: { interval in calls.intervals.append(interval); return [] })
        await model.reload()
        let thisWeek = PlanDay(year: 2026, month: 11, day: 16)
        let before = PlanDay(year: 2026, month: 10, day: 19)
        #expect(calls.intervals.last == DateInterval(start: thisWeek.startDate(in: calendar),
                                                      end: thisWeek.adding(days: 7, calendar: calendar).startDate(in: calendar)))
        await model.go(toWeekOf: PlanDay(year: 2026, month: 10, day: 22))
        #expect(calls.intervals.last == DateInterval(start: before.startDate(in: calendar),
                                                      end: before.adding(days: 7, calendar: calendar).startDate(in: calendar)))
    }

    @Test func reload_lateAnswerOfAnotherWeek_isDropped() async {
        let gate = Gate()
        let currentWeek = PlanDay(year: 2026, month: 11, day: 16).startDate(in: calendar)
        let model = make(FakeHealthStore(), closedIssueDates: { interval in
            // The answer for the running week is held back; the earlier week answers at once with one issue.
            if interval.start == currentWeek { return await gate.wait() }
            return [interval.start.addingTimeInterval(3600)]
        })
        let late = Task { await model.reload() }
        while gate.continuation == nil { await Task.yield() }
        await model.goBack()
        #expect(model.gitHub == .counted(1))
        #expect(model.review?.completedTasks == 1)
        // Two issues of the week that was left arrive now and must not touch the week on screen.
        gate.open([now, now])
        await late.value
        #expect(model.weekStart == PlanDay(year: 2026, month: 11, day: 9))
        #expect(model.gitHub == .counted(1))
        #expect(model.review?.weekStart == PlanDay(year: 2026, month: 11, day: 9))
        #expect(model.review?.completedTasks == 1)
    }

    @Test func completedFooter_coversAllStates() {
        #expect(WeekReviewModel.completedFooter(.notConnected) == "Erinnerungen und lokale Aufgaben")
        #expect(WeekReviewModel.completedFooter(.loading) == "Erinnerungen und lokale Aufgaben. GitHub wird geladen …")
        #expect(WeekReviewModel.completedFooter(.counted(2)) == "Erinnerungen, lokale Aufgaben und geschlossene GitHub-Issues")
        #expect(WeekReviewModel.completedFooter(.unavailable)
                == "Erinnerungen und lokale Aufgaben. GitHub ist gerade nicht erreichbar.")
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

    @Test func proteinMean_isKnownWithoutGoal_goalComesFromTheSettings() async {
        let item = MealItem(name: "x", amount: "1", kcalMin: 500, kcal: 500, kcalMax: 500, protein: 40, carbs: 0, fat: 0, isEstimated: false)
        store.addMeal(MealValue(id: UUID(), date: now, kind: .lunch, title: "x", items: [item], origin: .manual), estimatedAt: nil)
        let model = make(FakeHealthStore())
        await model.reload()
        #expect(model.review?.averageProtein == 40)
        #expect(model.review?.goals.proteinGrams == nil)
        settings.proteinGoalEnabled = true
        await model.reload()
        #expect(model.review?.averageProtein == 40)
        #expect(model.review?.goals.proteinGrams != nil)
    }

    // MARK: Budget, goal plans and stored Health values (nutrition plan, C4)

    private func makeWithBudgets(_ health: FakeHealthStore, plans: [GoalPlan], withWeights: Bool = false) -> WeekReviewModel {
        let now = self.now
        let context = container.mainContext
        let goals = GoalStore(context: context, settings: settings, calendar: calendar, now: { now })
        for plan in plans { goals.adopt(plan) }
        let budgets = DayBudgets(intake: store, goals: goals, dayHealth: DayHealthStore(context: context, now: { now }), health: health,
                                 settings: settings, calendar: calendar, now: { now })
        let weights = withWeights ? WeightStore(intake: store, health: health, calendar: calendar) : nil
        return WeekReviewModel(store: store, health: health, settings: settings, budgets: budgets, calendar: calendar, now: { now },
                               weights: weights, completedReminders: { _ in [] }, completedLocalTasks: { _ in [] })
    }

    private func plan(from day: PlanDay, kcal: Int) -> GoalPlan {
        GoalPlan(validFrom: day, kcal: kcal, waterMilliliters: 2000, stepsPerDay: 8000, workoutMinutesPerWeek: 150)
    }

    @Test func weekReview_dayWithinBudget_usesPlanAndStoredHealthOfThatDay() async {
        let monday = PlanDay(year: 2026, month: 11, day: 16)
        let health = FakeHealthStore()
        health.setGroupAccess(.asked, for: .activeEnergy)
        health.activeEnergy = [DailyActiveEnergy(start: monday.startDate(in: calendar), kilocalories: 800)]
        settings.activityCreditPercent = 100
        // The goal rose from Tuesday on; Monday keeps its old plan and its stored activity.
        let model = makeWithBudgets(health, plans: [plan(from: PlanDay(year: 2026, month: 10, day: 1), kcal: 2000),
                                                    plan(from: monday.adding(days: 1, calendar: calendar), kcal: 2600)])
        await model.reload()
        let days = model.review?.days
        #expect(days?[0].goalKcal == 2800, "2.000 of the old plan plus the 800 credited that day")
        #expect(days?[1].goalKcal == 2600)
        health.activeEnergy = []
        await model.reload()
        #expect(model.review?.days[0].goalKcal == 2800, "a later silent Health does not change the past day")
    }

    @Test func weekReview_unknownActivity_fallsBackToBaseGoal() async {
        let model = makeWithBudgets(FakeHealthStore(), plans: [plan(from: PlanDay(year: 2026, month: 10, day: 1), kcal: 2100)])
        await model.reload()
        #expect(model.review?.days.map(\.goalKcal) == Array(repeating: 2100, count: 7))
    }

    @Test func weekReview_foreignEntries_countOnlyWhenSwitchedOn() async {
        let health = FakeHealthStore()
        health.setGroupAccess(.asked, for: .foreignNutrition)
        health.addForeignNutrition(day: PlanDay(year: 2026, month: 11, day: 17).startDate(in: calendar).addingTimeInterval(11 * 3600),
                                   kilocalories: 600, source: "Yazio")
        let model = makeWithBudgets(health, plans: [plan(from: PlanDay(year: 2026, month: 10, day: 1), kcal: 2300)])
        await model.reload()
        #expect(model.review?.daysWithMeals == 0 && health.nutritionReads.isEmpty)
        settings.countsForeignNutrition = true
        await model.reload()
        #expect(model.review?.days[1].kcal == 600)
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

    // MARK: Weight and goals of the shown week (C4)

    private func weightEntry(_ kilograms: Double, day: PlanDay) {
        let date = day.startDate(in: calendar).addingTimeInterval(7 * 3600)
        store.addWeight(WeightValue(id: UUID(), date: date, kilograms: kilograms))
    }

    @Test func reload_withoutWeightStore_hasNoWeightSection() async {
        weightEntry(82, day: PlanDay(year: 2026, month: 11, day: 16))
        let model = make(FakeHealthStore())
        await model.reload()
        #expect(model.weekWeight == nil)
    }

    @Test func reload_currentWeek_referencesToday() async {
        for (offset, kilograms) in [(0, 82.0), (1, 81.0), (2, 80.0)] {
            weightEntry(kilograms, day: PlanDay(year: 2026, month: 11, day: 16 + offset))
        }
        let model = make(FakeHealthStore(), withWeights: true)
        await model.reload()
        #expect(model.weekWeight?.figures.referenceDay == PlanDay(year: 2026, month: 11, day: 18))
        #expect(model.weekWeight?.figures.mean == 81)
        #expect(model.weekWeight?.figures.measurementCount == 3)
    }

    @Test func reload_weightOfTheShownWeek_notOfToday() async {
        // Last week 90, 89, 88 (mean 89); this week 80, 80, 80. Going back must show the mean at the end of last week.
        for (offset, kilograms) in [(0, 90.0), (1, 89.0), (2, 88.0)] {
            weightEntry(kilograms, day: PlanDay(year: 2026, month: 11, day: 9 + offset))
        }
        for offset in 0..<3 { weightEntry(80, day: PlanDay(year: 2026, month: 11, day: 16 + offset)) }
        let model = make(FakeHealthStore(), withWeights: true)
        await model.reload()
        #expect(model.weekWeight?.figures.mean == 80)
        // The window of the previous mean (5 to 11 Nov) holds the last three values of the week before: 89.
        #expect(model.weekWeight?.figures.previousMean == 89)
        #expect(model.weekWeight?.figures.change == -9)
        await model.goBack()
        #expect(model.weekWeight?.weekStart == PlanDay(year: 2026, month: 11, day: 9))
        #expect(model.weekWeight?.figures.referenceDay == PlanDay(year: 2026, month: 11, day: 15))
        #expect(model.weekWeight?.figures.mean == 89)
    }

    @Test func reload_changeIsTheDifferenceOfTwoWeeklyMeans() async {
        // Week of 9 Nov: mean 82 at its Sunday; the week before (2 Nov) has the mean 84 at its Sunday.
        for (offset, kilograms) in [(0, 83.0), (2, 82.0), (4, 81.0)] { weightEntry(kilograms, day: PlanDay(year: 2026, month: 11, day: 9 + offset)) }
        for (offset, kilograms) in [(0, 85.0), (2, 84.0), (4, 83.0)] { weightEntry(kilograms, day: PlanDay(year: 2026, month: 11, day: 2 + offset)) }
        let model = make(FakeHealthStore(), withWeights: true)
        await model.reload()
        await model.goBack()
        #expect(model.weekWeight?.figures.mean == 82)
        #expect(model.weekWeight?.figures.previousMean == 84)
        #expect(model.weekWeight?.figures.change == -2)
    }

    @Test func reload_bodyGroupNotAsked_usesOwnEntriesOnly() async {
        let health = FakeHealthStore()
        health.foreignWeights = (0..<3).map {
            ForeignWeight(id: UUID(), date: PlanDay(year: 2026, month: 11, day: 16 + $0).startDate(in: calendar).addingTimeInterval(8 * 3600),
                          kilograms: 99, sourceName: "Waage")
        }
        weightEntry(82, day: PlanDay(year: 2026, month: 11, day: 16))
        let notAsked = make(health, withWeights: true)
        await notAsked.reload()
        #expect(notAsked.weekWeight?.figures.measurementCount == 1)
        #expect(notAsked.weekWeight?.figures.mean == nil)

        health.setGroupAccess(.asked, for: .body)
        let asked = make(health, withWeights: true)
        await asked.reload()
        #expect(asked.weekWeight?.figures.measurementCount == 3)
        #expect(asked.weekWeight?.figures.mean != nil)
    }

    @Test func reload_weekWithoutMeasurements_keepsTheSectionWithAHint() async {
        let model = make(FakeHealthStore(), withWeights: true)
        await model.reload()
        #expect(model.weekWeight != nil)
        #expect(model.weekWeight?.figures.measurementCount == 0)
        #expect(model.isWeekEmpty)
    }

    @Test func isWeekEmpty_falseWhenOnlyWeightWasRecorded() async {
        weightEntry(82, day: PlanDay(year: 2026, month: 11, day: 17))
        let model = make(FakeHealthStore(), withWeights: true)
        await model.reload()
        #expect(model.review?.isEmpty == true)
        #expect(!model.isWeekEmpty)
    }

    @Test func reload_targetWeightComesFromThePlanOfTheShownWeek() async {
        let monday = PlanDay(year: 2026, month: 11, day: 16)
        var first = plan(from: PlanDay(year: 2026, month: 10, day: 1), kcal: 2000)
        first.targetWeightKg = 78
        var second = plan(from: monday.adding(days: 1, calendar: calendar), kcal: 2000)
        second.targetWeightKg = 75
        for offset in 0..<3 { weightEntry(80, day: monday.adding(days: offset, calendar: calendar)) }
        let model = makeWithBudgets(FakeHealthStore(), plans: [first, second], withWeights: true)
        await model.reload()
        #expect(model.weekWeight?.targetKg == 75)
        #expect(model.weekWeight?.figures.remainingToTarget == -5)
        await model.goBack()
        #expect(model.weekWeight?.targetKg == 78)
    }

    @Test func goalAge_namesThePlanOfTheGoalDay() async {
        let first = plan(from: PlanDay(year: 2026, month: 10, day: 26), kcal: 2000)
        let model = makeWithBudgets(FakeHealthStore(), plans: [first])
        await model.reload()
        // Goal day is today, Wednesday 18 Nov: 23 days after 26 Oct, three full weeks.
        #expect(model.goalAge?.validFrom == PlanDay(year: 2026, month: 10, day: 26))
        #expect(model.goalAge?.weeks == 3)
    }

    @Test func goalAge_withoutAStoredPlan_isHidden() async {
        let model = make(FakeHealthStore())
        await model.reload()
        #expect(model.goalAge == nil, "the single goals of the settings stand in; there is no date to name")
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
