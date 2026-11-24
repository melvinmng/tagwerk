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
}
