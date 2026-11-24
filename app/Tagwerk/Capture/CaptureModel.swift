import Foundation
import HealthBridge
import Observation
import OSLog
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
/// Health is only read after the user was asked once. The Health card asks for everything in one system sheet
/// (`connectHealth()`); every other request goes through the same guard, so two sheets never compete. Steps stay in memory: no SwiftData, no log; only today's count reaches the plan header and,
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
    /// Own and foreign body weights for the sheet, the morning start and the trends page.
    let weights: WeightStore
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
    /// Permission group "weitere Nährwerte nach Health" (settings); `nil` until the first query.
    private(set) var furtherNutrientsAccess: HealthGroupAccess?
    /// Permission group of other apps' nutrition (settings); `nil` until the first query.
    private(set) var foreignNutritionAccess: HealthGroupAccess?
    /// Permission group "body" (weight and body fat, read and write); `nil` until the first query.
    private(set) var bodyAccess: HealthGroupAccess?
    /// Whether Health is connected at all (the core group was asked); only then a weight asks for its own group.
    private(set) var healthConnected = false
    /// Write permission for the weight and the height; `nil` until the first query. A refusal is shown in the settings.
    private(set) var weightWriteAccess: HealthWriteAccess?
    private(set) var heightWriteAccess: HealthWriteAccess?
    @ObservationIgnored private let logger = Logger(subsystem: "local.tagwerk", category: "health")
    /// Whether a system sheet of Health is being requested right now; a second request in that time is dropped.
    @ObservationIgnored private var healthRequestInFlight = false
    /// Steps of the displayed day; `nil` without a value, while loading or without permission (shown as "–", never 0).
    private(set) var steps: Int?
    /// Today's steps with their day, so a value from before midnight is never shown as today's.
    private var todayStepsValue: DaySteps?
    private(set) var undo: UndoNotice?
    /// Weight of today, yesterday and the 7-day mean for the row "Verlauf und Ziele"; read with every reload.
    private(set) var weightOverview = WeightOverview()
    @ObservationIgnored private var weekForeign: [WorkoutValue] = []
    /// Health workouts and steps of the weeks around the shown day, read after each reload. A day change inside this
    /// window shows them at once, so the neighbour page and the page after it carry the same numbers.
    @ObservationIgnored private var healthCache: HealthCache?
    /// The read of the neighbouring weeks runs after `reload()` has returned, so the day is on screen without waiting for it. A newer
    /// reload cancels it.
    @ObservationIgnored private var prefetch: Task<Void, Never>?
    /// The neighbour pages built since the model last changed: the preview asks for them on every body evaluation, and each one is a
    /// set of SwiftData fetches. Emptied by every change (`refreshLocal`) and by the arrival of the prefetch.
    @ObservationIgnored private var pageCache: [PlanDay: CaptureDay] = [:]
    /// Bumped whenever the neighbour pages are dropped. `page(for:)` reads it, so a view that shows a preview is rendered again when the
    /// pages change without any other observed value changing (the neighbour numbers arriving from the prefetch).
    private var pageRevision = 0

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
    /// Whether `reload()` waits for the read of the neighbouring weeks; defaults to `waitsForHealth`.
    @ObservationIgnored private let waitsForPrefetch: Bool

    /// `budgets` defaults to a service without stored plans and Health values: the single goals of the settings and the own
    /// entries stand in (previews, tests that do not care for the budget).
    init(store: IntakeStore, mirror: HealthMirror, health: any HealthStoring, settings: AppSettings, budgets: DayBudgets? = nil,
         calendar: Calendar = .tagwerk, now: @escaping () -> Date = Date.init, waitsForHealth: Bool = false,
         waitsForPrefetch: Bool? = nil) {
        self.waitsForHealth = waitsForHealth
        self.waitsForPrefetch = waitsForPrefetch ?? waitsForHealth
        self.store = store
        self.mirror = mirror
        self.health = health
        self.weights = WeightStore(intake: store, health: health, calendar: calendar)
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
        // The Health card asks for the steps as well; while it is shown, the tile must not offer a second prompt.
        case .notAsked: showsHealthCard ? .value(steps) : .allow
        case .asked, nil: .value(steps)
        }
    }

    enum SummaryTile: Hashable {
        case water, steps, training
    }

    /// Tiles of the summary (ST1): water, steps and the weekly training. Protein moved to the card "Nährwerte" (decision NU2b).
    /// Water and steps share the first row; the training follows alone or, with room, on the same row.
    static func summaryRows(steps: Bool, training: Bool) -> [[SummaryTile]] {
        let tiles: [SummaryTile] = [.water] + (steps ? [.steps] : []) + (training ? [.training] : [])
        // Up to two tiles per row, so a tile keeps enough width for its value at larger text sizes.
        return stride(from: 0, to: tiles.count, by: 2).map { Array(tiles[$0..<min($0 + 2, tiles.count)]) }
    }

    var summaryRows: [[SummaryTile]] { summaryRows(steps: steps, plan: figures.plan) }

    /// The tiles of a page: the training tile follows the goal plan that holds on that page's day.
    func summaryRows(steps: Int?, plan: GoalPlan) -> [[SummaryTile]] {
        Self.summaryRows(steps: stepsTile(for: steps) != .hidden, training: plan.workoutMinutesPerWeek > 0)
    }

    /// The rows of the card "Nährwerte" for a page: the totals of the day (own and, when switched on, other apps' entries) against the
    /// goal plan and the budget of that day.
    func nutrientRows(for figures: DayFigures) -> [NutrientRow] {
        NutrientCard.rows(totals: figures.totals, plan: figures.plan, budget: figures.budget, visible: settings.visibleNutrients)
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
        let weekStart = IntakeRules.weekStart(containing: day.startDate(in: calendar), calendar: calendar)
        let weekEnd = PlanDay(date: weekStart, calendar: calendar).adding(days: 7, calendar: calendar).startDate(in: calendar)
        let week = DateInterval(start: weekStart, end: weekEnd)
        // The statuses do not depend on each other: asked together instead of one HealthKit call after the other on the main actor.
        let health = self.health
        async let accessRead = health.access()
        async let stepsAccessRead = health.stepsAccess()
        async let activeEnergyRead = health.groupAccess(.activeEnergy)
        async let furtherNutrientsRead = health.groupAccess(.moreNutrients)
        async let foreignNutritionRead = health.groupAccess(.foreignNutrition)
        async let bodyRead = health.groupAccess(.body)
        async let weightWriteRead = health.writeAccess(for: .weight)
        async let heightWriteRead = health.writeAccess(for: .height)
        let access = await accessRead
        let stepsAccess = await stepsAccessRead
        // The reads that follow depend on the statuses; the workouts of the week and the steps of the day and of today go together.
        async let foreignRead = foreignWorkouts(in: week, access: access)
        async let stepsRead = readSteps(requestedDay: requestedDay, today: today, stepsAccess: stepsAccess)
        self.access = access
        self.stepsAccess = stepsAccess
        self.activeEnergyAccess = await activeEnergyRead
        self.furtherNutrientsAccess = await furtherNutrientsRead
        self.foreignNutritionAccess = await foreignNutritionRead
        self.bodyAccess = await bodyRead
        self.weightWriteAccess = await weightWriteRead
        self.heightWriteAccess = await heightWriteRead
        self.healthConnected = access.wasAsked
        let foreignOfWeek = await foreignRead
        let stepReads = await stepsRead
        var stepsOfDay: Int?
        if stepReads.asked {
            // A failed read (Health is locked while the phone is locked) keeps the last value instead of clearing it.
            stepsOfDay = stepReads.day ?? (shownBefore == requestedDay ? stepsBefore : nil)
            // Today's count is current even when a later navigation discards the displayed day's result below.
            let stepsOfToday = stepReads.today ?? todayStepsBefore
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
        await refreshWeightOverview()
        prefetch?.cancel()
        let run = Task { await prefetchNeighbourHealth() }
        prefetch = run
        // Tests wait for it; the app does not: the page is complete without the neighbours' Health numbers.
        if waitsForPrefetch { await run.value }
    }

    /// Waits for the read of the neighbouring weeks that the last reload started (tests).
    func waitForPrefetch() async {
        await prefetch?.value
    }

    /// The Health workouts of the week as values; empty when Health was not asked or the read fails.
    private func foreignWorkouts(in week: DateInterval, access: HealthAccess) async -> [WorkoutValue] {
        guard access.wasAsked else { return [] }
        return ((try? await health.foreignWorkouts(in: week)) ?? []).map(Self.workoutValue)
    }

    /// What the step reads of a reload brought. `day` and `today` are `.some(nil)` for "no statistics" and `nil` for a failed read.
    private struct StepReads {
        var asked: Bool
        var day: Int??
        var today: Int??
    }

    /// The steps of the shown day and of today, read together; nothing is read before the step sheet was shown. When the shown day
    /// is today, one read serves both.
    private func readSteps(requestedDay: PlanDay, today: PlanDay, stepsAccess: StepsAccess) async -> StepReads {
        guard stepsAccess == .asked else { return StepReads(asked: false, day: nil, today: nil) }
        async let dayRead = dailySteps(on: requestedDay)
        async let otherRead: Int?? = requestedDay == today ? nil : dailySteps(on: today)
        let readOfDay = await dayRead
        let readOfToday = requestedDay == today ? readOfDay : await otherRead
        return StepReads(asked: true, day: readOfDay, today: readOfToday)
    }

    /// The weight figures from own entries and, once the group "body" was asked, the measurements of other apps.
    func refreshWeightOverview() async {
        let today = self.today
        let end = today.adding(days: 1, calendar: calendar).startDate(in: calendar)
        let days = await weights.dayValues(in: DateInterval(start: end.addingTimeInterval(-45 * 86_400), end: end))
        weightOverview = WeightOverview.make(days, today: today, calendar: calendar)
    }

    static func workoutValue(_ workout: ForeignWorkout) -> WorkoutValue {
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
        // The neighbour pages built before this point lack these numbers; drop them now and once more after the budgets changed.
        invalidatePages()
        await budgets.refreshHealth(in: interval)
        guard !Task.isCancelled else { return }
        invalidatePages()
    }

    /// The step sum of one day: `.some(nil)` without statistics, `nil` when the read failed (errors are not logged:
    /// health data).
    private func dailySteps(on day: PlanDay) async -> Int?? {
        let interval = DateInterval(start: day.startDate(in: calendar), end: day.adding(days: 1, calendar: calendar).startDate(in: calendar))
        guard let sums = try? await health.dailySteps(in: interval, calendar: calendar) else { return nil }
        let count: Int? = sums.first { PlanDay(date: $0.start, calendar: calendar) == day }?.count
        return .some(count)
    }

    private func invalidatePages() {
        pageCache.removeAll()
        pageRevision += 1
    }

    private func refreshLocal(week: DateInterval? = nil) {
        invalidatePages()
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
        _ = pageRevision
        if target == day { return current }
        if let cached = pageCache[target] { return cached }
        let page = buildPage(for: target)
        pageCache[target] = page
        return page
    }

    private func buildPage(for target: PlanDay) -> CaptureDay {
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

    /// "noch ~1.480 kcal · 1,2 / 2,0 l · 6.412 Schritte" for the head of "Planen": what is left of today's budget, from the same
    /// figures as the head of "Erfassen". `nil` when switched off or nothing recorded today (entries of other apps count as
    /// recorded). Steps appear only when known for today.
    var planHeaderLine: String? {
        guard settings.showsIntakeInPlan else { return nil }
        let figures = todayFigures
        return IntakeFormat.planHeaderLine(budget: figures.budget, waterMilliliters: figures.totals.waterMilliliters,
                                           goalWaterMilliliters: figures.plan.waterMilliliters,
                                           hasEntries: todayHasEntries || figures.totals.foreign != nil, steps: todaySteps)
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

    /// A weight: new entries offer "Widerrufen". The first one asks for the Health group "body" (a user tap started this call), after the
    /// entry is saved and shown, so the sheet of iOS never holds up the entry itself. Without a connected Health nothing is asked.
    func saveWeight(_ weight: WeightValue, isNew: Bool) async {
        if isNew {
            store.addWeight(weight)
            undo = UndoNotice(text: String(localized: "\(WeightFormat.kilograms(weight.kilograms)) erfasst"), action: .remove(weight.id))
        } else {
            store.updateWeight(weight)
        }
        refreshLocal()
        await requestBodyAccessIfDue()
        await changed()
    }

    /// The time of a new weight: now, also when another day is shown (a weighing is not back-filled like a meal).
    var weightEntryDate: Date { now() }

    /// The newest known weight for the start of a new entry: an own one or one that another app wrote in the last 90 days.
    func latestKnownKilograms() async -> Double? {
        let end = now().addingTimeInterval(86_400)
        let measurements = await weights.measurements(in: DateInterval(start: end.addingTimeInterval(-91 * 86_400), end: end))
        return measurements.last?.kilograms
    }

    /// "Gewicht aus Health" in the settings or on the trends page: asks for the group "body" once, then mirrors waiting weights.
    func allowBodyAccess() async {
        await requestBodyAccessIfDue(force: true)
        await changed()
    }

    private func requestBodyAccessIfDue(force: Bool = false) async {
        let connected = await health.access().wasAsked
        if (force || connected), await health.groupAccess(.body) == .notAsked {
            await requestingHealth("body") { try await $0.requestAuthorization(for: .body) }
        }
        bodyAccess = await health.groupAccess(.body)
        weightWriteAccess = await health.writeAccess(for: .weight)
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
        await refreshWeightOverview()
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

    /// The one consent of the Health card: a single system sheet for everything the app needs (core types, steps, active energy,
    /// weight and height). Does nothing while another Health sheet is being requested.
    func connectHealth() async {
        guard await requestingHealth("connect", { try await $0.requestAuthorization() }) else { return }
        await reload()
        await mirror.sync()
    }

    /// Runs one request of a Health sheet. Only one runs at a time: a second call while the first is open is dropped, so the two
    /// sheets of the old cards can never appear together. A failing request is logged (error domain and code, never values) and
    /// leaves the state as it was. Returns whether this call ran its request.
    @discardableResult
    private func requestingHealth(_ scope: String, _ request: (any HealthStoring) async throws -> Void) async -> Bool {
        guard !healthRequestInFlight else { return false }
        healthRequestInFlight = true
        defer { healthRequestInFlight = false }
        do {
            try await request(health)
        } catch {
            let nsError = error as NSError
            logger.error("Health request \(scope, privacy: .public) failed: \(nsError.domain, privacy: .public) \(nsError.code)")
        }
        return true
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

    /// The budget line says that the active energy is not connected; with crediting switched off (share 0) there is nothing to say.
    /// Asking happens in the Health card or in the settings, never at the budget line.
    func activeEnergyNeedsAccess(for budget: EnergyBudget) -> Bool {
        activeEnergyAccess == .notAsked && budget.creditPercent > 0
    }

    /// "Aktive Energie lesen" in the settings: the sheet for the active energy only, which leaves the other permissions alone.
    func allowActiveEnergy() async {
        guard await requestingHealth("activeEnergy", { try await $0.requestAuthorization(for: .activeEnergy) }) else { return }
        await reload()
    }

    /// "Weitere Nährwerte nach Health" in the settings: asks for the write permission of fibre, sugar, saturated fat and sodium once,
    /// then mirrors the meals that carry such values again (the mirror skips types that stay denied).
    func allowFurtherNutrients() async {
        if await health.groupAccess(.moreNutrients) == .notAsked {
            await requestingHealth("moreNutrients") { try await $0.requestAuthorization(for: .moreNutrients) }
        }
        furtherNutrientsAccess = await health.groupAccess(.moreNutrients)
        await mirror.furtherNutrientsGranted()
    }

    /// The switch "Einträge anderer Apps mitzählen": switching it on asks for the read permission once; switching it off stops
    /// reading and removes foreign values from the sums at once. The sums follow with the reload.
    func setCountsForeignNutrition(_ enabled: Bool) async {
        settings.countsForeignNutrition = enabled
        if enabled, await health.groupAccess(.foreignNutrition) == .notAsked {
            await requestingHealth("foreignNutrition") { try await $0.requestAuthorization(for: .foreignNutrition) }
        }
        await reload()
    }

    /// "Größe in Health" in the settings: asks for the write permission of the height once.
    func allowHeightWriting() async {
        if await health.groupAccess(.height) == .notAsked {
            await requestingHealth("height") { try await $0.requestAuthorization(for: .height) }
        }
        heightWriteAccess = await health.writeAccess(for: .height)
    }

    func connectSteps() async {
        guard await requestingHealth("steps", { try await $0.requestStepsAuthorization() }) else { return }
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
