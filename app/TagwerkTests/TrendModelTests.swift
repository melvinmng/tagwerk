import Foundation
import HealthBridge
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The trends page: intake charts from the stored figures of each day and the weight with its mean, trend and goal line.
@MainActor
struct TrendModelTests {
    let container: ModelContainer
    let intake: IntakeStore
    let goals: GoalStore
    let dayHealth: DayHealthStore
    let settings: AppSettings
    let calendar = Calendar.tagwerk
    let today = PlanDay(year: 2026, month: 11, day: 18)
    var noon: Date { today.startDate(in: calendar).addingTimeInterval(12 * 3600 + 40 * 60) }

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        let noon = PlanDay(year: 2026, month: 11, day: 18).startDate(in: .tagwerk).addingTimeInterval(12 * 3600 + 40 * 60)
        settings = try AppSettings.current(in: container.mainContext)
        settings.activityCreditPercent = 100
        intake = IntakeStore(context: container.mainContext)
        goals = GoalStore(context: container.mainContext, settings: settings, calendar: .tagwerk, now: { noon })
        dayHealth = DayHealthStore(context: container.mainContext, now: { noon })
        goals.adopt(GoalPlan(validFrom: PlanDay(year: 2026, month: 1, day: 1), kcal: 2300, proteinGrams: 140, fiberGrams: 30,
                             waterMilliliters: 2000, stepsPerDay: 8000, workoutMinutesPerWeek: 150, targetWeightKg: 80))
    }

    private func makeModel(_ health: FakeHealthStore = FakeHealthStore()) -> TrendModel {
        let noon = self.noon
        let budgets = DayBudgets(intake: intake, goals: goals, dayHealth: dayHealth, health: health, settings: settings,
                                 calendar: calendar, now: { noon })
        let mirror = HealthMirror(store: intake, health: health, now: { noon })
        let capture = CaptureModel(store: intake, mirror: mirror, health: health, settings: settings, budgets: budgets,
                                   calendar: calendar, now: { noon }, waitsForHealth: true)
        return TrendModel(store: intake, capture: capture, goals: goals)
    }

    private func day(_ offset: Int) -> PlanDay { today.adding(days: offset, calendar: calendar) }

    private func addMeal(_ offset: Int, kcal: Double, protein: Double = 20) {
        let date = day(offset).startDate(in: calendar).addingTimeInterval(12 * 3600)
        intake.addMeal(MealValue(id: UUID(), date: date, kind: .lunch, title: "Essen",
                                 items: [MealItem(name: "Essen", amount: "1", kcalMin: kcal, kcal: kcal, kcalMax: kcal, protein: protein,
                                                  carbs: 50, fat: 10, isEstimated: false)], origin: .manual), estimatedAt: nil)
    }

    private func addWeight(_ offset: Int, _ kg: Double, hour: Int = 7) {
        let date = day(offset).startDate(in: calendar).addingTimeInterval(TimeInterval(hour * 3600))
        intake.addWeight(WeightValue(id: UUID(), date: date, kilograms: kg))
    }

    // MARK: Intake

    @Test func buckets_week_month_year() async {
        addMeal(0, kcal: 2000)
        addMeal(-1, kcal: 2400)
        addMeal(-20, kcal: 1800)
        addMeal(-100, kcal: 2200)
        let model = makeModel()
        await model.reload()
        #expect(model.buckets.count == 7)
        #expect(model.buckets.compactMap(\.eatenKcal) == [2400, 2000])
        await model.select(.month)
        #expect(model.buckets.count == 30)
        #expect(model.buckets.compactMap(\.eatenKcal) == [1800, 2400, 2000])
        await model.select(.year)
        #expect(model.buckets.count == 12)
        #expect(model.buckets.last?.daysWithEntries == 2, "the running month holds today and yesterday")
        #expect(model.buckets.compactMap(\.eatenKcal).count == 3, "August, October and November hold meals")
    }

    @Test func intakeChart_usesStoredDayHealth() async {
        // Yesterday's active energy and a foreign meal are stored; Health itself answers nothing now.
        settings.countsForeignNutrition = true
        dayHealth.record(DayHealth(day: day(-1), activeKcal: 400, creditPercent: 100,
                                   foreign: ForeignIntake(kcal: 600, protein: 30, sources: ["Yazio"])), isToday: false)
        addMeal(-1, kcal: 1500)
        let model = makeModel()
        await model.reload()
        let yesterday = model.buckets[5]
        #expect(yesterday.eatenKcal == 2100, "own meal plus the stored foreign total")
        #expect(yesterday.budgetKcal == 2700, "base goal plus the stored active energy at the share of that day")
        #expect(model.buckets.last?.eatenKcal == nil, "today holds nothing")
    }

    @Test func foreignOnlyDay_countsOnlyWhenSwitchedOn() async {
        dayHealth.record(DayHealth(day: day(-2), activeKcal: nil, creditPercent: 50, foreign: ForeignIntake(kcal: 800)), isToday: false)
        settings.countsForeignNutrition = false
        let off = makeModel()
        await off.reload()
        #expect(off.buckets.compactMap(\.eatenKcal).isEmpty)
        settings.countsForeignNutrition = true
        let on = makeModel()
        await on.reload()
        #expect(on.buckets.compactMap(\.eatenKcal) == [800])
    }

    @Test func means_goalsAndSummary() async {
        addMeal(0, kcal: 2000, protein: 100)
        addMeal(-1, kcal: 2400, protein: 120)
        let model = makeModel()
        await model.reload()
        #expect(model.means.protein == 110)
        #expect(model.plan.proteinGrams == 140)
        #expect(model.intakeMean?.eaten == 2200)
        #expect(model.intakeSummary.contains("2.200"))
    }

    // MARK: Weight

    @Test func weight_meanTrendAndGoalLine() async {
        for (offset, kg) in [(0, 80.0), (-1, 81.0), (-2, 82.0), (-28, 82.0), (-29, 83.0), (-30, 84.0)] { addWeight(offset, kg) }
        let model = makeModel()
        await model.reload()
        #expect(model.summary.mean == 81)
        #expect(model.summary.trendPerWeek == -0.5)
        #expect(model.summary.remainingToTarget == -1, "one kilogram above the target of 80")
        #expect(model.targetSegments.count == 1 && model.targetSegments.first?.kilograms == 80)
        #expect(model.meanLine.last?.kilograms == 81)
        #expect(model.paceLimit == nil)
    }

    @Test func weight_foreignMeasurementsComeInWithTheirSource() async {
        let health = FakeHealthStore()
        health.setGroupAccess(.asked, for: .body)
        health.foreignWeights = [ForeignWeight(id: UUID(), date: day(-1).startDate(in: calendar).addingTimeInterval(7 * 3600), kilograms: 83.2,
                                               sourceName: "Waage", bodyFatPercent: 24)]
        addWeight(0, 82.5)
        let model = makeModel(health)
        await model.reload()
        #expect(model.measurementList.map(\.kilograms) == [82.5, 83.2], "newest first")
        #expect(model.measurementList.last?.sourceName == "Waage")
        #expect(!model.offersBodyAccess)
    }

    @Test func weight_offersTheBodyAccessUntilItWasAsked() async {
        let model = makeModel()
        await model.capture.reload()
        #expect(model.offersBodyAccess)
        await model.capture.allowBodyAccess()
        #expect(!model.offersBodyAccess)
    }

    @Test func weight_periodChangesTheVisibleMeasurements() async {
        addWeight(0, 80)
        addWeight(-20, 82)
        addWeight(-200, 90)
        let model = makeModel()
        await model.reload()
        model.selectWeightPeriod(.week)
        #expect(model.visibleMeasurements.map(\.kilograms) == [80])
        model.selectWeightPeriod(.threeMonths)
        #expect(model.visibleMeasurements.map(\.kilograms) == [82, 80])
        model.selectWeightPeriod(.year)
        #expect(model.visibleMeasurements.map(\.kilograms) == [90, 82, 80])
    }

    @Test func weight_fastLoss_showsTheHintWithTheLimitOfTheApp() async {
        // Mean 80 now, 84 four weeks earlier: one kilogram per week, above 1 % of 80 kg.
        for (offset, kg) in [(0, 80.0), (-1, 80.0), (-2, 80.0), (-28, 84.0), (-29, 84.0), (-30, 84.0)] { addWeight(offset, kg) }
        let model = makeModel()
        await model.reload()
        let pace = model.paceLimit
        #expect(pace?.trend == -1.0)
        #expect(abs((pace?.limit ?? 0) - 0.8) < 1e-9)
    }

    @Test func deletingAnOwnWeight_removesItFromTheList_andUndoBringsItBack() async {
        addWeight(0, 80)
        let model = makeModel()
        await model.reload()
        let id = model.measurementList.first!.id
        await model.capture.delete(id)
        await model.reload()
        #expect(model.measurementList.isEmpty)
        await model.capture.undoLast()
        await model.reload()
        #expect(model.measurementList.map(\.id) == [id])
    }
}
