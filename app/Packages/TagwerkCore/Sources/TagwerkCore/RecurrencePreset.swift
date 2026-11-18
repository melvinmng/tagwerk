import Foundation

/// The quick choices of the recurrence page (mockup RK3). Weekday and day of the month come from the
/// start of the series, i.e. the due date.
public enum RecurrencePreset: String, Sendable, Hashable, CaseIterable {
    case daily, weekdays, weekend, weekly, biweekly, monthly, yearly

    /// The rule this preset stands for when the series starts on `start`.
    public func rule(for start: PlanDay, calendar: Calendar) -> RecurrenceRule {
        switch self {
        case .daily: .daily(interval: 1)
        // "Werktags" is fixed to Monday–Friday (decision 2026-11-18), not the working days of the settings.
        case .weekdays: .weekly(interval: 1, weekdays: [2, 3, 4, 5, 6])
        case .weekend: .weekly(interval: 1, weekdays: [7, 1])
        case .weekly: .weekly(interval: 1, weekdays: [start.weekday(in: calendar)])
        case .biweekly: .weekly(interval: 2, weekdays: [start.weekday(in: calendar)])
        case .monthly: .monthly(interval: 1, day: start.day)
        case .yearly: .yearly(interval: 1)
        }
    }

    /// The preset whose rule equals `rule` exactly, or `nil` for a custom rule.
    public static func matching(_ rule: RecurrenceRule, start: PlanDay, calendar: Calendar) -> RecurrencePreset? {
        var normalized = rule
        if case .weekly(let interval, let weekdays) = rule, weekdays.isEmpty {
            normalized = .weekly(interval: interval, weekdays: [start.weekday(in: calendar)])
        }
        return allCases.first { $0.rule(for: start, calendar: calendar) == normalized }
    }
}
