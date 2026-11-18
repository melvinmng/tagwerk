import Foundation
import Observation
import TagwerkCore

/// State of the recurrence page (mockup RK3), without SwiftUI. Every change goes through a method, so the
/// model knows whether the user made a choice: until then `recurrence` is the original value unchanged,
/// and an unreadable rule from Reminders is never rewritten just by opening the page.
@MainActor
@Observable
final class RecurrenceEditorModel {
    enum Frequency: CaseIterable, Hashable {
        case day, week, month, year
    }

    enum MonthOption: Hashable {
        case dayOfMonth, weekdayOfMonth
    }

    enum EndKind: CaseIterable, Hashable {
        case never, date, count
    }

    let original: Recurrence?
    let calendar: Calendar
    /// First day of the series: the due date (or the day the due date will get).
    private(set) var start: PlanDay
    /// `nil` means "Nie" (or an unreadable original that has not been replaced).
    private(set) var frequency: Frequency?
    private(set) var interval = 1
    /// Weekdays 1 = Sunday … 7 = Saturday.
    private(set) var weekdays: Set<Int>
    private(set) var monthOption: MonthOption = .dayOfMonth
    private(set) var monthDay: Int
    private(set) var ordinal: Int
    private(set) var ordinalWeekday: Int
    private(set) var endKind: EndKind = .never
    private(set) var endDate: PlanDay
    private(set) var count = 10
    /// True after the first choice of the user.
    private(set) var isChanged = false

    init(original: Recurrence?, start: PlanDay, calendar: Calendar) {
        self.original = original
        self.start = start
        self.calendar = calendar
        weekdays = [start.weekday(in: calendar)]
        monthDay = start.day
        ordinal = Self.ordinal(of: start)
        ordinalWeekday = start.weekday(in: calendar)
        endDate = Self.defaultEnd(after: start, calendar: calendar)
        if let original { load(original) }
    }

    // MARK: Derived values

    /// The resulting repetition: the original until the user chooses something.
    var recurrence: Recurrence? {
        guard isChanged else { return original }
        guard let frequency else { return nil }
        let rule: RecurrenceRule = switch frequency {
        case .day: .daily(interval: interval)
        case .week: .weekly(interval: interval, weekdays: weekdays)
        case .month where monthOption == .weekdayOfMonth && canUseWeekdayOfMonth:
            .monthlyWeekday(interval: interval, ordinal: ordinal, weekday: ordinalWeekday)
        case .month: .monthly(interval: interval, day: monthDay)
        case .year: .yearly(interval: interval)
        }
        return Recurrence(rule: rule, start: start, end: endKind == .date ? max(endDate, start) : nil,
                          count: endKind == .count ? count : nil)
    }

    var isUnsupportedOriginal: Bool {
        if case .unsupported = original?.rule { return true }
        return false
    }

    /// The "Nie" chip: no repetition (an untouched unreadable rule is not "Nie").
    var isNever: Bool { recurrence == nil }

    var selectedPreset: RecurrencePreset? {
        guard let recurrence else { return nil }
        return RecurrencePreset.matching(recurrence.rule, start: start, calendar: calendar)
    }

    var summary: String {
        recurrence.map { RecurrenceText.summary($0, calendar: calendar) } ?? String(localized: "Nie")
    }

    /// "Am 3. Mittwoch" exists only for the first four weeks of a month (days 1 to 28).
    var canUseWeekdayOfMonth: Bool { (1...4).contains(ordinal) }

    /// Months without this day are skipped (Tagwerk's model; EventKit unverified, plan §3 item 4).
    var skipsShortMonths: Bool {
        frequency == .month && (monthOption == .dayOfMonth || !canUseWeekdayOfMonth) && monthDay > 28
    }

    /// The next occurrences from the start, computed like the planning (`TagwerkCore.occurrences`).
    func nextOccurrences(_ limit: Int) -> [PlanDay] {
        guard let recurrence else { return [] }
        return TagwerkCore.nextOccurrences(of: recurrence, onOrAfter: start, limit: limit, calendar: calendar)
    }

    /// The last occurrence of a series with a count.
    var lastOccurrence: PlanDay? {
        guard let recurrence, let count = recurrence.count, !isUnsupportedOriginal || isChanged else { return nil }
        return TagwerkCore.nextOccurrences(of: recurrence, onOrAfter: start, limit: count, calendar: calendar).last
    }

    /// The next matching day when the due date is no occurrence of the new rule (decision 2026-11-18:
    /// suggest, do not move automatically).
    var suggestedDue: PlanDay? {
        guard isChanged, let recurrence, let next = nextOccurrence(of: recurrence, onOrAfter: start, calendar: calendar),
              next != start else { return nil }
        return next
    }

