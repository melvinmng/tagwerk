import Foundation
import HealthBridge
import Observation
import TagwerkCore

/// Everything the page of one day shows from the model: its entries, the sums against the goals, the training time
/// and the steps. The shown page and the preview of a neighbour page are built from the same value.
struct CaptureDay: Equatable {
    var day: PlanDay
    var meals: [MealValue]
    var drinks: [DrinkValue]
    /// Own and Health workouts of the day, by start.
    var workouts: [WorkoutValue]
    /// The day's own entries only; what counts as eaten (with other apps' entries) is in `figures.totals`.
    var intake: DayIntake
    /// Plan, Health values and budget of the day.
    var figures: DayFigures
    var dayMinutes: Int
    var weekMinutes: Int
    /// `nil` without a value (shown as "–", never 0).
    var steps: Int?

    var hasEntries: Bool { !meals.isEmpty || !drinks.isEmpty || !workouts.isEmpty }
}

/// State of the "Erfassen" tab (mockup E1a, ST1): one day with totals against the goals, own entries, Health workouts
/// and steps.
///
/// Health is only read after the user was asked once; permission is requested only from `connectHealth()` and
/// `allowSteps()`. Steps stay in memory: no SwiftData, no log; only today's count reaches the plan header and,
/// with the nutrition switch, the widget.
@MainActor
@Observable
final class CaptureModel {
    /// A short confirmation with "Widerrufen".
    struct UndoNotice: Equatable, Identifiable {
        enum Action: Equatable {
            case remove(UUID)
            case restore(UUID)
        }

        let id = UUID()
        let text: String
        let action: Action

        static func == (lhs: UndoNotice, rhs: UndoNotice) -> Bool { lhs.id == rhs.id }
    }

    let settings: AppSettings
    let calendar: Calendar
    private let store: IntakeStore
    private let mirror: HealthMirror
    private let health: any HealthStoring
    /// Goal plan, Health values and budget of a day; shared with the plan header, the widget and the weekly review.
    let budgets: DayBudgets
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var deletedEntries: [UUID: IntakeStore.Deleted] = [:]

    var day: PlanDay
    private(set) var meals: [MealValue] = []
    private(set) var drinks: [DrinkValue] = []
    /// Own and Health workouts of the day, by start.
    private(set) var workouts: [WorkoutValue] = []
    private(set) var intake: DayIntake = .empty
    /// Plan, Health values and budget of the displayed day.
    private(set) var figures: DayFigures
    /// The same for today, whatever day is displayed: plan header, widget and Siri.
    private(set) var todayFigures: DayFigures
    /// Today's sums regardless of the displayed day: plan header, widget and Siri (phase 4).
    private(set) var todayIntake: DayIntake = .empty
    private(set) var todayHasEntries = false
    /// Training time of the displayed day and of its Monday-to-Sunday week; every workout counts, short ones too.
    private(set) var dayMinutes = 0
    private(set) var weekMinutes = 0
    /// `nil` until the first query, so the Health card does not flash when Health is connected.
    private(set) var access: HealthAccess?
    /// Step permission, asked separately from `access`; `nil` until the first query.
    private(set) var stepsAccess: StepsAccess?
    /// Permission group of the active energy, asked separately; `nil` until the first query.
    private(set) var activeEnergyAccess: HealthGroupAccess?
    /// Steps of the displayed day; `nil` without a value, while loading or without permission (shown as "–", never 0).
    private(set) var steps: Int?
    /// Today's steps with their day, so a value from before midnight is never shown as today's.
    private var todayStepsValue: DaySteps?
    private(set) var undo: UndoNotice?
    @ObservationIgnored private var weekForeign: [WorkoutValue] = []
    /// Health workouts and steps of the weeks around the shown day, read after each reload. A day change inside this
    /// window shows them at once, so the neighbour page and the page after it carry the same numbers.
    @ObservationIgnored private var healthCache: HealthCache?

    struct HealthCache {
        /// The weeks of the day before and the day after the shown day.
        var interval: DateInterval
        var foreign: [WorkoutValue]
        var steps: [PlanDay: Int]
    }

