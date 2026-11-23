import Foundation
import HealthBridge
import Observation
import TagwerkCore

/// State of the trends page ("Verlauf und Ziele", decisions OR1a and KG3a): intake charts per period and the weight with its 7-day
/// mean, goal line and figures.
///
/// The intake charts read the same figures as the head of "Erfassen" (`DayBudgets`), so a day shows one number everywhere, and past
/// days keep the Health values stored for them. Local data shows first; Health is read afterwards and the charts follow.
@MainActor
@Observable
final class TrendModel {
    let capture: CaptureModel
    private let store: IntakeStore
    private let goals: GoalStore?

    var period: TrendPeriod = .week
    var weightPeriod: WeightPeriod = .threeMonths

    /// The bars of the selected period.
    private(set) var buckets: [TrendBucket] = []
    /// The plan of today: the goals the means are compared with.
    private(set) var plan: GoalPlan
    /// Every measurement read, own and foreign, oldest first.
    private(set) var measurements: [WeightMeasurement] = []
    private(set) var summary = WeightTrend.Summary()
    /// The 7-day mean over the selected weight period.
    private(set) var meanLine: [(day: PlanDay, kilograms: Double)] = []
    private(set) var targetSegments: [TargetSegment] = []
    @ObservationIgnored private var requestID = 0

    init(store: IntakeStore, capture: CaptureModel, goals: GoalStore?) {
        self.store = store
        self.capture = capture
        self.goals = goals
        self.plan = capture.budgets.plan(on: capture.today)
    }

    var calendar: Calendar { capture.calendar }
    var today: PlanDay { capture.today }
    var settings: AppSettings { capture.settings }

    // MARK: Loading

    func reload() async {
        requestID += 1
        let request = requestID
        loadIntake()
        loadWeight(await capture.weights.measurements(in: weightInterval))
        // Health values reach the store now; the charts follow with the days that were empty before.
        guard let span = TrendRules.span(period, today: today, calendar: calendar) else { return }
        await capture.budgets.refreshHealth(in: DateInterval(start: span.lowerBound.startDate(in: calendar), end: tomorrowStart))
        guard request == requestID else { return }
        loadIntake()
    }

    /// A new period needs no Health read for the weight, and the intake from the store comes at once.
    func select(_ period: TrendPeriod) async {
        self.period = period
        await reload()
    }

    func selectWeightPeriod(_ period: WeightPeriod) {
        weightPeriod = period
        rebuildWeight()
    }

    private var tomorrowStart: Date { today.adding(days: 1, calendar: calendar).startDate(in: calendar) }

    /// From a year back, or from the first own entry when that is older, to the end of today; the trend needs the days before
    /// the span as well.
    private var weightInterval: DateInterval {
        let yearBack = today.adding(days: -(365 + WeightTrend.trendSpanDays + WeightTrend.averageDays), calendar: calendar)
        let start = min(yearBack, capture.weights.earliestOwnDay ?? yearBack)
        return DateInterval(start: start.startDate(in: calendar), end: tomorrowStart)
    }

    private func loadIntake() {
        guard let span = TrendRules.span(period, today: today, calendar: calendar) else { return }
        let interval = DateInterval(start: span.lowerBound.startDate(in: calendar), end: tomorrowStart)
        let calendar = self.calendar
        let meals = Dictionary(grouping: store.meals(in: interval)) { PlanDay(date: $0.date, calendar: calendar) }
        let drinks = Dictionary(grouping: store.drinks(in: interval)) { PlanDay(date: $0.date, calendar: calendar) }
        // Only days that hold something are computed: a year of empty days would cost a year of queries for nothing.
        let candidates = Set(meals.keys).union(drinks.keys).union(capture.budgets.storedDays(in: span))
        var figures: [PlanDay: DayFigure] = [:]
        for day in candidates where span.contains(day) && day <= today {
            let own = IntakeRules.dayIntake(meals: meals[day] ?? [], drinks: drinks[day] ?? [])
            let counted = capture.budgets.figures(on: day, own: own)
            let totals = counted.totals
            let hasFood = !(meals[day] ?? []).isEmpty || totals.foreign?.kcal != nil
            let hasWater = !(drinks[day] ?? []).isEmpty || totals.foreign?.waterMilliliters != nil
            figures[day] = DayFigure(day: day, eatenKcal: hasFood ? totals.kcal : nil,
                                     budgetKcal: hasFood ? Double(counted.budget.budget) : nil,
                                     proteinGrams: hasFood ? totals.protein : nil,
                                     fiberGrams: hasFood ? totals.nutrient(.fiber).value : nil,
                                     waterMilliliters: hasWater ? totals.waterMilliliters : nil)
        }
        buckets = TrendRules.buckets(period, days: figures, today: today, calendar: calendar)
        plan = capture.budgets.plan(on: today)
    }

