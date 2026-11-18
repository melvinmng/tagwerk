import Foundation

/// Date and time texts for the screen, formatted for a locale instead of hand-built German patterns.
/// The locale is a parameter (default: the app's), so tests and callers can pass another one.
public enum DateText {
    /// "09:05" in German, "9:05 AM" in US English; `date` is read in the calendar's time zone.
    public static func time(_ date: Date, calendar: Calendar, locale: Locale = .current) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour().minute())
    }

    /// The same for minutes since midnight (a position in the day grid).
    public static func time(minutes: Int, calendar: Calendar, locale: Locale = .current) -> String {
        let midnight = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let date = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: midnight) ?? midnight
        return time(date, calendar: calendar, locale: locale)
    }

    /// "Sa." in German, "Sat" in English.
    public static func shortWeekday(_ day: PlanDay, calendar: Calendar, locale: Locale = .current) -> String {
        let symbols = localized(calendar, locale).shortWeekdaySymbols
        return symbols[(day.weekday(in: calendar) - 1) % symbols.count]
    }

    /// Day and month in the order and with the separators of the locale: "21.11." in German, "11/21" in US English.
    public static func numericDay(_ day: PlanDay, calendar: Calendar, locale: Locale = .current) -> String {
        day.startDate(in: calendar)
            .formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .day(.twoDigits).month(.twoDigits))
    }

    /// The abbreviated weekday names, starting with the calendar's first weekday ("Mo." … "So." for Monday).
    public static func shortWeekdaySymbols(calendar: Calendar, locale: Locale = .current) -> [String] {
        let symbols = localized(calendar, locale).shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private static func localized(_ calendar: Calendar, _ locale: Locale) -> Calendar {
        var copy = calendar
        copy.locale = locale
        return copy
    }
}