    struct DaySteps: Equatable {
        var day: PlanDay
        var count: Int
    }
    /// "Today" at the last reload: a view that showed today follows to the new day after midnight.
    @ObservationIgnored private var lastToday: PlanDay
    @ObservationIgnored private var pendingSync: Task<Void, Never>?

    /// Tests wait for each Health run, so no run outlives the test's store.
    @ObservationIgnored private let waitsForHealth: Bool

    /// `budgets` defaults to a service without stored plans and Health values: the single goals of the settings and the own
    /// entries stand in (previews, tests that do not care for the budget).
    init(store: IntakeStore, mirror: HealthMirror, health: any HealthStoring, settings: AppSettings, budgets: DayBudgets? = nil,
         calendar: Calendar = .tagwerk, now: @escaping () -> Date = Date.init, waitsForHealth: Bool = false) {
        self.waitsForHealth = waitsForHealth
        self.store = store
        self.mirror = mirror
        self.health = health
        self.settings = settings
        self.calendar = calendar
        self.now = now
        let budgets = budgets ?? DayBudgets(intake: store, goals: nil, dayHealth: nil, health: health, settings: settings,
                                            calendar: calendar, now: now)
        self.budgets = budgets
        let today = PlanDay(date: now(), calendar: calendar)
        self.day = today
        self.lastToday = today
        let initial = budgets.figures(on: today, own: .empty)
        self.figures = initial
        self.todayFigures = initial
    }

    var today: PlanDay { PlanDay(date: now(), calendar: calendar) }
    var isToday: Bool { day == today }
    var canGoForward: Bool { day < today }
    var showsHealthCard: Bool { access == .notDetermined && !settings.healthCardDismissed }
    var hasEntries: Bool { !meals.isEmpty || !drinks.isEmpty || !workouts.isEmpty }

    /// Today's steps for the plan header and the widget, whatever day the tab shows.
    var todaySteps: Int? {
        guard let todayStepsValue, todayStepsValue.day == today else { return nil }
        return todayStepsValue.count
    }

    /// The steps tile of the summary: hidden without Health, a button before the step sheet was shown, else the value.
    enum StepsTile: Equatable {
        case hidden
        case allow
        case value(Int?)
    }

    var stepsTile: StepsTile { stepsTile(for: steps) }

    /// The steps tile for a page that shows `steps` (the shown day or a neighbour).
    func stepsTile(for steps: Int?) -> StepsTile {
        switch stepsAccess {
        case .unavailable: .hidden
        case .notAsked: .allow
        case .asked, nil: .value(steps)
        }
    }

    enum SummaryTile: Hashable {
        case water, protein, steps, training
    }

    /// Tiles of the summary (ST1): water and protein in the first row, steps and the weekly training in the second.
    /// When each row would hold a single tile, they share one row.
    static func summaryRows(protein: Bool, steps: Bool, training: Bool) -> [[SummaryTile]] {
        let first: [SummaryTile] = protein ? [.water, .protein] : [.water]
        let second: [SummaryTile] = (steps ? [.steps] : []) + (training ? [.training] : [])
        if second.isEmpty { return [first] }
        if first.count == 1 && second.count == 1 { return [first + second] }
        return [first, second]
    }

    var summaryRows: [[SummaryTile]] { summaryRows(steps: steps, plan: figures.plan) }

    /// The tiles of a page: protein and training follow the goal plan that holds on that page's day.
    func summaryRows(steps: Int?, plan: GoalPlan) -> [[SummaryTile]] {
        Self.summaryRows(protein: plan.proteinGrams != nil, steps: stepsTile(for: steps) != .hidden,
                         training: plan.workoutMinutesPerWeek > 0)
    }

    // MARK: Loading

