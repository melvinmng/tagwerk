import Foundation
import HealthBridge
import TagwerkCore

/// Collects the data package for the goal planning (decision PV2a) from what the app holds: the days of the period with the figures that
/// every other screen shows (`DayBudgets`), the weight trend, the training time and the steps. Health is read only for the groups that
/// were asked before. The result is a draft with every group; the data sheet lets the user switch groups off, and only the frozen
/// selection goes to ChatGPT.
@MainActor
final class GoalDataBuilder {
    /// The standard period of the package: 28 days.
    static let standardDays = 28
    /// "Fortschritt besprechen" covers the time since the current goals, at most 12 weeks, at least one week.
    static let reviewDays = 7...84

    private let intake: IntakeStore
    private let budgets: DayBudgets
    private let weights: WeightStore
    private let health: any HealthStoring
    private let bodyProfile: BodyProfileStore
    private let goals: GoalStore
    private let calendar: Calendar
    private let now: () -> Date

    init(intake: IntakeStore, budgets: DayBudgets, weights: WeightStore, health: any HealthStoring, bodyProfile: BodyProfileStore,
         goals: GoalStore, calendar: Calendar, now: @escaping () -> Date) {
        self.intake = intake
        self.budgets = budgets
        self.weights = weights
        self.health = health
        self.bodyProfile = bodyProfile
        self.goals = goals
        self.calendar = calendar
        self.now = now
    }

    var today: PlanDay { PlanDay(date: now(), calendar: calendar) }

    /// The days since the plan of today began, for "Fortschritt besprechen"; the standard period when that is shorter than a week.
    func reviewPeriodDays() -> Int {
        let plan = budgets.plan(on: today)
        guard plan.validFrom < today else { return Self.standardDays }
        let days = calendar.dateComponents([.day], from: plan.validFrom.startDate(in: calendar), to: today.startDate(in: calendar)).day ?? 0
        return days < Self.reviewDays.lowerBound ? Self.standardDays : min(days, Self.reviewDays.upperBound)
    }

    /// Builds the draft: the `periodDays` days before today (today itself is not finished and would pull the means down).
    func build(periodDays: Int) async -> GoalPlanningSession {
        // The body values are read once more before the sheet; never in the background.
        await bodyProfile.refresh()
        let first = today.adding(days: -periodDays, calendar: calendar)
        let interval = DateInterval(start: first.startDate(in: calendar), end: today.startDate(in: calendar))
        await budgets.refreshHealth(in: interval)

        let meals = Dictionary(grouping: intake.meals(in: interval)) { PlanDay(date: $0.date, calendar: calendar) }
        let drinks = Dictionary(grouping: intake.drinks(in: interval)) { PlanDay(date: $0.date, calendar: calendar) }
        let steps = await dailySteps(in: interval)
        var days: [GoalDataDay] = []
        var activeByDay: [PlanDay: Double] = [:]
        var day = first
        while day < today {
            let counted = budgets.figures(on: day, own: IntakeRules.dayIntake(meals: meals[day] ?? [], drinks: drinks[day] ?? []))
            let totals = counted.totals
            let hasFood = !(meals[day] ?? []).isEmpty || totals.foreign?.kcal != nil
            let hasWater = !(drinks[day] ?? []).isEmpty || totals.foreign?.waterMilliliters != nil
            // Active energy counts as known only when Health delivered a sum; an own workout alone is no day total.
            let active = counted.active.isFromHealth ? counted.active.total : nil
            if let active { activeByDay[day] = active }
            days.append(GoalDataDay(eatenKcal: hasFood ? totals.kcal : nil, proteinGrams: hasFood ? totals.protein : nil,
                                    fiberGrams: hasFood ? totals.nutrient(.fiber).value : nil,
                                    waterMilliliters: hasWater ? Double(totals.waterMilliliters) : nil, activeKcal: active,
                                    steps: steps[day].map(Double.init)))
            day = day.adding(days: 1, calendar: calendar)
        }

        let weight = await weightFigures(periodStart: first)
        let workouts = await workoutMinutesPerWeek(in: interval, periodDays: periodDays)
        let profile = bodyProfile.profile
        let plan = goals.current(on: today)
        let package = GoalDataSummary.make(periodDays: periodDays, days: days, profile: profile, year: bodyProfile.currentYear,
                                           weight: weight, workoutMinutesPerWeek: workouts, plan: plan)
        // The mean active energy of the last 14 days for the deficit check: the days Health has a sum for, never a zero.
        let recent = activeByDay.filter { $0.key >= today.adding(days: -GoalGuardConstants.activityAverageDays, calendar: calendar) }.values
        let meanActive = recent.isEmpty ? nil : recent.reduce(0, +) / Double(recent.count)
        return GoalPlanningSession(package: package, guardInput: GoalGuardInput(body: profile.values, weightKg: weight.kilograms,
                                                                               meanActiveKcal: meanActive, year: bodyProfile.currentYear))
    }

    // MARK: Parts

    private func dailySteps(in interval: DateInterval) async -> [PlanDay: Int] {
        guard await health.stepsAccess() == .asked, let sums = try? await health.dailySteps(in: interval, calendar: calendar) else { return [:] }
        return Dictionary(sums.map { (PlanDay(date: $0.start, calendar: calendar), $0.count) }) { first, _ in first }
    }

    private func weightFigures(periodStart: PlanDay) async -> GoalDataWeight {
        let lookBack = periodStart.adding(days: -(WeightTrend.trendSpanDays + WeightTrend.averageDays), calendar: calendar)
        let readInterval = DateInterval(start: lookBack.startDate(in: calendar), end: today.adding(days: 1, calendar: calendar).startDate(in: calendar))
        let measurements = await weights.measurements(in: readInterval)
        let values = WeightRules.dayValues(measurements, calendar: calendar)
        let summary = WeightTrend.summary(values, today: today, targetKg: nil, calendar: calendar)
        let byDay = values.mapValues(\.kilograms)
        let start = WeightTrend.movingAverage(byDay, on: periodStart, calendar: calendar)
        return GoalDataWeight(kilograms: summary.mean ?? summary.latest?.kilograms, trendKgPerWeek: summary.trendPerWeek,
                              startKilograms: start)
    }

    private func workoutMinutesPerWeek(in interval: DateInterval, periodDays: Int) async -> Double? {
        var workouts = intake.workouts(in: interval)
        if await health.access().wasAsked, let foreign = try? await health.foreignWorkouts(in: interval) {
            workouts += foreign.map(CaptureModel.workoutValue)
        }
        let weeks = Double(periodDays) / 7
        guard weeks > 0 else { return nil }
        return Double(IntakeRules.workoutMinutes(workouts, in: interval)) / weeks
    }
}
