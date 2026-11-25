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

    // MARK: Week figures

    /// Monday, 16 Nov 2026; the week ends on Sunday the 22nd.
    private let monday = PlanDay(year: 2026, month: 11, day: 16)
    /// A day after the shown week, so the week counts as past.
    private let afterTheWeek = PlanDay(year: 2026, month: 11, day: 25)

    /// Day values from `(offset from Monday, kg)`.
    private func weekDays(_ pairs: [(Int, Double)]) -> [PlanDay: DayWeight] {
        Dictionary(uniqueKeysWithValues: pairs.map { offset, kilograms in
            let day = monday.adding(days: offset, calendar: calendar)
            return (day, DayWeight(day: day, kilograms: kilograms))
        })
    }

    @Test func weekFigures_meanAtWeekEnd_pastWeek() {
        // The measurement of the following Tuesday (offset 8) must not move the mean of the shown week.
        let days = weekDays([(0, 80), (2, 81), (4, 82), (8, 100)])
        let figures = WeightTrend.weekFigures(days, weekStart: monday, today: afterTheWeek, targetKg: nil, calendar: calendar)
        #expect(figures.referenceDay == PlanDay(year: 2026, month: 11, day: 22))
        #expect(figures.mean == 81)
    }

    @Test func weekFigures_currentWeek_usesToday() {
        let wednesday = PlanDay(year: 2026, month: 11, day: 18)
        let days = weekDays([(0, 80), (1, 81), (2, 82), (3, 99)])
        let figures = WeightTrend.weekFigures(days, weekStart: monday, today: wednesday, targetKg: nil, calendar: calendar)
        #expect(figures.referenceDay == wednesday)
        // The value of Thursday lies after today and stays out.
        #expect(figures.mean == 81)
        #expect(figures.latest?.kilograms == 82)
    }

    @Test func weekFigures_fewerThanThreeValues_meanUnknownButLatestKnown() {
        let days = weekDays([(1, 82.4), (3, 82.0)])
        let figures = WeightTrend.weekFigures(days, weekStart: monday, today: afterTheWeek, targetKg: 78, calendar: calendar)
        #expect(figures.mean == nil)
        #expect(figures.change == nil)
        #expect(figures.remainingToTarget == nil)
        #expect(figures.latest?.kilograms == 82.0)
        #expect(figures.latest?.day == monday.adding(days: 3, calendar: calendar))
        #expect(figures.measurementCount == 2)
    }

    @Test func weekFigures_changeNeedsBothMeans() {
        let thisWeekOnly = weekDays([(0, 80), (1, 81), (2, 82)])
        let withoutPrevious = WeightTrend.weekFigures(thisWeekOnly, weekStart: monday, today: afterTheWeek, targetKg: nil, calendar: calendar)
        #expect(withoutPrevious.mean == 81)
        #expect(withoutPrevious.previousMean == nil)
        #expect(withoutPrevious.change == nil)

        // The mean of the week before (offsets -7 to -1) is 82: the change is the difference of the two means.
        let both = weekDays([(0, 80), (1, 81), (2, 82), (-7, 83), (-5, 82), (-3, 81)])
        let figures = WeightTrend.weekFigures(both, weekStart: monday, today: afterTheWeek, targetKg: nil, calendar: calendar)
        #expect(figures.previousMean == 82)
        #expect(figures.change == -1)
    }

    @Test func weekFigures_countsOnlyMeasurementsOfTheWeek() {
        // Two values of the week before, three of the shown week, one of the week after: only the three count.
        let days = weekDays([(-2, 83), (-1, 83), (0, 80), (3, 81), (6, 82), (7, 90)])
        let figures = WeightTrend.weekFigures(days, weekStart: monday, today: afterTheWeek, targetKg: nil, calendar: calendar)
        #expect(figures.measurementCount == 3)
    }

    @Test func weekFigures_currentWeek_countsUpToToday() {
        let wednesday = PlanDay(year: 2026, month: 11, day: 18)
        let days = weekDays([(0, 80), (2, 82), (4, 99)])
        let figures = WeightTrend.weekFigures(days, weekStart: monday, today: wednesday, targetKg: nil, calendar: calendar)
        #expect(figures.measurementCount == 2)
    }

    @Test func weekFigures_remainingToTarget() {
        let days = weekDays([(0, 80), (1, 81), (2, 82)])
        let above = WeightTrend.weekFigures(days, weekStart: monday, today: afterTheWeek, targetKg: 78, calendar: calendar)
        #expect(above.remainingToTarget == -3)
        let below = WeightTrend.weekFigures(days, weekStart: monday, today: afterTheWeek, targetKg: 85, calendar: calendar)
        #expect(below.remainingToTarget == 4)
        let none = WeightTrend.weekFigures(days, weekStart: monday, today: afterTheWeek, targetKg: nil, calendar: calendar)
        #expect(none.remainingToTarget == nil)
    }

    @Test func weekFigures_emptyWeek_isAllUnknown() {
        let figures = WeightTrend.weekFigures([:], weekStart: monday, today: afterTheWeek, targetKg: 78, calendar: calendar)
        #expect(figures.mean == nil)
        #expect(figures.previousMean == nil)
        #expect(figures.change == nil)
        #expect(figures.trendPerWeek == nil)
        #expect(figures.latest == nil)
        #expect(figures.remainingToTarget == nil)
        #expect(figures.measurementCount == 0)
    }

    @Test func weekFigures_trendIsTheTrendOfTheReferenceDay() {
        // Mean 81 at the end of the week, 83 four weeks earlier: -0.5 kg per week, the same figure the trends page computes.
        let days = weekDays([(0, 80), (2, 81), (4, 82), (-28, 82), (-27, 83), (-26, 84)])
        let figures = WeightTrend.weekFigures(days, weekStart: monday, today: afterTheWeek, targetKg: nil, calendar: calendar)
        #expect(figures.trendPerWeek == -0.5)
    }

    @Test func weekFigures_currentWeek_agreesWithSummaryOfToday() {
        // The weekly review and the trends page must show the same mean, trend and distance for the same day.
        let wednesday = PlanDay(year: 2026, month: 11, day: 18)
        let days = weekDays([(0, 80), (1, 81), (2, 82), (-28, 82), (-27, 83), (-26, 84)])
        let figures = WeightTrend.weekFigures(days, weekStart: monday, today: wednesday, targetKg: 78, calendar: calendar)
        let summary = WeightTrend.summary(days, today: wednesday, targetKg: 78, calendar: calendar)
        #expect(figures.mean == summary.mean)
        #expect(figures.trendPerWeek == summary.trendPerWeek)
        #expect(figures.remainingToTarget == summary.remainingToTarget)
        #expect(figures.latest == summary.latest)
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
