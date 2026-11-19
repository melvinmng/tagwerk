import Foundation

/// Texts for reminder offsets, in the language of the locale (plan P4, Task 1).
public enum ReminderText {
    /// "15 Minuten vorher", "1 Tag vorher um 18:00", "Zum Zeitpunkt".
    public static func describe(_ offset: ReminderOffset, locale: Locale = .current, calendar: Calendar = .current) -> String {
        let language = VoiceLanguage.from(locale: locale)
        func text(_ key: String.LocalizationValue) -> String { Localized.string(key, in: language, bundle: .module) }
        switch offset {
        case .before(let amount, let unit):
            if amount == 0 { return text("Zum Zeitpunkt") }
            switch unit {
            case .minutes: return text("\(amount) Minuten vorher")
            case .hours: return text("\(amount) Stunden vorher")
            case .days: return text("\(amount) Tage vorher")
            case .weeks: return text("\(amount) Wochen vorher")
            }
        case .at(let daysBefore, let hour, let minute):
            let clock = DateText.time(minutes: hour * 60 + minute, calendar: calendar, locale: locale)
            switch daysBefore {
            case 0: return text("Am selben Tag um \(clock)")
            case 1: return text("1 Tag vorher um \(clock)")
            default: return text("\(daysBefore) Tage vorher um \(clock)")
            }
        case .absolute(let date):
            let day = date.formatted(Date.FormatStyle(date: .numeric, time: .omitted, locale: locale, calendar: calendar,
                                                      timeZone: calendar.timeZone))
            return [day, DateText.time(date, calendar: calendar, locale: locale)].joined(separator: ", ")
        }
    }

    /// One line for a list: "Keine", the only entry as written, or "2 Wochen vorher + 2 weitere".
    public static func summary(_ list: [ReminderOffset], locale: Locale = .current, calendar: Calendar = .current) -> String {
        let language = VoiceLanguage.from(locale: locale)
        guard let first = list.first else { return Localized.string("Keine", in: language, bundle: .module) }
        let firstText = describe(first, locale: locale, calendar: calendar)
        guard list.count > 1 else { return firstText }
        return Localized.string("\(firstText) + \(list.count - 1) weitere", in: language, bundle: .module)
    }
}
