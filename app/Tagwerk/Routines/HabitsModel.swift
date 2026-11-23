import Foundation
import HealthBridge
import Observation
import TagwerkCore

/// The habits of the "Erfassen" tab and their numbers (phase 7 design §6). Facts come from the stores and, over the
/// 90-day window, from Health; everything automatic is calculated and never stored.
///
/// Health is read with at most three queries per run (foreign workouts, daily steps and, later, daylight) and only
/// when the user was asked before. A failed read keeps the values of the last read of the same day, so the counter does
/// not fall while the phone is locked.
/// Where the habit sources of the app's own routines read their days from. Each closure gets the 90-day window.
struct HabitDaySources {
    var closedDays: @MainActor (ClosedRange<PlanDay>) -> Set<PlanDay> = { _ in [] }
    var journalDays: @MainActor (ClosedRange<PlanDay>) -> Set<PlanDay> = { _ in [] }
    var bibleStudyDays: @MainActor (ClosedRange<PlanDay>) -> Set<PlanDay> = { _ in [] }
}

@MainActor
@Observable
final class HabitsModel {
    struct Row: Identifiable, Equatable {
        var id: UUID { habit.id }
        let habit: Habit
        let isFulfilled: Bool
        /// The source is fulfilled; the row cannot be unchecked.
        let isAutomatic: Bool
        let state: State

        /// What the row shows (design GW3b, GW2a). The green check always means "done"; the bolt means "an automatic source".
        enum State: Equatable {
            /// (1) A habit by hand, still open.
            case manualOpen
            /// (2) Fulfilled by its source; the check cannot be removed.
            case automaticDone
            /// (3) The source is not fulfilled yet and ticks the habit by itself. `progress` is the share of the goal (0…1) for water
            /// and steps, `nil` for sources without a measure.
            case automaticPending(progress: Double?)
            /// (4) Ticked by hand while the source is still open; the check can be removed.
            case manualDoneSourcePending
            /// A habit by hand, done.
            case manualDone
        }
    }

    /// All habits, paused ones too, by order.
    private(set) var habits: [Habit] = []
    private(set) var facts: HabitFacts = .empty
    private(set) var day: PlanDay
    /// Habits active on `day`.
    private(set) var rows: [Row] = []
    private(set) var todayCounter: HabitCounter?
    /// Bumped by every recalculation; views read it to follow changes.
    private(set) var revision = 0
    @ObservationIgnored var onChanged: (() -> Void)?
    /// Called when habits are created, changed, sorted, paused or deleted (Siri's phrase parameters follow them).
    @ObservationIgnored var onListChanged: (() -> Void)?
    let calendar: Calendar

    @ObservationIgnored private let store: HabitStore
    @ObservationIgnored private let intake: IntakeStore
    @ObservationIgnored private let health: any HealthStoring
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let daySources: HabitDaySources
    @ObservationIgnored private let now: () -> Date
    /// Last Health values and the day they were read.
    @ObservationIgnored private var healthWorkoutDays: Set<PlanDay> = []
    @ObservationIgnored private var healthSteps: [PlanDay: Int] = [:]
    @ObservationIgnored private var healthReadDay: PlanDay?
    @ObservationIgnored private var healthReadWasComplete = false

    init(store: HabitStore, intake: IntakeStore, health: any HealthStoring, settings: AppSettings,
         daySources: HabitDaySources = HabitDaySources(), calendar: Calendar = .tagwerk, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.intake = intake
        self.health = health
        self.settings = settings
        self.daySources = daySources
        self.calendar = calendar
        self.now = now
        self.day = PlanDay(date: now(), calendar: calendar)
        migrateMovementSourceIfNeeded()
        refreshLocal()
    }

    var today: PlanDay { PlanDay(date: now(), calendar: calendar) }

    /// Health was read today and every type the user allowed answered; without that, habits fed by Health cannot be
    /// calculated and a counter written now could be lower than the real one.
    var hasCurrentHealthFacts: Bool { healthReadDay == today && healthReadWasComplete }

