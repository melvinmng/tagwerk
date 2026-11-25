import Foundation

/// The 7-day mean, the trend and the linear projection of the body weight (decision KG3a). Pure functions of the day values, so the
/// trends page, the weekly review and the data package of the goal planning ask the same place.
public enum WeightTrend {
    /// A mean covers the day and the six days before it.
    public static let averageDays = 7
    /// A mean needs at least this many day values inside its window; fewer is "unknown", never a guess.
    public static let minimumValuesForAverage = 3
    /// The trend compares the mean of a day with the mean of the day this many days earlier.
    public static let trendSpanDays = 28
    /// A projection further away than this is not shown: a straight line over years says nothing.
    public static let maximumProjectionDays = 730

    /// The mean of the day values of the seven days up to and including `day`; days without a measurement are skipped (a gap does not
    /// break the mean). `nil` with fewer than three values.
    public static func movingAverage(_ values: [PlanDay: Double], on day: PlanDay, calendar: Calendar) -> Double? {
        var sum = 0.0
        var count = 0
        for offset in 0..<averageDays {
            if let value = values[day.adding(days: -offset, calendar: calendar)] {
                sum += value
                count += 1
            }
        }
        return count >= minimumValuesForAverage ? sum / Double(count) : nil
    }

    /// Kilograms per week: the 7-day mean of `day` minus the 7-day mean 28 days earlier, divided by the four weeks between them.
    /// `nil` when one of the two means is unknown.
    public static func trendPerWeek(_ values: [PlanDay: Double], on day: PlanDay, calendar: Calendar) -> Double? {
        guard let now = movingAverage(values, on: day, calendar: calendar),
              let before = movingAverage(values, on: day.adding(days: -trendSpanDays, calendar: calendar), calendar: calendar)
        else { return nil }
        return (now - before) / Double(trendSpanDays / 7)
    }

    /// The 7-day mean for every day from `first` to `last` that has one (days without a mean are left out of the line).
    public static func averageSeries(_ values: [PlanDay: Double], from first: PlanDay, to last: PlanDay,
                                     calendar: Calendar) -> [(day: PlanDay, kilograms: Double)] {
        var result: [(PlanDay, Double)] = []
        var day = first
        while day <= last {
            if let mean = movingAverage(values, on: day, calendar: calendar) { result.append((day, mean)) }
            day = day.adding(days: 1, calendar: calendar)
        }
        return result
    }

    /// A straight-line projection of when the target weight is reached at the current trend.
    public struct Projection: Sendable, Hashable {
        /// The day the line reaches the target.
        public var day: PlanDay
        public var daysAhead: Int
    }

    /// `nil` without a trend or a target, at a standstill, when the weight moves away from the target, when the target is reached
    /// already, or when the line would need more than `maximumProjectionDays`. It is an extrapolation, not a forecast.
    public static func projection(mean: Double, trendPerWeek: Double, target: Double, today: PlanDay, calendar: Calendar) -> Projection? {
        let remaining = target - mean
        guard abs(remaining) >= 0.05, trendPerWeek != 0, (remaining > 0) == (trendPerWeek > 0) else { return nil }
        let days = Int((remaining / trendPerWeek * 7).rounded(.up))
        guard days <= maximumProjectionDays else { return nil }
        return Projection(day: today.adding(days: days, calendar: calendar), daysAhead: days)
    }

    /// The figures under the weight chart, all for `today`.
    public struct Summary: Sendable, Hashable {
        /// The newest day value up to `today`; `nil` without any measurement.
        public var latest: DayWeight?
        /// The 7-day mean of `today`; `nil` with fewer than three values in the window.
        public var mean: Double?
        /// Kilograms per week over the last 28 days; `nil` without enough values.
        public var trendPerWeek: Double?
        /// The mean of today minus the first mean there is (the first day on which three values lay within seven days).
        public var sinceStart: Double?
        /// Target weight minus the mean; negative when the weight is above the target. `nil` without target or mean.
        public var remainingToTarget: Double?
        public var projection: Projection?

        public init(latest: DayWeight? = nil, mean: Double? = nil, trendPerWeek: Double? = nil, sinceStart: Double? = nil,
                    remainingToTarget: Double? = nil, projection: Projection? = nil) {
            self.latest = latest
            self.mean = mean
            self.trendPerWeek = trendPerWeek
            self.sinceStart = sinceStart
            self.remainingToTarget = remainingToTarget
            self.projection = projection
        }
    }