    /// Reloads the day; reads Health workouts only when access was asked before, and steps only after the step sheet.
    /// `refreshingLocalFirst: false` after `show(_:)`, which already read the store for the new day.
    func reload(refreshingLocalFirst: Bool = true) async {
        let today = self.today
        // Kept when a step read fails; only valid while the day stays the same.
        let shownBefore = day, stepsBefore = steps, todayStepsBefore = todaySteps
        if day > today || (day == lastToday && lastToday != today) { day = today }
        lastToday = today
        if refreshingLocalFirst { refreshLocal() }
        let requestedDay = day
        let access = await health.access()
        self.access = access
        let weekStart = IntakeRules.weekStart(containing: day.startDate(in: calendar), calendar: calendar)
        let weekEnd = PlanDay(date: weekStart, calendar: calendar).adding(days: 7, calendar: calendar).startDate(in: calendar)
        let week = DateInterval(start: weekStart, end: weekEnd)
        var foreignOfWeek: [WorkoutValue] = []
        if access.wasAsked {
            let foreign = (try? await health.foreignWorkouts(in: week)) ?? []
            foreignOfWeek = foreign.map(Self.workoutValue)
        }
        let stepsAccess = await health.stepsAccess()
        self.stepsAccess = stepsAccess
        self.activeEnergyAccess = await health.groupAccess(.activeEnergy)
        var stepsOfDay: Int?
        if stepsAccess == .asked {
            // A failed read (Health is locked while the phone is locked) keeps the last value instead of clearing it.
            let readOfDay = await dailySteps(on: requestedDay)
            stepsOfDay = readOfDay ?? (shownBefore == requestedDay ? stepsBefore : nil)
            // Today's count is current even when a later navigation discards the displayed day's result below.
            let readOfToday = requestedDay == today ? readOfDay : await dailySteps(on: today)
            let stepsOfToday = readOfToday ?? todayStepsBefore
            todayStepsValue = stepsOfToday.map { DaySteps(day: today, count: $0) }
        } else {
            todayStepsValue = nil
        }
        // A later navigation already moved on; its own reload applies its week.
        guard day == requestedDay else { return }
        weekForeign = foreignOfWeek
        steps = stepsOfDay
        // The day sums of the active energy and of other apps' nutrition go into the store; the figures read them from there.
        await budgets.refreshHealth(in: week)
        guard day == requestedDay else { return }
        refreshLocal(week: week)
        await prefetchNeighbourHealth()
    }

    private static func workoutValue(_ workout: ForeignWorkout) -> WorkoutValue {
        WorkoutValue(id: workout.id.uuidString, activity: workout.activity ?? .other, start: workout.start,
                     minutes: max(0, Int(workout.end.timeIntervalSince(workout.start) / 60)),
                     kilocalories: workout.kilocalories, sourceName: workout.sourceName, isOwn: false,
                     customName: workout.activity == nil ? workout.activityName : nil)
    }

    /// Reads the Health workouts and steps of the days around the shown one, in one query each, so the next page
    /// change needs no wait. Only what `reload()` reads as well (access asked before); a failed read keeps the
    /// cache as it is.
    private func prefetchNeighbourHealth() async {
        let shown = day
        let first = IntakeRules.weekStart(containing: shown.adding(days: -1, calendar: calendar).startDate(in: calendar), calendar: calendar)
        let lastWeek = IntakeRules.weekStart(containing: shown.adding(days: 1, calendar: calendar).startDate(in: calendar), calendar: calendar)
        let end = PlanDay(date: lastWeek, calendar: calendar).adding(days: 7, calendar: calendar).startDate(in: calendar)
        let interval = DateInterval(start: first, end: end)
        var foreign: [WorkoutValue] = []
        if await health.access().wasAsked {
            guard let read = try? await health.foreignWorkouts(in: interval) else { return }
            foreign = read.map(Self.workoutValue)
        }
        var steps: [PlanDay: Int] = [:]
        if await health.stepsAccess() == .asked {
            guard let sums = try? await health.dailySteps(in: interval, calendar: calendar) else { return }
            steps = Dictionary(sums.map { (PlanDay(date: $0.start, calendar: calendar), $0.count) }) { first, _ in first }
        }
        guard !Task.isCancelled else { return }
        healthCache = HealthCache(interval: interval, foreign: foreign, steps: steps)
        await budgets.refreshHealth(in: interval)
    }

