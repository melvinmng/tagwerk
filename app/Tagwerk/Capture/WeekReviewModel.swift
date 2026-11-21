import Foundation
import HealthBridge
import Observation
import TagwerkCore

/// State of the weekly review (phase 4 design §5.6, mockup R1a, ST1). Reads Health workouts only when access was asked
/// before and steps only after the step sheet; nothing here reaches an AI feature or the network.
@MainActor
@Observable
final class WeekReviewModel {
    private(set) var weekStart: PlanDay
    private(set) var review: WeekReview?
    /// The "Schritte" section appears only after the step sheet was shown.
    private(set) var showsSteps = false
    /// Phase 7: the habits active in the shown week and the written reflection (empty without a routine store).
    private(set) var habitSummaries: [HabitWeekSummary] = []
    var reflection = WeekReflection()
    /// Whether the GitHub issues closed in the shown week are part of "Erledigt" (D6): the local numbers show first.
    private(set) var gitHub: GitHubClosed = .notConnected

    private let store: IntakeStore
    private let health: any HealthStoring
    private let settings: AppSettings
    let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let completedReminders: (DateInterval) async -> [Date]
    @ObservationIgnored private let completedLocalTasks: (DateInterval) -> [Date]
    @ObservationIgnored private let habits: HabitsModel?
    @ObservationIgnored private let routineStore: RoutineStore?
    @ObservationIgnored private let openPlanWeek: ((PlanDay) -> Void)?
    /// Closing moments of the issues assigned to the user that count as completed within an interval; `nil` while GitHub
    /// is not connected.
    @ObservationIgnored private let closedIssueDates: (@MainActor (DateInterval) async throws -> [Date])?

    init(store: IntakeStore, health: any HealthStoring, settings: AppSettings, calendar: Calendar = .tagwerk,
         now: @escaping () -> Date = Date.init,
         completedReminders: @escaping (DateInterval) async -> [Date],
         completedLocalTasks: @escaping (DateInterval) -> [Date],
         habits: HabitsModel? = nil, routineStore: RoutineStore? = nil, openPlanWeek: ((PlanDay) -> Void)? = nil,
         closedIssueDates: (@MainActor (DateInterval) async throws -> [Date])? = nil) {
        self.closedIssueDates = closedIssueDates
        self.habits = habits
        self.routineStore = routineStore
        self.openPlanWeek = openPlanWeek
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
        saveReflection()
        weekStart = weekStart.adding(days: -7, calendar: calendar)
        await reload()
    }

    func goForward() async {
        guard canGoForward else { return }
        saveReflection()
        weekStart = weekStart.adding(days: 7, calendar: calendar)
        await reload()
    }

    /// Jumps to the week containing a chosen day; later weeks show the current week (only back in time).
    func go(toWeekOf target: PlanDay) async {
        saveReflection()
        let start = PlanDay(date: IntakeRules.weekStart(containing: target.startDate(in: calendar), calendar: calendar),
                            calendar: calendar)
        weekStart = min(start, currentWeekStart)
        await reload()
    }

    /// Habits of the week and its reflection; the reflection belongs to the week, so a change of week loads another one.
    private func loadRoutineParts(for week: PlanDay) {
        if let habits {
            habitSummaries = HabitRules.weekSummaries(habits.habits, weekStart: week, today: today, facts: habits.facts, calendar: calendar)
        }
        if let routineStore { reflection = routineStore.reflection(weekStart: week) }
    }

    /// Writes the reflection of the shown week.
    func saveReflection() {
        routineStore?.saveReflection(reflection, weekStart: weekStart, at: now())
    }

    /// "Woche planen": opens "Planen" in the week view of the following week.
    func planNextWeek() {
        openPlanWeek?(weekStart.adding(days: 7, calendar: calendar))
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
        let stepsAsked = await health.stepsAccess() == .asked
        var steps: [PlanDay: Int] = [:]
        if stepsAsked {
            let sums = (try? await health.dailySteps(in: interval, calendar: calendar)) ?? []
            for sum in sums { steps[PlanDay(date: sum.start, calendar: calendar)] = sum.count }
        }
        let completed = await completedReminders(interval) + completedLocalTasks(interval)
        // A later navigation already moved on.
        guard weekStart == requested else { return }
        let goals = WeekReview.Goals(kcal: settings.goalKilocalories, waterMilliliters: settings.goalWaterMilliliters,
                                     workoutMinutesPerWeek: settings.goalWorkoutMinutesPerWeek,
                                     stepsPerDay: settings.goalStepsPerDay,
                                     proteinGrams: settings.proteinGoalEnabled ? settings.goalProteinGrams : nil)
        showsSteps = stepsAsked
        loadRoutineParts(for: requested)
        /// `completedDates` are the completions of reminders, local tasks and (once they arrived) closed GitHub issues.
        func makeReview(completedDates: [Date]) -> WeekReview {
            WeekReview.make(weekStart: requested, now: now(), meals: meals, drinks: drinks, workouts: workouts,
                            steps: steps, completedDates: completedDates, goals: goals, calendar: calendar)
        }
        review = makeReview(completedDates: completed)
        guard let closedIssueDates else {
            gitHub = .notConnected
            return
        }
        gitHub = .loading
        do {
            let closed = try await closedIssueDates(interval)
            // The answer belongs to the week that was asked for; the week on screen may be another one by now.
            guard weekStart == requested else { return }
            review = makeReview(completedDates: completed + closed)
            gitHub = .counted(closed.count)
        } catch {
            guard weekStart == requested else { return }
            gitHub = .unavailable
        }
    }

    /// The footer under "Erledigt".
    static func completedFooter(_ state: GitHubClosed) -> String {
        switch state {
        case .notConnected: String(localized: "Erinnerungen und lokale Aufgaben")
        case .loading: String(localized: "Erinnerungen und lokale Aufgaben. GitHub wird geladen …")
        case .counted: String(localized: "Erinnerungen, lokale Aufgaben und geschlossene GitHub-Issues")
        case .unavailable: String(localized: "Erinnerungen und lokale Aufgaben. GitHub ist gerade nicht erreichbar.")
        }
    }
}
