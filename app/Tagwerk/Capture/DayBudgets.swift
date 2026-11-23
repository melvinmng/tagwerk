import Foundation
import HealthBridge
import TagwerkCore

/// What a day counts: the plan that held on it, the Health values kept for it and the budget that follows from both.
struct DayFigures: Hashable {
    var day: PlanDay
    var plan: GoalPlan
    /// The stored Health values of the day (active energy, other apps' nutrition); `nil` while there are none.
    var health: DayHealth?
    var active: ActiveEnergy
    /// Own entries plus, when switched on, the day totals of other apps.
    var totals: IntakeTotals
    var budget: EnergyBudget
}

/// The one place that turns a day's entries, goal plan and Health values into a budget. The head of "Erfassen", the head of
/// "Planen", the widget and the weekly review all ask here, so one day shows one number everywhere.
///
/// Health values are read into `DayHealthStore` (`refreshHealth`) and always taken from there: a past day keeps its last known
/// values when Health answers differently later or not at all, and a background run needs no Health query.
@MainActor
final class DayBudgets {
    private let intake: IntakeStore
    private let goals: GoalStore?
    private let dayHealth: DayHealthStore?
    private let health: any HealthStoring
    private let settings: AppSettings
    private let calendar: Calendar
    private let now: () -> Date
    /// Whether the calories of a workout may be written to Health now; only decides workouts mirrored before that was recorded.
    private var mayWriteEnergy = true

    init(intake: IntakeStore, goals: GoalStore?, dayHealth: DayHealthStore?, health: any HealthStoring, settings: AppSettings,
         calendar: Calendar, now: @escaping () -> Date) {
        self.intake = intake
        self.goals = goals
        self.dayHealth = dayHealth
        self.health = health
        self.settings = settings
        self.calendar = calendar
        self.now = now
    }

    var today: PlanDay { PlanDay(date: now(), calendar: calendar) }

    /// The goal plan that holds on `day`. Without a store (or without a plan) the single goals of the settings stand in.
    func plan(on day: PlanDay) -> GoalPlan {
        if let plan = goals?.current(on: day) { return plan }
        var fallback = GoalPlan.migrated(validFrom: day, kcal: settings.goalKilocalories, waterMilliliters: settings.goalWaterMilliliters,
                                         proteinGoalEnabled: settings.proteinGoalEnabled, proteinGrams: settings.goalProteinGrams,
                                         stepsPerDay: settings.goalStepsPerDay, workoutMinutesPerWeek: settings.goalWorkoutMinutesPerWeek)
        // A fixed identity, so two reads of the same day give equal figures.
        fallback.id = Self.fallbackPlanID
        return fallback
    }

    private static let fallbackPlanID = UUID(uuidString: "00000000-0000-0000-0000-00000000F0A1")!

    /// The figures of `day` for its own entries `own`. Today uses the current credit share; a past day the share that was set when
    /// its Health values were stored.
    func figures(on day: PlanDay, own: DayIntake) -> DayFigures {
        let plan = plan(on: day)
        let stored = dayHealth?.value(on: day)
        let creditPercent = day == today ? settings.activityCreditPercent : (stored?.creditPercent ?? settings.activityCreditPercent)
        let workouts = intake.ownWorkoutEnergy(on: day, calendar: calendar, mayWriteEnergy: mayWriteEnergy)
        let active = ActiveEnergy.make(healthKcal: stored?.activeKcal, ownWorkouts: workouts)
        let totals = IntakeTotals.make(own: own, foreign: stored?.foreign, countsForeign: settings.countsForeignNutrition)
        let budget = EnergyBudget.make(plan: plan, active: active, creditPercent: creditPercent, eatenKcal: totals.kcal,
                                       eatenIsEstimated: totals.hasEstimate)
        return DayFigures(day: day, plan: plan, health: stored, active: active, totals: totals, budget: budget)
    }

    /// The days of `span` for which Health values are stored (active energy or other apps' nutrition); the trends page computes only
    /// days that hold something.
    func storedDays(in span: ClosedRange<PlanDay>) -> [PlanDay] {
        (dayHealth?.values(from: span.lowerBound, to: span.upperBound) ?? []).map(\.day)
    }

    /// The figures of `day` from the entries in the store.
    func figures(on day: PlanDay) -> DayFigures {
        figures(on: day, own: IntakeRules.dayIntake(meals: intake.meals(on: day, calendar: calendar),
                                                    drinks: intake.drinks(on: day, calendar: calendar)))
    }

    /// Reads the day sums of the active energy and, when switched on, of other apps' nutrition for the days of `interval` and
    /// stores them. Each read happens only when its permission group was asked; a read that throws (Health is locked) changes
    /// nothing, and a day without a value never erases one that was known. Errors are not logged: they could carry health data.
    func refreshHealth(in interval: DateInterval) async {
        mayWriteEnergy = await health.access().allowsWriting(.activeEnergy)
        guard let dayHealth else { return }
        var energy: [PlanDay: Double]?
        if await health.groupAccess(.activeEnergy) == .asked,
           let sums = try? await health.dailyActiveEnergy(in: interval, calendar: calendar) {
            energy = Dictionary(sums.map { (PlanDay(date: $0.start, calendar: calendar), $0.kilocalories) }) { first, _ in first }
        }
        var foreign: [PlanDay: ForeignIntake]?
        if settings.countsForeignNutrition, await health.groupAccess(.foreignNutrition) == .asked,
           let sums = try? await health.dailyForeignNutrition(in: interval, calendar: calendar) {
            foreign = Dictionary(sums.map { (PlanDay(date: $0.start, calendar: calendar), $0.intake) }) { first, _ in first }
        }
        guard energy != nil || foreign != nil else { return }
        let today = self.today
        var day = PlanDay(date: interval.start, calendar: calendar)
        while day.startDate(in: calendar) < interval.end, day <= today {
            defer { day = day.adding(days: 1, calendar: calendar) }
            let stored = dayHealth.value(on: day)
            let activeKcal = energy.map { $0[day] } ?? stored?.activeKcal
            let foreignValue = foreign.map { $0[day] ?? ForeignIntake() } ?? stored?.foreign ?? ForeignIntake()
            if stored == nil, activeKcal == nil, !foreignValue.hasValues { continue }
            dayHealth.record(DayHealth(day: day, activeKcal: activeKcal, creditPercent: settings.activityCreditPercent,
                                       foreign: foreignValue), isToday: day == today)
        }
    }
}
