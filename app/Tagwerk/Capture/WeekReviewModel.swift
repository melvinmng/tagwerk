import Foundation
import HealthBridge
import Observation
import TagwerkCore

/// State of the weekly review (phase 4 design §5.6, mockup R1a). Reads Health only when access was asked before,
/// and nothing here reaches an AI feature or the network.
@MainActor
@Observable
final class WeekReviewModel {
    private(set) var weekStart: PlanDay
    private(set) var review: WeekReview?

    private let store: IntakeStore
    private let health: any HealthStoring
    private let settings: AppSettings
    let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let completedReminders: (DateInterval) async -> [Date]
    @ObservationIgnored private let completedLocalTasks: (DateInterval) -> [Date]

    init(store: IntakeStore, health: any HealthStoring, settings: AppSettings, calendar: Calendar = .tagwerk,
         now: @escaping () -> Date = Date.init,
         completedReminders: @escaping (DateInterval) async -> [Date],
         completedLocalTasks: @escaping (DateInterval) -> [Date]) {
        self.store = store
        self.health = health
        self.settings = settings
        self.calendar = calendar
        self.now = now
        self.completedReminders = completedReminders
        self.completedLocalTasks = completedLocalTasks
        self.weekStart = PlanDay(date: IntakeRules.weekStart(containing: now(), calendar: calendar), calendar: calendar)
    }

    var today: PlanDay { PlanDay(date: now(), calendar: calendar) }
    var currentWeekStart: PlanDay { PlanDay(date: IntakeRules.weekStart(containing: now(), calendar: calendar), calendar: calendar) }
    /// Only back in time (design §9.8).
    var canGoForward: Bool { weekStart < currentWeekStart }
    var title: String { WeekReview.title(weekStart: weekStart, calendar: calendar) }

    func goBack() async {
        weekStart = weekStart.adding(days: -7, calendar: calendar)
        await reload()
    }

    func goForward() async {
        guard canGoForward else { return }
        weekStart = weekStart.adding(days: 7, calendar: calendar)
        await reload()
    }

    /// Jumps to the week containing a chosen day; later weeks show the current week (only back in time).
    func go(toWeekOf target: PlanDay) async {
        let start = PlanDay(date: IntakeRules.weekStart(containing: target.startDate(in: calendar), calendar: calendar),
                            calendar: calendar)
        weekStart = min(start, currentWeekStart)
        await reload()
    }

    func reload() async {
        let requested = weekStart
        let start = requested.startDate(in: calendar)
        let interval = DateInterval(start: start, end: requested.adding(days: 7, calendar: calendar).startDate(in: calendar))
        let days = (0..<7).map { requested.adding(days: $0, calendar: calendar) }
        let meals = days.flatMap { store.meals(on: $0, calendar: calendar) }
        let drinks = days.flatMap { store.drinks(on: $0, calendar: calendar) }
        var workouts = store.workouts(in: interval)
        if await health.access().wasAsked {
            let foreign = (try? await health.foreignWorkouts(in: interval)) ?? []
            workouts += foreign.map { workout in
                WorkoutValue(id: workout.id.uuidString, activity: workout.activity ?? .other, start: workout.start,
                             minutes: max(0, Int(workout.end.timeIntervalSince(workout.start) / 60)),
                             kilocalories: workout.kilocalories, sourceName: workout.sourceName, isOwn: false)
            }
        }
        let completed = await completedReminders(interval) + completedLocalTasks(interval)
        // A later navigation already moved on.
        guard weekStart == requested else { return }
        let goals = WeekReview.Goals(kcal: settings.goalKilocalories, waterMilliliters: settings.goalWaterMilliliters,
                                     workoutsPerWeek: settings.goalWorkoutsPerWeek,
                                     proteinGrams: settings.proteinGoalEnabled ? settings.goalProteinGrams : nil)
        review = WeekReview.make(weekStart: requested, now: now(), meals: meals, drinks: drinks, workouts: workouts,
                                 completedDates: completed, goals: goals, calendar: calendar)
    }
}
