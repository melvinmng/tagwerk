import EventKit
import Foundation
import TagwerkCore

/// Conversion between Tagwerk's `Recurrence` and `EKRecurrenceRule`, without an event store.
///
/// Assumptions about EventKit that are not verified on a device yet (plan §3) are kept in this file:
/// the spelling of "n-th weekday" (`nthWeekday`) and the time of the end date (`endDate(for:calendar:)`).
public enum RecurrenceMapping {
    /// The rule to write, or `nil` when the recurrence must not be written (`.unsupported` or invalid values).
    /// `start` is not written: EventKit takes the start of the series from the reminder's due date.
    public static func ekRule(for recurrence: Recurrence, calendar: Calendar) -> EKRecurrenceRule? {
        guard recurrence.isValid else { return nil }
        let end: EKRecurrenceEnd? = if let day = recurrence.end {
            EKRecurrenceEnd(end: endDate(for: day, calendar: calendar))
        } else if let count = recurrence.count {
            EKRecurrenceEnd(occurrenceCount: count)
        } else {
            nil
        }
        switch recurrence.rule {
        case .daily(let interval):
            return make(.daily, interval: interval, end: end)
        case .weekly(let interval, let weekdays):
            let days = weekdays.sorted().compactMap(EKWeekday.init(rawValue:)).map { EKRecurrenceDayOfWeek($0) }
            return make(.weekly, interval: interval, weekdays: days.isEmpty ? nil : days, end: end)
        case .monthly(let interval, let day):
            return make(.monthly, interval: interval, monthDays: [NSNumber(value: day)], end: end)
        case .monthlyWeekday(let interval, let ordinal, let weekday):
            guard let day = EKWeekday(rawValue: weekday) else { return nil }
            return make(.monthly, interval: interval, weekdays: [nthWeekday(day, ordinal: ordinal)], end: end)
        case .yearly(let interval):
            return make(.yearly, interval: interval, end: end)
        case .unsupported:
            return nil
        }
    }

    /// Maps a rule to Tagwerk's patterns; anything Tagwerk cannot express becomes `.unsupported`.
    /// Unset and empty lists count the same. The series starts at the due date.
    public static func recurrence(from rule: EKRecurrenceRule, due: DueDate, calendar: Calendar) -> Recurrence {
        let interval = max(1, rule.interval)
        let weekdays = rule.daysOfTheWeek ?? []
        let monthDays = (rule.daysOfTheMonth ?? []).map(\.intValue)
        let months = (rule.monthsOfTheYear ?? []).map(\.intValue)
        let positions = (rule.setPositions ?? []).map(\.intValue)
        let yearParts = (rule.weeksOfTheYear ?? []).count + (rule.daysOfTheYear ?? []).count
        let pattern: RecurrenceRule
        // Hourly rules of the Reminders app have no public frequency and would otherwise read as daily.
        if isSubDaily(ruleText: rule.description) {
            return Recurrence(rule: .unsupported, start: PlanDay(due), end: nil, count: nil)
        }
        switch rule.frequency {
        case .daily where weekdays.isEmpty:
            pattern = .daily(interval: interval)
        case .weekly where positions.isEmpty:
            pattern = .weekly(interval: interval, weekdays: Set(weekdays.map { $0.dayOfTheWeek.rawValue }))
        case .monthly where weekdays.isEmpty && monthDays.count <= 1 && positions.isEmpty && months.isEmpty:
            let day = monthDays.first ?? due.day
            pattern = (1...31).contains(day) ? .monthly(interval: interval, day: day) : .unsupported
        case .monthly where weekdays.count == 1 && monthDays.isEmpty && months.isEmpty:
            let entry = weekdays[0]
            let ordinal: Int? = switch (entry.weekNumber, positions.count) {
            case (0, 1): positions[0]
            case (let number, 0) where number != 0: number
            default: nil
            }
            if let ordinal, (1...4).contains(ordinal) {
                pattern = .monthlyWeekday(interval: interval, ordinal: ordinal, weekday: entry.dayOfTheWeek.rawValue)
            } else {
                pattern = .unsupported
            }
        case .yearly where weekdays.isEmpty && positions.isEmpty && yearParts == 0
            && (months.isEmpty || months == [due.month]) && (monthDays.isEmpty || monthDays == [due.day]):
            pattern = .yearly(interval: interval)
        default:
            pattern = .unsupported
        }
        let end = rule.recurrenceEnd?.endDate.map { PlanDay(date: $0, calendar: calendar) }
        let count = rule.recurrenceEnd.flatMap { $0.occurrenceCount > 0 ? $0.occurrenceCount : nil }
        return Recurrence(rule: pattern, start: PlanDay(due), end: end, count: count)
    }

    /// Unverified assumption: EventKit describes a rule with its RRULE text ("FREQ=HOURLY"), also for frequencies
    /// that `EKRecurrenceFrequency` cannot express.
    static func isSubDaily(ruleText: String) -> Bool {
        ["FREQ=HOURLY", "FREQ=MINUTELY", "FREQ=SECONDLY"].contains { ruleText.contains($0) }
    }

    /// Unverified assumption (plan §3, item 6): the end is written as the last second of the end day in the
    /// device's time zone, so a timed occurrence on that day is still included and reading the date back in
    /// the same time zone gives the same calendar day.
    static func endDate(for day: PlanDay, calendar: Calendar) -> Date {
        day.adding(days: 1, calendar: calendar).startDate(in: calendar).addingTimeInterval(-1)
    }

    /// Unverified assumption (plan §3, item 2): "the 3rd Wednesday" is written as a weekday with week number,
    /// not as a weekday with `setPositions`. Both forms are read.
    static func nthWeekday(_ day: EKWeekday, ordinal: Int) -> EKRecurrenceDayOfWeek {
        EKRecurrenceDayOfWeek(day, weekNumber: ordinal)
    }

    private static func make(_ frequency: EKRecurrenceFrequency, interval: Int, weekdays: [EKRecurrenceDayOfWeek]? = nil,
                             monthDays: [NSNumber]? = nil, end: EKRecurrenceEnd?) -> EKRecurrenceRule {
        EKRecurrenceRule(recurrenceWith: frequency, interval: interval, daysOfTheWeek: weekdays, daysOfTheMonth: monthDays,
                         monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: end)
    }
}