    /// The step sum of one day: `.some(nil)` without statistics, `nil` when the read failed (errors are not logged:
    /// health data).
    private func dailySteps(on day: PlanDay) async -> Int?? {
        let interval = DateInterval(start: day.startDate(in: calendar), end: day.adding(days: 1, calendar: calendar).startDate(in: calendar))
        guard let sums = try? await health.dailySteps(in: interval, calendar: calendar) else { return nil }
        let count: Int? = sums.first { PlanDay(date: $0.start, calendar: calendar) == day }?.count
        return .some(count)
    }

    private func refreshLocal(week: DateInterval? = nil) {
        let dayStart = day.startDate(in: calendar)
        let dayEnd = day.adding(days: 1, calendar: calendar).startDate(in: calendar)
        let weekInterval = week ?? {
            let start = IntakeRules.weekStart(containing: dayStart, calendar: calendar)
            return DateInterval(start: start, end: PlanDay(date: start, calendar: calendar).adding(days: 7, calendar: calendar)
                .startDate(in: calendar))
        }()
        meals = store.meals(on: day, calendar: calendar)
        drinks = store.drinks(on: day, calendar: calendar)
        let weekWorkouts = store.workouts(in: weekInterval) + weekForeign.filter { weekInterval.contains($0.start) }
        workouts = weekWorkouts.filter { $0.start >= dayStart && $0.start < dayEnd }.sorted { $0.start < $1.start }
        dayMinutes = IntakeRules.workoutMinutes(weekWorkouts, in: DateInterval(start: dayStart, end: dayEnd))
        weekMinutes = IntakeRules.workoutMinutes(weekWorkouts, in: weekInterval)
        intake = IntakeRules.dayIntake(meals: meals, drinks: drinks)
        figures = budgets.figures(on: day, own: intake)
        refreshToday()
    }

    /// The shown day as the page displays it.
    var current: CaptureDay {
        CaptureDay(day: day, meals: meals, drinks: drinks, workouts: workouts, intake: intake, figures: figures,
                   dayMinutes: dayMinutes, weekMinutes: weekMinutes, steps: steps)
    }

    /// The page of another day for the preview beside the shown one: the local entries and, from the Health cache,
    /// the Health workouts and the steps. Reads no Health and changes nothing.
    func page(for target: PlanDay) -> CaptureDay {
        if target == day { return current }
        let dayStart = target.startDate(in: calendar)
        let dayEnd = target.adding(days: 1, calendar: calendar).startDate(in: calendar)
        let weekStart = IntakeRules.weekStart(containing: dayStart, calendar: calendar)
        let weekInterval = DateInterval(start: weekStart, end: PlanDay(date: weekStart, calendar: calendar).adding(days: 7, calendar: calendar)
            .startDate(in: calendar))
        let meals = store.meals(on: target, calendar: calendar)
        let drinks = store.drinks(on: target, calendar: calendar)
        let foreign = healthCache.map { $0.interval.contains(weekStart) ? $0.foreign : [] } ?? []
        let weekWorkouts = store.workouts(in: weekInterval) + foreign.filter { weekInterval.contains($0.start) }
        let workouts = weekWorkouts.filter { $0.start >= dayStart && $0.start < dayEnd }.sorted { $0.start < $1.start }
        let steps = target == today ? todaySteps : healthCache?.steps[target]
        let intake = IntakeRules.dayIntake(meals: meals, drinks: drinks)
        return CaptureDay(day: target, meals: meals, drinks: drinks, workouts: workouts, intake: intake,
                          figures: budgets.figures(on: target, own: intake),
                          dayMinutes: IntakeRules.workoutMinutes(weekWorkouts, in: DateInterval(start: dayStart, end: dayEnd)),
                          weekMinutes: IntakeRules.workoutMinutes(weekWorkouts, in: weekInterval), steps: steps)
    }

    /// Recomputes today's sums; every local change passes here (add, edit, delete, undo).
    private func refreshToday() {
        let today = self.today
        let todayMeals = day == today ? meals : store.meals(on: today, calendar: calendar)
        let todayDrinks = day == today ? drinks : store.drinks(on: today, calendar: calendar)
        todayIntake = IntakeRules.dayIntake(meals: todayMeals, drinks: todayDrinks)
        todayFigures = day == today ? figures : budgets.figures(on: today, own: todayIntake)
        todayHasEntries = !todayMeals.isEmpty || !todayDrinks.isEmpty
        onTodayChanged?()
    }

