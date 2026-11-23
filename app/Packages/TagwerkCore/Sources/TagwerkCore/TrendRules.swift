import Foundation

/// The periods of the intake charts on the trends page ("Verlauf und Ziele", decision OR1a).
public enum TrendPeriod: String, Sendable, CaseIterable, Identifiable {
    case week, month, year
    public var id: String { rawValue }
}

/// The periods of the weight chart (decision KG3a); three months is in addition to the periods of the intake charts.
public enum WeightPeriod: String, Sendable, CaseIterable, Identifiable {
    case week, month, threeMonths, year
    public var id: String { rawValue }
}

/// What one day counts for the charts. A value is `nil` when the day has no entry that carries it: a day without entries is a gap in
/// the chart, never a zero.
public struct DayFigure: Sendable, Hashable {
    public var day: PlanDay
    public var eatenKcal: Double?
    /// The budget of the day, set together with `eatenKcal`.
    public var budgetKcal: Double?
    public var proteinGrams: Double?
    public var fiberGrams: Double?
    public var waterMilliliters: Int?

    public init(day: PlanDay, eatenKcal: Double? = nil, budgetKcal: Double? = nil, proteinGrams: Double? = nil,
                fiberGrams: Double? = nil, waterMilliliters: Int? = nil) {
        self.day = day
        self.eatenKcal = eatenKcal
        self.budgetKcal = budgetKcal
        self.proteinGrams = proteinGrams
        self.fiberGrams = fiberGrams
        self.waterMilliliters = waterMilliliters
    }
}

/// One bar of an intake chart: a day (week, month) or a calendar month (year). Values are means per day over the days that have one.
public struct TrendBucket: Sendable, Hashable, Identifiable {
    public var first: PlanDay
    public var last: PlanDay
    public var eatenKcal: Double?
    public var budgetKcal: Double?
    public var proteinGrams: Double?
    public var fiberGrams: Double?
    public var waterMilliliters: Double?
    /// Days with an entry that counts as eaten.
    public var daysWithEntries: Int

    public var id: PlanDay { first }
    public var isOverBudget: Bool { (eatenKcal ?? 0) > (budgetKcal ?? .infinity) }
}

/// A stretch of days on which one target weight held (the goal line of the weight chart steps at a change of the goal plan).
public struct TargetSegment: Sendable, Hashable {
    public var first: PlanDay
    public var last: PlanDay
    public var kilograms: Double
}

public enum TrendRules {
    /// The days a period covers, oldest first: the last 7 days, the last 30 days, or the months from eleven months ago up to this one.
    public static func ranges(_ period: TrendPeriod, today: PlanDay, calendar: Calendar) -> [ClosedRange<PlanDay>] {
        switch period {
        case .week:
            return (0..<7).reversed().map { let day = today.adding(days: -$0, calendar: calendar); return day...day }
        case .month:
            return (0..<30).reversed().map { let day = today.adding(days: -$0, calendar: calendar); return day...day }
        case .year:
            let thisMonth = PlanDay(year: today.year, month: today.month, day: 1)
            return (0..<12).reversed().compactMap { back in
                guard let start = calendar.date(byAdding: .month, value: -back, to: thisMonth.startDate(in: calendar)) else { return nil }
                let first = PlanDay(date: start, calendar: calendar)
                guard let next = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
                let last = min(today, PlanDay(date: next, calendar: calendar).adding(days: -1, calendar: calendar))
                return first...last
            }
        }
    }

    /// The whole span of a period, from the first to the last day.
    public static func span(_ period: TrendPeriod, today: PlanDay, calendar: Calendar) -> ClosedRange<PlanDay>? {
        let ranges = ranges(period, today: today, calendar: calendar)
        guard let first = ranges.first, let last = ranges.last else { return nil }
        return first.lowerBound...last.upperBound
    }