    var canAddHabit: Bool { habits.filter { $0.pausedSince == nil }.count < HabitRules.maximumActive }

    /// The counter of rule 8 for any day inside the window (the evening sheet of yesterday after midnight).
    func counter(on day: PlanDay) -> HabitCounter? {
        HabitRules.counter(habits, today: day, facts: facts, calendar: calendar)
    }

    /// Automatic sources already used by another habit (paused ones included).
    func takenSources(excluding id: UUID?) -> Set<HabitSource> {
        Set(habits.filter { $0.id != id && $0.source != .manual }.map(\.source))
    }

    /// Once: a habit with the source "Training erfasst" whose name is the old suggestion "Bewegung" (German or English) gets the
    /// combined source "Bewegung" (workout or step goal). A habit the user renamed or gave another source stays as it is, and
    /// the switch never runs again, so a later choice of the old source is respected.
    func migrateMovementSourceIfNeeded() {
        guard !settings.movementSourceMigrated else { return }
        settings.movementSourceMigrated = true
        for var habit in store.habits() where habit.source == .workout && HabitSuggestions.isFormerMovementName(habit.name) {
            habit.source = .movement
            store.save(habit)
        }
    }

    // MARK: Loading

    /// Reloads the values; `day` nil keeps the shown day. Days after today show today.
    func reload(day: PlanDay? = nil) async {
        let today = self.today
        self.day = min(day ?? self.day, today)
        let window = HabitRules.window(today: today, calendar: calendar)
        let interval = DateInterval(start: window.lowerBound.startDate(in: calendar),
                                    end: today.adding(days: 1, calendar: calendar).startDate(in: calendar))
        let sameDay = healthReadDay == today
        var workoutDays = sameDay ? healthWorkoutDays : []
        var steps = sameDay ? healthSteps : [:]
        var complete = true
        let access = await health.access()
        if access.wasAsked {
            if let foreign = try? await health.foreignWorkouts(in: interval) {
                workoutDays = Set(foreign.filter { Self.isCounting(start: $0.start, end: $0.end) }
                    .map { PlanDay(date: $0.start, calendar: calendar) })
            } else {
                complete = false
            }
        }
        if await health.stepsAccess() == .asked {
            if let sums = try? await health.dailySteps(in: interval, calendar: calendar) {
                steps = Dictionary(sums.map { (PlanDay(date: $0.start, calendar: calendar), $0.count) }) { first, _ in first }
            } else {
                complete = false
            }
        }
        healthWorkoutDays = workoutDays
        healthSteps = steps
        healthReadDay = today
        healthReadWasComplete = complete
        refreshLocal()
    }

    /// The rows of any day from the facts already loaded: the page of a neighbour day shows them while it is dragged
    /// in, and the shown page does not wait for `show(_:)`.
    func rows(for day: PlanDay) -> [Row] {
        let today = self.today
        let day = min(day, today)
        return habits.filter { HabitRules.isActive($0, on: day, today: today) }.map { row(for: $0, on: day) }
    }

    /// The row of one habit on one day, from the facts already loaded.
    private func row(for habit: Habit, on day: PlanDay) -> Row {
        let isManuallyChecked = facts.manualChecks[habit.id]?.contains(day) == true
        let isSourceFulfilled = HabitRules.isSourceFulfilled(habit, on: day, facts: facts)
        let state: Row.State
        if habit.source == .manual {
            state = isManuallyChecked ? .manualDone : .manualOpen
        } else if isSourceFulfilled {
            state = .automaticDone
        } else if isManuallyChecked {
            state = .manualDoneSourcePending
        } else {
            state = .automaticPending(progress: HabitText.sourceProgress(habit, on: day, facts: facts))
        }
        return Row(habit: habit, isFulfilled: isManuallyChecked || isSourceFulfilled, isAutomatic: isSourceFulfilled, state: state)
    }