    /// Called after today's sums changed; the environment rewrites the widget snapshot.
    @ObservationIgnored var onTodayChanged: (() -> Void)?

    /// "~1.240 / 2.300 kcal · 1,2 / 2,0 l · 6.412 Schritte" for the head of "Planen"; `nil` when switched off or nothing
    /// recorded today. Steps appear only when known for today.
    var planHeaderLine: String? {
        guard settings.showsIntakeInPlan else { return nil }
        return IntakeFormat.planHeaderLine(intake: todayIntake, goalKcal: settings.goalKilocalories,
                                           goalWaterMilliliters: settings.goalWaterMilliliters, hasEntries: todayHasEntries,
                                           steps: todaySteps)
    }

    func goBack(days: Int = 1) async {
        day = day.adding(days: -days, calendar: calendar)
        await reload()
    }

    func goForward() async {
        guard canGoForward else { return }
        day = day.adding(days: 1, calendar: calendar)
        await reload()
    }

    /// Shows a day at once with the entries of the store; days after today show today.
    /// Synchronous, so a swipe or an arrow can animate the change. `reload()` adds Health afterwards.
    /// Returns `false` when the day stays the same (forward from today), so the view can signal the limit.
    @discardableResult
    func show(_ target: PlanDay) -> Bool {
        let next = min(target, today)
        guard next != day else { return false }
        day = next
        // The Health numbers of the neighbouring days were read after the last reload; without them (or beyond that
        // window) the steps and Health workouts of another day arrive with the reload.
        let nextWeek = IntakeRules.weekStart(containing: next.startDate(in: calendar), calendar: calendar)
        if let cache = healthCache, cache.interval.contains(nextWeek) {
            weekForeign = cache.foreign
            steps = next == today ? todaySteps : cache.steps[next]
        } else {
            steps = next == today ? todaySteps : nil
        }
        refreshLocal()
        return true
    }

    /// Jumps to a chosen day; days after today show today (only back in time).
    func go(to target: PlanDay) async {
        day = min(target, today)
        await reload()
    }

    /// Time of a new entry: now today, the same clock time on an earlier day (back-filling).
    var entryDate: Date {
        let current = now()
        guard !isToday else { return current }
        let offset = current.timeIntervalSince(PlanDay(date: current, calendar: calendar).startDate(in: calendar))
        return day.startDate(in: calendar).addingTimeInterval(offset)
    }

    // MARK: Entries

    /// `offersUndo: false` for Siri: a "Widerrufen" bar hours later, on the next opening, would only confuse.
    func addWater(_ milliliters: Int, at date: Date? = nil, offersUndo: Bool = true) async {
        let drink = DrinkValue(id: UUID(), date: date ?? entryDate, milliliters: milliliters)
        store.addDrink(drink)
        if offersUndo { undo = UndoNotice(text: String(localized: "\(String(milliliters)) ml Wasser erfasst"), action: .remove(drink.id)) }
        await changed()
    }

    func updateDrink(_ drink: DrinkValue) async {
        store.updateDrink(drink)
        await changed()
    }

    func saveMeal(_ meal: MealValue, estimatedAt: Date?, isNew: Bool) async {
        if isNew {
            store.addMeal(meal, estimatedAt: estimatedAt)
            undo = UndoNotice(text: String(localized: "\(meal.title) erfasst"), action: .remove(meal.id))
        } else {
            store.updateMeal(meal, estimatedAt: estimatedAt)
        }
        await changed()
    }

    /// "＋" in "Zuletzt und häufig": the same values now, slot by time.
    func repeatMeal(_ meal: MealValue) async {
        let date = entryDate
        let copy = MealValue(id: UUID(), date: date, kind: MealKind.forTime(date, calendar: calendar), title: meal.title,
                             items: meal.items, origin: meal.origin)
        await saveMeal(copy, estimatedAt: nil, isNew: true)
    }

    func saveWorkout(_ workout: WorkoutValue, isNew: Bool) async {
        if isNew {
            store.addWorkout(workout)
            undo = UndoNotice(text: String(localized: "\(workout.displayName) erfasst"), action: .remove(UUID(uuidString: workout.id) ?? UUID()))
        } else {
            store.updateWorkout(workout)
        }
        await changed()
    }

