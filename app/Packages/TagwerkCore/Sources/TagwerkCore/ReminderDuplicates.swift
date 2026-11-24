import Foundation

/// Reminders of Tagwerk and alarms of the calendar that fire in the same minute for one entry (plan g1, ER5b). The user is
/// reminded twice then, once by Tagwerk and once by the calendar; the deadline page says so.
public enum ReminderDuplicates {
    /// Reminders of both lists that fire in the same minute for this entry, in the order of `tagwerk`.
    public static func find(tagwerk: [ReminderOffset], calendarAlarms: [ReminderOffset], anchor: Date, isAllDay: Bool,
                            calendar: Calendar) -> [(offset: ReminderOffset, fire: Date)] {
        func minute(_ date: Date) -> Int { Int((date.timeIntervalSince1970 / 60).rounded(.down)) }
        let alarmMinutes = Set(calendarAlarms.compactMap {
            $0.fireDate(anchor: anchor, isAllDay: isAllDay, calendar: calendar).map(minute)
        })
        return tagwerk.compactMap { offset in
            guard let fire = offset.fireDate(anchor: anchor, isAllDay: isAllDay, calendar: calendar),
                  alarmMinutes.contains(minute(fire)) else { return nil }
            return (offset, fire)
        }
    }

    /// "Doppelt: „1 Tag vorher“ – Tagwerk und Kalender erinnern beide am So., 22. Nov."
    public static func notice(_ duplicate: (offset: ReminderOffset, fire: Date), subject: ReminderSubject, isAllDay: Bool,
                              locale: Locale = .current, calendar: Calendar = .current) -> String {
        let language = VoiceLanguage.from(locale: locale)
        let name = ReminderText.describe(duplicate.offset, subject: subject, isAllDay: isAllDay, locale: locale, calendar: calendar)
        let day = duplicate.fire.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.abbreviated).day().month(.abbreviated))
        return Localized.string("Doppelt: „\(name)“ – Tagwerk und Kalender erinnern beide am \(day)", in: language, bundle: .module)
    }
}

/// The question for a repeating entry before reminders change (plan g1, ER8b): what changes, and from which day on.
public enum ReminderReachText {
    /// "Erinnerungen für welche Termine ändern?" / "… welche Fälligkeiten ändern?"
    public static func title(_ subject: ReminderSubject, locale: Locale = .current) -> String {
        let language = VoiceLanguage.from(locale: locale)
        switch subject {
        case .task: return Localized.string("Erinnerungen für welche Fälligkeiten ändern?", in: language, bundle: .module)
        case .event, .deadline: return Localized.string("Erinnerungen für welche Termine ändern?", in: language, bundle: .module)
        }
    }

    /// "Nur am 27. Nov."
    public static func onlyThis(_ day: PlanDay, calendar: Calendar, locale: Locale = .current) -> String {
        Localized.string("Nur am \(dayText(day, calendar: calendar, locale: locale))", in: VoiceLanguage.from(locale: locale), bundle: .module)
    }

    /// "Ab 27. Nov. für alle folgenden"
    public static func fromThis(_ day: PlanDay, calendar: Calendar, locale: Locale = .current) -> String {
        Localized.string("Ab \(dayText(day, calendar: calendar, locale: locale)) für alle folgenden",
                         in: VoiceLanguage.from(locale: locale), bundle: .module)
    }

    private static func dayText(_ day: PlanDay, calendar: Calendar, locale: Locale) -> String {
        day.startDate(in: calendar).formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .day().month(.abbreviated))
    }
}
