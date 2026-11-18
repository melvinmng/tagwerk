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
}

struct PageSwipeTests {
    @Test func swipeRight_goesBack() {
        #expect(PageSwipe.direction(start: CGPoint(x: 100, y: 300), translation: CGSize(width: 80, height: 10)) == .back)
    }

    @Test func swipeLeft_goesForward() {
        #expect(PageSwipe.direction(start: CGPoint(x: 300, y: 300), translation: CGSize(width: -80, height: -12)) == .forward)
    }

    @Test func shortSwipe_ignored() {
        #expect(PageSwipe.direction(start: CGPoint(x: 100, y: 300), translation: CGSize(width: 40, height: 0)) == nil)
    }

    @Test func verticalScroll_ignored() {
        #expect(PageSwipe.direction(start: CGPoint(x: 100, y: 300), translation: CGSize(width: 70, height: 90)) == nil)
    }

    /// The system back gesture starts at the leading edge; it must not also switch the week.
    @Test func edgeSwipe_leftToSystemBack() {
        #expect(PageSwipe.direction(start: CGPoint(x: 12, y: 300), translation: CGSize(width: 120, height: 0)) == nil)
    }
}
