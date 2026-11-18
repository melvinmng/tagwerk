import Foundation
import HealthBridge
import Observation
import TagwerkCore

/// State of the "Erfassen" tab (mockup E1a): one day with totals against the goals, own entries and Health workouts.
///
/// Health is only read after the user was asked once; permission is requested only from `connectHealth()`.
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
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var deletedEntries: [UUID: IntakeStore.Deleted] = [:]

    var day: PlanDay
    private(set) var meals: [MealValue] = []
    private(set) var drinks: [DrinkValue] = []
    /// Own and Health workouts of the day, by start.
    private(set) var workouts: [WorkoutValue] = []
    private(set) var intake: DayIntake = .empty
    /// Today's sums regardless of the displayed day: plan header, widget and Siri (phase 4).
    private(set) var todayIntake: DayIntake = .empty
    private(set) var todayHasEntries = false
    /// Workouts of the Monday-to-Sunday week of `day`.
    private(set) var weekCount = 0
    /// `nil` until the first query, so the Health card does not flash when Health is connected.
    private(set) var access: HealthAccess?
    private(set) var undo: UndoNotice?
    @ObservationIgnored private var weekForeign: [WorkoutValue] = []
    /// "Today" at the last reload: a view that showed today follows to the new day after midnight.
    @ObservationIgnored private var lastToday: PlanDay
    @ObservationIgnored private var pendingSync: Task<Void, Never>?

    /// Tests wait for each Health run, so no run outlives the test's store.
    @ObservationIgnored private let waitsForHealth: Bool

    init(store: IntakeStore, mirror: HealthMirror, health: any HealthStoring, settings: AppSettings,
         calendar: Calendar = .tagwerk, now: @escaping () -> Date = Date.init, waitsForHealth: Bool = false) {
        self.waitsForHealth = waitsForHealth
        self.store = store
        self.mirror = mirror
        self.health = health
        self.settings = settings
        self.calendar = calendar
        self.now = now
        let today = PlanDay(date: now(), calendar: calendar)
        self.day = today
        self.lastToday = today
    }

    var today: PlanDay { PlanDay(date: now(), calendar: calendar) }
    var isToday: Bool { day == today }
    var canGoForward: Bool { day < today }
    var showsHealthCard: Bool { access == .notDetermined && !settings.healthCardDismissed }
    var hasEntries: Bool { !meals.isEmpty || !drinks.isEmpty || !workouts.isEmpty }

    // MARK: Loading

    /// Reloads the day; reads Health workouts only when access was asked before.
    /// `refreshingLocalFirst: false` after `show(_:)`, which already read the store for the new day.
    func reload(refreshingLocalFirst: Bool = true) async {
        let today = self.today
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
            foreignOfWeek = foreign.map { workout in
                WorkoutValue(id: workout.id.uuidString, activity: workout.activity ?? .other, start: workout.start,
                             minutes: max(0, Int(workout.end.timeIntervalSince(workout.start) / 60)),
                             kilocalories: workout.kilocalories, sourceName: workout.sourceName, isOwn: false,
                             customName: workout.activity == nil ? workout.activityName : nil)
            }
        }
        // A later navigation already moved on; its own reload applies its week.
        guard day == requestedDay else { return }
        weekForeign = foreignOfWeek
        refreshLocal(week: week)
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
        weekCount = IntakeRules.workoutsThisWeek(weekWorkouts, now: dayStart, calendar: calendar)
        intake = IntakeRules.dayIntake(meals: meals, drinks: drinks)
        refreshToday()
    }

    /// Recomputes today's sums; every local change passes here (add, edit, delete, undo).
    private func refreshToday() {
        let today = self.today
        let todayMeals = day == today ? meals : store.meals(on: today, calendar: calendar)
        let todayDrinks = day == today ? drinks : store.drinks(on: today, calendar: calendar)
        todayIntake = IntakeRules.dayIntake(meals: todayMeals, drinks: todayDrinks)
        todayHasEntries = !todayMeals.isEmpty || !todayDrinks.isEmpty
        onTodayChanged?()
    }

    /// Called after today's sums changed; the environment rewrites the widget snapshot.
    @ObservationIgnored var onTodayChanged: (() -> Void)?

    /// "~1.240 / 2.300 kcal · 1,2 / 2,0 l" for the head of "Planen"; `nil` when switched off or nothing recorded today.
    var planHeaderLine: String? {
        guard settings.showsIntakeInPlan else { return nil }
        return IntakeFormat.planHeaderLine(intake: todayIntake, goalKcal: settings.goalKilocalories,
                                           goalWaterMilliliters: settings.goalWaterMilliliters, hasEntries: todayHasEntries)
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