    /// The bars of a period. A value is the mean over the days of the bar that have it, so a day without entries does not pull the
    /// mean down; a bar without any day has no value. The budget is the mean over the same days as the eaten energy.
    public static func buckets(_ period: TrendPeriod, days: [PlanDay: DayFigure], today: PlanDay, calendar: Calendar) -> [TrendBucket] {
        ranges(period, today: today, calendar: calendar).map { range in
            var figures: [DayFigure] = []
            var day = range.lowerBound
            while day <= range.upperBound {
                if let figure = days[day] { figures.append(figure) }
                day = day.adding(days: 1, calendar: calendar)
            }
            func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
            let eaten = figures.filter { $0.eatenKcal != nil }
            return TrendBucket(first: range.lowerBound, last: range.upperBound,
                               eatenKcal: mean(eaten.compactMap(\.eatenKcal)), budgetKcal: mean(eaten.compactMap(\.budgetKcal)),
                               proteinGrams: mean(figures.compactMap(\.proteinGrams)), fiberGrams: mean(figures.compactMap(\.fiberGrams)),
                               waterMilliliters: mean(figures.compactMap { $0.waterMilliliters.map(Double.init) }),
                               daysWithEntries: eaten.count)
        }
    }

    /// The span of a weight period, ending today.
    public static func weightSpan(_ period: WeightPeriod, today: PlanDay, calendar: Calendar) -> ClosedRange<PlanDay> {
        let days: Int = switch period {
        case .week: 7
        case .month: 30
        case .threeMonths: 91
        case .year: 365
        }
        return today.adding(days: 1 - days, calendar: calendar)...today
    }

    /// The target weight on each stretch of `span`: it steps where a goal plan with another target takes over. A plan without a target
    /// leaves a gap, so no line is drawn for those days.
    public static func targetSegments(timeline: GoalTimeline, span: ClosedRange<PlanDay>, calendar: Calendar) -> [TargetSegment] {
        var segments: [TargetSegment] = []
        var day = span.lowerBound
        var open: (first: PlanDay, kilograms: Double)?
        func close(before end: PlanDay) {
            if let current = open { segments.append(TargetSegment(first: current.first, last: end, kilograms: current.kilograms)) }
            open = nil
        }
        while day <= span.upperBound {
            let target = timeline.plan(on: day)?.targetWeightKg
            if let target {
                if let current = open, current.kilograms != target {
                    close(before: day.adding(days: -1, calendar: calendar))
                }
                if open == nil { open = (day, target) }
            } else {
                close(before: day.adding(days: -1, calendar: calendar))
            }
            day = day.adding(days: 1, calendar: calendar)
        }
        close(before: span.upperBound)
        return segments
    }
}

/// The spoken summaries of the charts (VoiceOver reads these instead of single marks).
public enum TrendText {
    /// "Tagesmittel etwa 2.290 Kilokalorien, Budget 2.596. An 5 von 7 Tagen erfasst."
    public static func intakeSummary(_ buckets: [TrendBucket], locale: Locale = .current) -> String {
        let eaten = buckets.compactMap(\.eatenKcal)
        let weights = buckets.map(\.daysWithEntries)
        let days = weights.reduce(0, +)
        guard !eaten.isEmpty else { return String(localized: "Keine Einträge in diesem Zeitraum.", bundle: .module) }
        // A mean of bars weighs every day alike, so the bars are weighted with their days.
        let total = buckets.reduce(0.0) { $0 + ($1.eatenKcal ?? 0) * Double($1.daysWithEntries) }
        let budget = buckets.reduce(0.0) { $0 + ($1.budgetKcal ?? 0) * Double($1.daysWithEntries) }
        let mean = IntakeFormat.grouped(Int((total / Double(max(1, days))).rounded()), locale: locale)
        let budgetText = IntakeFormat.grouped(Int((budget / Double(max(1, days))).rounded()), locale: locale)
        return String(localized: "Tagesmittel etwa \(mean) Kilokalorien, Budget \(budgetText). Einträge an \(days) Tagen.", bundle: .module)
    }

    /// "82 Messungen. 7-Tage-Mittel 81,9 Kilogramm, Trend minus 0,3 Kilogramm pro Woche."
    public static func weightSummary(measurements: Int, summary: WeightTrend.Summary, locale: Locale = .current) -> String {
        guard measurements > 0 else { return String(localized: "Keine Messungen in diesem Zeitraum.", bundle: .module) }
        var parts = [String(localized: "\(measurements) Messungen.", bundle: .module)]
        if let mean = summary.mean {
            parts.append(String(localized: "7-Tage-Mittel \(WeightFormat.kilograms(mean, locale: locale)).", bundle: .module))
        }
        if let trend = summary.trendPerWeek {
            parts.append(String(localized: "Trend \(WeightFormat.changePerWeek(trend, locale: locale)).", bundle: .module))
        }
        return parts.joined(separator: " ")
    }
}