    public static func summary(_ days: [PlanDay: DayWeight], today: PlanDay, targetKg: Double?, calendar: Calendar) -> Summary {
        let values = days.mapValues(\.kilograms)
        let latest = days.values.filter { $0.day <= today }.max { $0.day < $1.day }
        let mean = movingAverage(values, on: today, calendar: calendar)
        let trend = trendPerWeek(values, on: today, calendar: calendar)
        var sinceStart: Double?
        if let mean, let first = days.keys.min() {
            var day = first
            while day <= today {
                if let start = movingAverage(values, on: day, calendar: calendar) {
                    sinceStart = mean - start
                    break
                }
                day = day.adding(days: 1, calendar: calendar)
            }
        }
        var remaining: Double?
        var projected: Projection?
        if let mean, let targetKg {
            remaining = targetKg - mean
            if let trend { projected = projection(mean: mean, trendPerWeek: trend, target: targetKg, today: today, calendar: calendar) }
        }
        return Summary(latest: latest, mean: mean, trendPerWeek: trend, sinceStart: sinceStart, remainingToTarget: remaining,
                       projection: projected)
    }

    /// The weight figures of one calendar week for the weekly review. Every number is taken at the reference day, the last day of
    /// the week that is not in the future, so a past week keeps its figures for as long as its measurements exist.
    public struct WeekFigures: Sendable, Hashable {
        /// The Sunday of the week, or today in the current week.
        public var referenceDay: PlanDay
        /// The newest day value up to the reference day; `nil` without any measurement.
        public var latest: DayWeight?
        /// The 7-day mean of the reference day; `nil` with fewer than three values in the window.
        public var mean: Double?
        /// The 7-day mean seven days before the reference day; `nil` with fewer than three values in that window.
        public var previousMean: Double?
        /// `mean` minus `previousMean` (negative when the weight went down); `nil` unless both means are known.
        public var change: Double?
        /// Kilograms per week over 28 days at the reference day, the figure of the trends page.
        public var trendPerWeek: Double?
        /// Days of the week (Monday up to the reference day) that have a measurement.
        public var measurementCount: Int
        /// Target weight minus `mean`; negative when the weight is above the target. `nil` without target or mean.
        public var remainingToTarget: Double?

        public init(referenceDay: PlanDay, latest: DayWeight? = nil, mean: Double? = nil, previousMean: Double? = nil,
                    change: Double? = nil, trendPerWeek: Double? = nil, measurementCount: Int = 0, remainingToTarget: Double? = nil) {
            self.referenceDay = referenceDay
            self.latest = latest
            self.mean = mean
            self.previousMean = previousMean
            self.change = change
            self.trendPerWeek = trendPerWeek
            self.measurementCount = measurementCount
            self.remainingToTarget = remainingToTarget
        }
    }

    /// The figures of the week starting on `weekStart`. Mean, trend, latest value and distance to the target come from `summary` for
    /// the reference day, so the weekly review and the trends page cannot show different numbers for the same day. The change of the
    /// week is the difference of two 7-day means (this week's against the week before), not of single measurements.
    public static func weekFigures(_ days: [PlanDay: DayWeight], weekStart: PlanDay, today: PlanDay, targetKg: Double?,
                                   calendar: Calendar) -> WeekFigures {
        let referenceDay = min(weekStart.adding(days: 6, calendar: calendar), today)
        let summary = summary(days, today: referenceDay, targetKg: targetKg, calendar: calendar)
        let values = days.mapValues(\.kilograms)
        let previousMean = movingAverage(values, on: referenceDay.adding(days: -averageDays, calendar: calendar), calendar: calendar)
        let change = summary.mean.flatMap { mean in previousMean.map { mean - $0 } }
        let count = days.keys.filter { $0 >= weekStart && $0 <= referenceDay }.count
        return WeekFigures(referenceDay: referenceDay, latest: summary.latest, mean: summary.mean, previousMean: previousMean,
                           change: change, trendPerWeek: summary.trendPerWeek, measurementCount: count,
                           remainingToTarget: summary.remainingToTarget)
    }
}