    /// Ranges of the interval stepper per frequency.
    var intervalRange: ClosedRange<Int> {
        switch frequency {
        case .day, nil: 1...365
        case .week: 1...52
        case .month: 1...24
        case .year: 1...10
        }
    }

    // MARK: Choices

    func apply(preset: RecurrencePreset) {
        load(Recurrence(rule: preset.rule(for: start, calendar: calendar), start: start, end: nil, count: nil), keepEnd: true)
        isChanged = true
    }

    func selectNever() {
        frequency = nil
        isChanged = true
    }

    /// Keeps the interval; weekday and day of the month come from the start.
    func setFrequency(_ newFrequency: Frequency) {
        guard newFrequency != frequency else { return }
        frequency = newFrequency
        interval = min(interval, intervalRange.upperBound)
        weekdays = [start.weekday(in: calendar)]
        monthDay = start.day
        ordinal = Self.ordinal(of: start)
        ordinalWeekday = start.weekday(in: calendar)
        isChanged = true
    }

    func setInterval(_ value: Int) {
        interval = min(max(1, value), intervalRange.upperBound)
        isChanged = true
    }

    /// The last selected weekday cannot be removed.
    func toggleWeekday(_ weekday: Int) {
        guard (1...7).contains(weekday) else { return }
        if weekdays.contains(weekday) {
            guard weekdays.count > 1 else { return }
            weekdays.remove(weekday)
        } else {
            weekdays.insert(weekday)
        }
        isChanged = true
    }

    func setMonthOption(_ option: MonthOption) {
        monthOption = option
        isChanged = true
    }

    func setEndKind(_ kind: EndKind) {
        endKind = kind
        isChanged = true
    }

    func setEndDate(_ day: PlanDay) {
        endDate = max(day, start)
        isChanged = true
    }

    func setCount(_ value: Int) {
        count = min(max(1, value), 999)
        isChanged = true
    }

    /// The due date changed (or the suggestion was taken): the series starts there; the rule stays.
    func updateStart(_ day: PlanDay) {
        start = day
        if endDate < day { endDate = day }
        if !isChanged, frequency == nil {
            weekdays = [day.weekday(in: calendar)]
            monthDay = day.day
            ordinal = Self.ordinal(of: day)
            ordinalWeekday = day.weekday(in: calendar)
        }
    }

    // MARK: Helpers

    /// Shows `recurrence` in the controls. An empty weekday set shows the start's weekday without
    /// changing `recurrence` (which stays the original until the user chooses something).
    private func load(_ recurrence: Recurrence, keepEnd: Bool = false) {
        switch recurrence.rule {
        case .daily(let value):
            frequency = .day
            interval = value
        case .weekly(let value, let days):
            frequency = .week
            interval = value
            weekdays = days.isEmpty ? [start.weekday(in: calendar)] : days
        case .monthly(let value, let day):
            frequency = .month
            interval = value
            monthOption = .dayOfMonth
            monthDay = day
        case .monthlyWeekday(let value, let number, let weekday):
            frequency = .month
            interval = value
            monthOption = .weekdayOfMonth
            ordinal = number
            ordinalWeekday = weekday
        case .yearly(let value):
            frequency = .year
            interval = value
        case .unsupported:
            frequency = nil
        }
        interval = max(1, interval)
        guard !keepEnd else { return }
        if let end = recurrence.end {
            endKind = .date
            endDate = end
        } else if let value = recurrence.count {
            endKind = .count
            count = value
        }
    }

    private static func ordinal(of day: PlanDay) -> Int { (day.day - 1) / 7 + 1 }

    private static func defaultEnd(after start: PlanDay, calendar: Calendar) -> PlanDay {
        let date = calendar.date(byAdding: .month, value: 3, to: start.startDate(in: calendar)) ?? start.startDate(in: calendar)
        return PlanDay(date: date, calendar: calendar)
    }
}

/// Whether a source can repeat in stage 1 of the plan (reminders only).
enum RecurrenceAvailability: Equatable {
    case available
    case unavailable(reason: String)

    /// The row in "Neue Aufgabe": reminders can repeat; local tasks (stage 2) and GitHub issues cannot.
    static func forNewTask(_ source: TaskSource) -> RecurrenceAvailability {
        switch source {
        case .reminders: .available
        case .local: .unavailable(reason: String(localized: "Nur für Erinnerungen"))
        case .github: .unavailable(reason: String(localized: "GitHub-Issues wiederholen sich nicht"))
        }
    }

    /// The repetition of a new task: only for reminders with a due date, starting at that date. A rule chosen
    /// before switching to another source is dropped.
    static func draftRecurrence(_ recurrence: Recurrence?, target: TaskSource, due: DueDate?) -> Recurrence? {
        guard forNewTask(target) == .available, var recurrence, let due else { return nil }
        recurrence.start = PlanDay(due)
        return recurrence
    }
}
