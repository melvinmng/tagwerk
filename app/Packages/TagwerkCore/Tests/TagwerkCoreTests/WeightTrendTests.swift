import Foundation
import Testing
@testable import TagwerkCore

/// The 7-day mean, the trend and the projection, from fixed series.
struct WeightTrendTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private let today = PlanDay(year: 2026, month: 11, day: 21)

    /// Day values from `(offset from today, kg)`.
    private func values(_ pairs: [(Int, Double)]) -> [PlanDay: Double] {
        Dictionary(uniqueKeysWithValues: pairs.map { (today.adding(days: $0.0, calendar: calendar), $0.1) })
    }

    @Test func movingAverage_needsThreeValues() {
        #expect(WeightTrend.movingAverage(values([(0, 80), (-1, 81)]), on: today, calendar: calendar) == nil)
        #expect(WeightTrend.movingAverage(values([(0, 80), (-1, 81), (-2, 82)]), on: today, calendar: calendar) == 81)
    }

    @Test func movingAverage_looksSevenDaysBackAndNoFurther() {
        let series = values([(0, 80), (-3, 82), (-6, 84), (-7, 100)])
        #expect(WeightTrend.movingAverage(series, on: today, calendar: calendar) == 82)
    }

    @Test func gaps_doNotBreakAverage() {
        // Three values scattered over the window still give a mean of the values there are; no gap counts as zero.
        let series = values([(0, 80), (-3, 81), (-6, 82)])
        #expect(WeightTrend.movingAverage(series, on: today, calendar: calendar) == 81)
    }

    @Test func trend_perWeekOver28Days() {
        // The mean of today is 81 and 28 days earlier 83: minus two kilograms in four weeks, minus half a kilogram per week.
        let series = values([(0, 80), (-1, 81), (-2, 82), (-28, 82), (-29, 83), (-30, 84)])
        #expect(WeightTrend.trendPerWeek(series, on: today, calendar: calendar) == -0.5)
    }

    @Test func trend_insufficientData_isNil() {
        #expect(WeightTrend.trendPerWeek(values([(0, 80), (-1, 81), (-2, 82)]), on: today, calendar: calendar) == nil)
        #expect(WeightTrend.trendPerWeek(values([(-28, 82), (-29, 83), (-30, 84)]), on: today, calendar: calendar) == nil)
    }

    @Test func trend_spansTheClockChangeWithoutShiftingDays() {
        // 2026-10-25 is the end of daylight-saving time in Berlin: the day count stays calendar days, not 24-hour blocks.
        let sunday = PlanDay(year: 2026, month: 10, day: 26)
        let series: [PlanDay: Double] = Dictionary(uniqueKeysWithValues:
            (0..<7).map { (sunday.adding(days: -$0, calendar: calendar), 80.0) } + (28..<35).map { (sunday.adding(days: -$0, calendar: calendar), 82.0) })
        #expect(WeightTrend.trendPerWeek(series, on: sunday, calendar: calendar) == -0.5)
    }

    @Test func averageSeries_leavesOutDaysWithoutAMean() {
        let series = values([(0, 80), (-1, 81), (-2, 82)])
        let line = WeightTrend.averageSeries(series, from: today.adding(days: -4, calendar: calendar), to: today, calendar: calendar)
        // The mean exists from the day the third value lies inside the window.
        #expect(line.map(\.day) == [today.adding(days: -0, calendar: calendar)])
        #expect(line.first?.kilograms == 81)
    }

    @Test func projection_linear_nilWhenMovingAway() {
        #expect(WeightTrend.projection(mean: 82, trendPerWeek: 0.3, target: 78, today: today, calendar: calendar) == nil)
        #expect(WeightTrend.projection(mean: 74, trendPerWeek: -0.3, target: 78, today: today, calendar: calendar) == nil)
        #expect(WeightTrend.projection(mean: 82, trendPerWeek: 0, target: 78, today: today, calendar: calendar) == nil)
    }

    @Test func projection_linear_reachesTheTargetAtTheCurrentPace() {
        let projection = WeightTrend.projection(mean: 82, trendPerWeek: -0.5, target: 78, today: today, calendar: calendar)
        // Four kilograms at half a kilogram per week: eight weeks.
        #expect(projection?.daysAhead == 56)
        #expect(projection?.day == PlanDay(year: 2027, month: 1, day: 16))
    }

    @Test func projection_nilWhenReachedOrFarAway() {
        #expect(WeightTrend.projection(mean: 78.02, trendPerWeek: -0.3, target: 78, today: today, calendar: calendar) == nil)
        #expect(WeightTrend.projection(mean: 82, trendPerWeek: -0.01, target: 78, today: today, calendar: calendar) == nil)
    }

    @Test func summary_collectsTheFigures() {
        func day(_ offset: Int, _ kg: Double) -> (PlanDay, DayWeight) {
            let day = today.adding(days: offset, calendar: calendar)
            return (day, DayWeight(day: day, kilograms: kg))
        }
        let pairs = [day(0, 80), day(-1, 81), day(-2, 82), day(-28, 82), day(-29, 83), day(-30, 84)]
        let summary = WeightTrend.summary(Dictionary(uniqueKeysWithValues: pairs), today: today, targetKg: 78, calendar: calendar)
        #expect(summary.latest?.kilograms == 80)
        #expect(summary.mean == 81)
        #expect(summary.trendPerWeek == -0.5)
        #expect(summary.remainingToTarget == -3)
        #expect(summary.projection?.daysAhead == 42)
        // The first mean there is lies on the day -28 (values -28, -29, -30 inside the window): 83.
        #expect(summary.sinceStart == -2)
    }

    @Test func summary_withoutData_isEmpty() {
        let summary = WeightTrend.summary([:], today: today, targetKg: 78, calendar: calendar)
        #expect(summary == WeightTrend.Summary())
    }
}

struct GoalGuardConstantsTests {
    @Test func weeklyLossLimit_isTheSmallerOfShareAndKilogram() {
        #expect(abs(GoalGuardConstants.weeklyLossLimit(bodyWeightKg: 82) - 0.82) < 1e-9)
        #expect(GoalGuardConstants.weeklyLossLimit(bodyWeightKg: 130) == 1.0)
    }

    @Test func exceedsWeeklyLossLimit_warnsOnlyForLoss() {
        #expect(GoalGuardConstants.exceedsWeeklyLossLimit(trendPerWeek: -0.9, bodyWeightKg: 82))
        #expect(!GoalGuardConstants.exceedsWeeklyLossLimit(trendPerWeek: -0.8, bodyWeightKg: 82))
        #expect(!GoalGuardConstants.exceedsWeeklyLossLimit(trendPerWeek: 1.5, bodyWeightKg: 82))
    }
}
