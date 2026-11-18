import Foundation

/// Plain-text form of a recurrence ("Alle 2 Wochen am Mo und Do, bis 31. März 2027"), mockup RK3.
public enum RecurrenceText {
    /// The rule followed by its end. Weekdays are listed in the order of the calendar's week.
    public static func summary(_ recurrence: Recurrence, locale: Locale = .current, calendar: Calendar) -> String {
        if case .unsupported = recurrence.rule { return text("Eigene Regel aus Erinnerungen", locale) }
        let rule = ruleText(recurrence, locale: locale, calendar: calendar)
        if let end = recurrence.end {
            return rule + ", " + text("bis \(longDate(end, withYear: true, locale: locale, calendar: calendar))", locale)
        }
        if let count = recurrence.count {
            return rule + ", " + text("\(count) Mal", locale)
        }
        return rule
    }

    private static func ruleText(_ recurrence: Recurrence, locale: Locale, calendar: Calendar) -> String {
        switch recurrence.rule {
        case .daily(let interval):
            return interval <= 1 ? text("Jeden Tag", locale) : text("Alle \(interval) Tage", locale)
        case .weekly(let interval, let weekdays):
            let days = weekdays.isEmpty ? [recurrence.start.weekday(in: calendar)] : weekdays
            if interval <= 1, days == [2, 3, 4, 5, 6] { return text("Jeden Werktag (Mo bis Fr)", locale) }
            if interval <= 1, days == [7, 1] { return text("Jedes Wochenende (Sa und So)", locale) }
            let list = weekdayList(days, locale: locale, calendar: calendar)
            return interval <= 1 ? text("Jede Woche am \(list)", locale) : text("Alle \(interval) Wochen am \(list)", locale)
        case .monthly(let interval, let day):
            return interval <= 1 ? text("Jeden Monat am \(day).", locale) : text("Alle \(interval) Monate am \(day).", locale)
        case .monthlyWeekday(let interval, let ordinal, let weekday):
            let number = ordinalText(ordinal, locale: locale)
            let name = weekdayName(weekday, locale: locale, calendar: calendar)
            return interval <= 1
                ? text("Jeden Monat am \(number) \(name)", locale)
                : text("Alle \(interval) Monate am \(number) \(name)", locale)
        case .yearly(let interval):
            let date = longDate(recurrence.start, withYear: false, locale: locale, calendar: calendar)
            return interval <= 1 ? text("Jedes Jahr am \(date)", locale) : text("Alle \(interval) Jahre am \(date)", locale)
        case .unsupported:
            return text("Eigene Regel aus Erinnerungen", locale)
        }
    }

    /// "Mo und Do" / "Mon and Thu", starting with the calendar's first weekday.
    private static func weekdayList(_ weekdays: Set<Int>, locale: Locale, calendar: Calendar) -> String {
        let symbols = shortWeekdaySymbols(locale: locale, calendar: calendar)
        let ordered = weekdays.filter { (1...7).contains($0) }
            .sorted { position($0, calendar) < position($1, calendar) }
        return ordered.map { symbols[$0 - 1] }.formatted(.list(type: .and).locale(locale))
    }

    /// Position of a weekday (1 = Sunday … 7 = Saturday) within the calendar's week, 0 for the first weekday.
    private static func position(_ weekday: Int, _ calendar: Calendar) -> Int {
        (weekday - calendar.firstWeekday + 7) % 7
    }

    /// Abbreviated standalone weekday names indexed by weekday - 1 (Sunday first).
    private static func shortWeekdaySymbols(locale: Locale, calendar: Calendar) -> [String] {
        var localized = calendar
        localized.locale = locale
        return localized.shortStandaloneWeekdaySymbols
    }

    private static func weekdayName(_ weekday: Int, locale: Locale, calendar: Calendar) -> String {
        var localized = calendar
        localized.locale = locale
        let symbols = localized.standaloneWeekdaySymbols
        return symbols[(max(1, min(7, weekday)) - 1) % symbols.count]
    }

    /// "3." in German, "3rd" in English.
    private static func ordinalText(_ number: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)."
    }

    /// "18. November" / "November 18", optionally with the year.
    private static func longDate(_ day: PlanDay, withYear: Bool, locale: Locale, calendar: Calendar) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.wide)
        return day.startDate(in: calendar).formatted(withYear ? style.year() : style)
    }

    private static func text(_ key: String.LocalizationValue, _ locale: Locale) -> String {
        String(localized: LocalizedStringResource(key, locale: locale, bundle: .atURL(Bundle.module.bundleURL)))
    }
}
