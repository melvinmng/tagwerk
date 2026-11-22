import Foundation

/// One reminder time of Bible Study with the weekdays it applies to (alarm model, BE2b). Weekdays count like `Calendar`
/// (1 = Sunday … 7 = Saturday).
public struct BibleStudyReminderTime: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    /// Minutes since midnight.
    public var minutes: Int
    public var weekdays: Set<Int>

    public init(id: UUID = UUID(), minutes: Int, weekdays: Set<Int>) {
        self.id = id
        self.minutes = minutes
        self.weekdays = weekdays
    }
}

/// The list of reminder times (BE2b): every weekday belongs to at most one time, so there is at most one reminder a day.
public enum BibleStudyReminderTimes {
    /// All seven weekdays in the order of the week, Monday first (the order the settings show them in).
    public static let weekdaysFromMonday = [2, 3, 4, 5, 6, 7, 1]

    /// Adds `time` or replaces the time with the same id. Its weekdays are taken from the other times; a time left without
    /// weekdays is dropped, the saved one included.
    public static func saving(_ time: BibleStudyReminderTime, into times: [BibleStudyReminderTime]) -> [BibleStudyReminderTime] {
        var result: [BibleStudyReminderTime] = []
        var placed = false
        for existing in times {
            if existing.id == time.id {
                result.append(time)
                placed = true
            } else {
                var other = existing
                other.weekdays.subtract(time.weekdays)
                result.append(other)
            }
        }
        if !placed { result.append(time) }
        return result.filter { !$0.weekdays.isEmpty }
    }

    /// The weekdays that other times already use: they are not selectable in the sheet of `time`.
    public static func takenWeekdays(for time: BibleStudyReminderTime, in times: [BibleStudyReminderTime]) -> Set<Int> {
        times.filter { $0.id != time.id }.reduce(into: Set<Int>()) { $0.formUnion($1.weekdays) }
    }

    /// The reminder time of a weekday in minutes since midnight, `nil` when no time applies to it.
    public static func minutes(on weekday: Int, in times: [BibleStudyReminderTime]) -> Int? {
        times.first { $0.weekdays.contains(weekday) }?.minutes
    }

    /// "06:45 · Mo Di Mi Do Fr": the time, then the weekdays from Monday.
    public static func summary(_ time: BibleStudyReminderTime, locale: Locale) -> String {
        "\(clock(time.minutes, locale: locale)) · \(weekdayNames(time.weekdays, locale: locale).joined(separator: " "))"
    }

    /// "Mo Di Mi Do Fr" as a list of names, Monday first.
    public static func weekdayNames(_ weekdays: Set<Int>, locale: Locale) -> [String] {
        let symbols = DateText.shortStandaloneWeekdaySymbols(calendar: mondayCalendar, locale: locale)
        return weekdaysFromMonday.enumerated().compactMap { weekdays.contains($0.element) ? symbols[$0.offset] : nil }
    }

    /// The clock time of `minutes` in the style of the locale ("06:45").
    public static func clock(_ minutes: Int, locale: Locale) -> String {
        DateText.time(minutes: minutes, calendar: mondayCalendar, locale: locale)
    }

    private static var mondayCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }
}