    private func loadWeight(_ read: [WeightMeasurement]) {
        measurements = read
        rebuildWeight()
    }

    private func rebuildWeight() {
        plan = capture.budgets.plan(on: today)
        let days = WeightRules.dayValues(measurements, calendar: calendar)
        summary = WeightTrend.summary(days, today: today, targetKg: plan.targetWeightKg, calendar: calendar)
        let span = TrendRules.weightSpan(weightPeriod, today: today, calendar: calendar)
        meanLine = WeightTrend.averageSeries(days.mapValues(\.kilograms), from: span.lowerBound, to: span.upperBound, calendar: calendar)
        let timeline = goals.map { GoalTimeline(plans: $0.plans()) } ?? GoalTimeline(plans: [plan])
        targetSegments = TrendRules.targetSegments(timeline: timeline, span: span, calendar: calendar)
    }

    // MARK: Derived values

    /// The measurements inside the selected weight period, oldest first (the points of the chart).
    var visibleMeasurements: [WeightMeasurement] {
        let span = TrendRules.weightSpan(weightPeriod, today: today, calendar: calendar)
        return measurements.filter { span.contains(PlanDay(date: $0.date, calendar: calendar)) }
    }

    /// The list under the chart: the visible measurements, newest first.
    var measurementList: [WeightMeasurement] { visibleMeasurements.reversed() }

    var showsBodyFat: Bool { settings.bodyFatEnabled && visibleMeasurements.contains { $0.bodyFatPercent != nil } }

    /// Means over the days of the selected period that have a value, for the cards next to the goals.
    var means: (protein: Double?, fiber: Double?, water: Double?) {
        func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        return (mean(buckets.compactMap(\.proteinGrams)), mean(buckets.compactMap(\.fiberGrams)), mean(buckets.compactMap(\.waterMilliliters)))
    }

    /// Mean eaten energy and mean budget over the days with entries (weighted by the days of each bar).
    var intakeMean: (eaten: Double, budget: Double)? {
        let days = buckets.reduce(0) { $0 + $1.daysWithEntries }
        guard days > 0 else { return nil }
        let eaten = buckets.reduce(0.0) { $0 + ($1.eatenKcal ?? 0) * Double($1.daysWithEntries) } / Double(days)
        let budget = buckets.reduce(0.0) { $0 + ($1.budgetKcal ?? 0) * Double($1.daysWithEntries) } / Double(days)
        return (eaten, budget)
    }

    /// Whether the weekly loss is above the limit of the app (the smaller of 1 % of the body weight and 1 kg); the hint is shown
    /// next to the trend and never blocks anything.
    var paceLimit: (trend: Double, limit: Double)? {
        guard let trend = summary.trendPerWeek, let mean = summary.mean,
              GoalGuardConstants.exceedsWeeklyLossLimit(trendPerWeek: trend, bodyWeightKg: mean) else { return nil }
        return (trend, GoalGuardConstants.weeklyLossLimit(bodyWeightKg: mean))
    }

    var intakeSummary: String { TrendText.intakeSummary(buckets) }
    var weightSummary: String { TrendText.weightSummary(measurements: visibleMeasurements.count, summary: summary) }

    /// Whether the measurements of other apps are readable at all: the group was not asked, so Tagwerk offers to ask.
    var offersBodyAccess: Bool { capture.healthConnected && capture.bodyAccess == .notAsked }
}
