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
@MainActor
@Observable
final class HabitsModel {
    struct Row: Identifiable, Equatable {
        var id: UUID { habit.id }
        let habit: Habit
        let isFulfilled: Bool
        /// The source is fulfilled; the row cannot be unchecked.
        let isAutomatic: Bool
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
    let calendar: Calendar

    @ObservationIgnored private let store: HabitStore
    @ObservationIgnored private let intake: IntakeStore
    @ObservationIgnored private let health: any HealthStoring
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let now: () -> Date
    /// Last Health values and the day they were read.
    @ObservationIgnored private var healthWorkoutDays: Set<PlanDay> = []
    @ObservationIgnored private var healthSteps: [PlanDay: Int] = [:]
    @ObservationIgnored private var healthReadDay: PlanDay?

    init(store: HabitStore, intake: IntakeStore, health: any HealthStoring, settings: AppSettings,
         calendar: Calendar = .tagwerk, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.intake = intake
        self.health = health
        self.settings = settings
        self.calendar = calendar
        self.now = now
        self.day = PlanDay(date: now(), calendar: calendar)
        refreshLocal()
    }

    var today: PlanDay { PlanDay(date: now(), calendar: calendar) }

    var canAddHabit: Bool { habits.filter { $0.pausedSince == nil }.count < HabitRules.maximumActive }

    /// Automatic sources already used by another habit (paused ones included).
    func takenSources(excluding id: UUID?) -> Set<HabitSource> {
        Set(habits.filter { $0.id != id && $0.source != .manual }.map(\.source))
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
        let access = await health.access()
        if access.wasAsked, let foreign = try? await health.foreignWorkouts(in: interval) {
            workoutDays = Set(foreign.filter { Self.isCounting(start: $0.start, end: $0.end) }
                .map { PlanDay(date: $0.start, calendar: calendar) })
        }
        if await health.stepsAccess() == .asked, let sums = try? await health.dailySteps(in: interval, calendar: calendar) {
            steps = Dictionary(sums.map { (PlanDay(date: $0.start, calendar: calendar), $0.count) }) { first, _ in first }
        }
        healthWorkoutDays = workoutDays
        healthSteps = steps
        healthReadDay = today
        refreshLocal()
    }

    /// Store and settings only, no Health.
    func refreshLocal() {
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
                           goalSteps: settings.goalStepsPerDay)
        day = min(day, today)
        rows = habits.filter { HabitRules.isActive($0, on: day, today: today) }.map { habit in
            Row(habit: habit, isFulfilled: HabitRules.isFulfilled(habit, on: day, facts: facts),
                isAutomatic: HabitRules.isSourceFulfilled(habit, on: day, facts: facts))
        }
        todayCounter = HabitRules.counter(habits, today: today, facts: facts, calendar: calendar)
        revision += 1
        onChanged?()
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

    func save(_ habit: Habit) { store.save(habit); refreshLocal() }
    func delete(_ id: UUID) { store.delete(id); refreshLocal() }
    func reorder(_ ids: [UUID]) { store.reorder(ids); refreshLocal() }
    func setPaused(_ id: UUID, _ paused: Bool) { store.setPaused(id, paused, today: today, calendar: calendar); refreshLocal() }
}
