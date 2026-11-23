import Foundation
import Testing
@testable import TagwerkCore

struct TrendRulesTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private let today = PlanDay(year: 2026, month: 11, day: 21)

    private func figure(_ offset: Int, kcal: Double?, budget: Double? = nil, protein: Double? = nil, water: Int? = nil) -> (PlanDay, DayFigure) {
        let day = today.adding(days: offset, calendar: calendar)
        return (day, DayFigure(day: day, eatenKcal: kcal, budgetKcal: budget, proteinGrams: protein, waterMilliliters: water))
    }

    @Test func trendModel_week_month_year_buckets() {
        let week = TrendRules.ranges(.week, today: today, calendar: calendar)
        #expect(week.count == 7 && week.first?.lowerBound == PlanDay(year: 2026, month: 11, day: 15) && week.last?.upperBound == today)
        let month = TrendRules.ranges(.month, today: today, calendar: calendar)
        #expect(month.count == 30 && month.first?.lowerBound == PlanDay(year: 2026, month: 10, day: 23))
        let year = TrendRules.ranges(.year, today: today, calendar: calendar)
        #expect(year.count == 12)
        #expect(year.first == PlanDay(year: 2025, month: 12, day: 1)...PlanDay(year: 2025, month: 12, day: 31))
        #expect(year.last == PlanDay(year: 2026, month: 11, day: 1)...today, "the running month ends today")
        #expect(TrendRules.span(.year, today: today, calendar: calendar) == PlanDay(year: 2025, month: 12, day: 1)...today)
    }

    @Test func buckets_meanOverDaysWithEntries_gapsStayEmpty() {
        let days = Dictionary(uniqueKeysWithValues: [figure(0, kcal: 2000, budget: 2400), figure(-1, kcal: 2400, budget: 2600),
                                                     figure(-2, kcal: nil, water: 1500)])
        let buckets = TrendRules.buckets(.week, days: days, today: today, calendar: calendar)
        #expect(buckets.count == 7)
        #expect(buckets.last?.eatenKcal == 2000)
        #expect(buckets[5].eatenKcal == 2400 && buckets[5].budgetKcal == 2600)
        #expect(buckets[4].eatenKcal == nil && buckets[4].waterMilliliters == 1500 && buckets[4].daysWithEntries == 0)
        #expect(buckets[0].eatenKcal == nil, "a day without entries is a gap, not a zero")
    }

    @Test func buckets_year_averagePerDayNotPerBucket() {
        var days: [PlanDay: DayFigure] = [:]
        for (offset, kcal) in [(0, 2000.0), (-1, 2200.0), (-2, 2400.0)] {
            let item = figure(offset, kcal: kcal, budget: 2300)
            days[item.0] = item.1
        }
        let november = TrendRules.buckets(.year, days: days, today: today, calendar: calendar).last
        #expect(november?.eatenKcal == 2200)
        #expect(november?.daysWithEntries == 3)
        #expect(november?.isOverBudget == false)
    }

    @Test func isOverBudget_comparesTheMeans() {
        let bucket = TrendBucket(first: today, last: today, eatenKcal: 2500, budgetKcal: 2400, daysWithEntries: 1)
        #expect(bucket.isOverBudget)
        #expect(!TrendBucket(first: today, last: today, daysWithEntries: 0).isOverBudget)
    }

    @Test func goalLine_stepsAtPlanChange() {
        let first = GoalPlan(validFrom: PlanDay(year: 2026, month: 9, day: 1), kcal: 2300, waterMilliliters: 2000, stepsPerDay: 8000,
                             workoutMinutesPerWeek: 150, targetWeightKg: 80)
        let second = GoalPlan(validFrom: PlanDay(year: 2026, month: 11, day: 1), kcal: 2300, waterMilliliters: 2000, stepsPerDay: 8000,
                              workoutMinutesPerWeek: 150, targetWeightKg: 78)
        let span = PlanDay(year: 2026, month: 10, day: 20)...today
        let segments = TrendRules.targetSegments(timeline: GoalTimeline(plans: [first, second]), span: span, calendar: calendar)
        #expect(segments == [TargetSegment(first: PlanDay(year: 2026, month: 10, day: 20), last: PlanDay(year: 2026, month: 10, day: 31), kilograms: 80),
                             TargetSegment(first: PlanDay(year: 2026, month: 11, day: 1), last: today, kilograms: 78)])
    }

    @Test func goalLine_planWithoutTarget_leavesAGap_andNoPlanNoLine() {
        let withTarget = GoalPlan(validFrom: PlanDay(year: 2026, month: 9, day: 1), kcal: 2300, waterMilliliters: 2000, stepsPerDay: 8000,
                                  workoutMinutesPerWeek: 150, targetWeightKg: 80)
        let without = GoalPlan(validFrom: PlanDay(year: 2026, month: 11, day: 10), kcal: 2300, waterMilliliters: 2000, stepsPerDay: 8000,
                               workoutMinutesPerWeek: 150)
        let span = PlanDay(year: 2026, month: 11, day: 5)...today
        let segments = TrendRules.targetSegments(timeline: GoalTimeline(plans: [withTarget, without]), span: span, calendar: calendar)
        #expect(segments == [TargetSegment(first: PlanDay(year: 2026, month: 11, day: 5), last: PlanDay(year: 2026, month: 11, day: 9), kilograms: 80)])
        #expect(TrendRules.targetSegments(timeline: GoalTimeline(plans: []), span: span, calendar: calendar).isEmpty)
    }

    @Test func weightSpan_endsTodayAndCoversThePeriod() {
        #expect(TrendRules.weightSpan(.week, today: today, calendar: calendar).lowerBound == PlanDay(year: 2026, month: 11, day: 15))
        #expect(TrendRules.weightSpan(.threeMonths, today: today, calendar: calendar).lowerBound == PlanDay(year: 2026, month: 8, day: 23))
        #expect(TrendRules.weightSpan(.year, today: today, calendar: calendar).upperBound == today)
    }

    @Test func chart_accessibilitySummary() {
        let days = Dictionary(uniqueKeysWithValues: [figure(0, kcal: 2000, budget: 2400), figure(-1, kcal: 2400, budget: 2600)])
        let buckets = TrendRules.buckets(.week, days: days, today: today, calendar: calendar)
        let de = Locale(identifier: "de_DE")
        #expect(TrendText.intakeSummary(buckets, locale: de) == "Tagesmittel etwa 2.200 Kilokalorien, Budget 2.500. Einträge an 2 Tagen.")
        #expect(TrendText.intakeSummary([], locale: de) == "Keine Einträge in diesem Zeitraum.")
        let summary = WeightTrend.Summary(mean: 81.9, trendPerWeek: -0.3)
        #expect(TrendText.weightSummary(measurements: 12, summary: summary, locale: de)
                == "12 Messungen. 7-Tage-Mittel 81,9 kg. Trend \u{2212}0,3 kg/Woche.")
        #expect(TrendText.weightSummary(measurements: 0, summary: WeightTrend.Summary(), locale: de) == "Keine Messungen in diesem Zeitraum.")
    }
}