    /// Shows another day at once from the stores; Health is read by `reload`.
    func show(_ target: PlanDay) {
        day = min(target, today)
        refreshLocal()
    }

    /// Store and settings only, no Health. `notify: false` for callers that run inside `onChanged` handlers.
    func refreshLocal(notify: Bool = true) {
        let today = self.today
        let window = HabitRules.window(today: today, calendar: calendar)
        let interval = DateInterval(start: window.lowerBound.startDate(in: calendar),
                                    end: today.adding(days: 1, calendar: calendar).startDate(in: calendar))
        habits = store.habits()
        var water: [PlanDay: Int] = [:]
        for drink in intake.drinks(in: interval) {
            water[PlanDay(date: drink.date, calendar: calendar), default: 0] += drink.milliliters
        }
        var workoutDays = healthWorkoutDays
        for workout in intake.workouts(in: interval) where workout.minutes >= IntakeRules.minimumWorkoutMinutes {
            workoutDays.insert(PlanDay(date: workout.start, calendar: calendar))
        }
        facts = HabitFacts(manualChecks: store.checks(in: window), waterMilliliters: water, workoutDays: workoutDays,
                           steps: healthSteps, goalWaterMilliliters: settings.goalWaterMilliliters,
                           goalSteps: settings.goalStepsPerDay, closedDays: daySources.closedDays(window),
                           journalDays: daySources.journalDays(window), bibleStudyDays: daySources.bibleStudyDays(window))
        day = min(day, today)
        rows = habits.filter { HabitRules.isActive($0, on: day, today: today) }.map { row(for: $0, on: day) }
        todayCounter = HabitRules.counter(habits, today: today, facts: facts, calendar: calendar)
        revision += 1
        if notify { onChanged?() }
    }

    private static func isCounting(start: Date, end: Date) -> Bool {
        end.timeIntervalSince(start) >= TimeInterval(IntakeRules.minimumWorkoutMinutes * 60)
    }

    // MARK: Changes

    /// Sets or removes the manual check of the shown day. Automatic rows and future days stay as they are.
    func toggle(_ id: UUID) async {
        guard day <= today, let row = rows.first(where: { $0.id == id }), !row.isAutomatic else { return }
        let hasManualCheck = facts.manualChecks[id]?.contains(day) == true
        store.setCheck(id, on: day, checked: !hasManualCheck, at: now())
        refreshLocal()
    }

    /// Siri: today's manual check, also for habits with an automatic source. `false` when it was already there.
    @discardableResult
    func checkToday(_ id: UUID) async -> Bool {
        let changed = store.setCheck(id, on: today, checked: true, at: now())
        refreshLocal()
        return changed
    }

    /// Whether a habit with `source` exists and is not paused.
    func hasActiveHabit(source: HabitSource) -> Bool {
        habits.contains { $0.source == source && $0.pausedSince == nil }
    }

    /// The suggestions that no habit has yet (see `HabitSuggestions`).
    var missingSuggestions: [HabitSuggestion] { HabitSuggestions.missing(existing: habits) }

    /// Takes over the selected suggestions and returns what was done.
    @discardableResult
    func adopt(_ selected: [HabitSuggestion]) -> HabitSuggestions.Plan {
        let plan = HabitSuggestions.plan(selected: selected, existing: habits)
        for habit in HabitSuggestions.habits(for: plan, existing: habits, today: today) { store.save(habit) }
        changedList()
        return plan
    }

    func save(_ habit: Habit) { store.save(habit); changedList() }
    func delete(_ id: UUID) { store.delete(id); changedList() }
    func reorder(_ ids: [UUID]) { store.reorder(ids); changedList() }
    func setPaused(_ id: UUID, _ paused: Bool) {
        store.setPaused(id, paused, today: today, calendar: calendar)
        changedList()
    }

    private func changedList() {
        refreshLocal()
        onListChanged?()
    }
}