    func delete(_ id: UUID) async {
        guard let deleted = store.delete(id, healthNotBefore: now().addingTimeInterval(HealthMirror.undoWindow)) else { return }
        deletedEntries[id] = deleted
        undo = UndoNotice(text: String(localized: "Eintrag gelöscht"), action: .restore(id))
        refreshLocal()
        mirror.syncAfterUndoWindow()
    }

    func undoLast() async {
        guard let notice = undo else { return }
        undo = nil
        switch notice.action {
        case .remove(let id):
            store.delete(id, healthNotBefore: now())
            await changed()
        case .restore(let id):
            guard let deleted = deletedEntries.removeValue(forKey: id) else { return }
            store.restore(deleted)
            await changed()
        }
    }

    func clearUndo(_ notice: UndoNotice) {
        if undo == notice { undo = nil }
    }

    /// Shows the change at once; the Health mirror runs afterwards and never holds up a sheet.
    private func changed() async {
        refreshLocal()
        let mirror = self.mirror
        let run = Task { await mirror.sync() }
        pendingSync = run
        if waitsForHealth { await run.value }
    }

    /// Waits for the Health run started by the last change (tests, catch-up).
    func waitForHealth() async {
        await pendingSync?.value
    }

    func estimatedAt(meal id: UUID) -> Date? { store.estimatedAt(meal: id) }
    func isInHealth(_ id: UUID) -> Bool { store.healthSynced(id) }

    // MARK: Health

    func connectHealth() async {
        try? await health.requestAuthorization()
        await reload()
        await mirror.sync()
    }

    /// "In Health erlauben" in the steps tile: before Health was ever connected, the full sheet (one sheet for
    /// everything); afterwards a sheet for steps only, which leaves the existing access untouched.
    func allowSteps() async {
        if access?.wasAsked == true {
            await connectSteps()
        } else {
            await connectHealth()
        }
    }

    /// The budget line offers "In Health erlauben" for the active energy until its sheet was shown; with crediting switched off
    /// (share 0) there is nothing to offer.
    func offersActiveEnergy(for budget: EnergyBudget) -> Bool {
        activeEnergyAccess == .notAsked && budget.creditPercent > 0
    }

    /// "In Health erlauben" at the budget line: the sheet for the active energy only, which leaves the other permissions alone.
    func allowActiveEnergy() async {
        try? await health.requestAuthorization(for: .activeEnergy)
        await reload()
    }

    func connectSteps() async {
        try? await health.requestStepsAuthorization()
        await reload()
    }

    func dismissHealthCard() {
        settings.healthCardDismissed = true
    }

    /// Catch-up after returning to the foreground.
    func syncPending() async {
        await mirror.sync()
    }

    // MARK: Helpers for the sheets

    func repeatSuggestions(filter: String) -> [MealValue] {
        let current = now()
        let since = calendar.date(byAdding: .day, value: -IntakeRules.repeatWindowDays, to: current) ?? current
        return IntakeRules.repeatSuggestions(meals: store.meals(since: since), hidden: [], filter: filter, now: current,
                                             calendar: calendar)
    }

    /// Defaults of a new workout: the last one's type and duration, otherwise strength training for 45 min.
    var workoutDefaults: (activity: WorkoutActivity, minutes: Int) {
        guard let latest = store.latestWorkout() else { return (.strength, 45) }
        return (latest.activity, latest.minutes)
    }

    /// Warning when a typed workout overlaps a Health workout of the day.
    func overlapWarning(start: Date, minutes: Int) -> String? {
        let interval = DateInterval(start: start, duration: TimeInterval(max(1, minutes) * 60))
        guard let other = IntakeRules.overlappingWorkout(interval, in: weekForeign) else { return nil }
        let time = DateText.time(other.start, calendar: calendar)
        let source = other.sourceName ?? "Health"
        return String(localized: "Überschneidet sich mit „\(other.displayName)“ (\(time), \(source)). Das Training würde doppelt gezählt.")
    }
}
