import Foundation

/// What a reminder counts from; decides the wording of the distance 0.
public enum ReminderSubject: Sendable, Equatable {
    case task, event, deadline
}

extension ReminderKind {
    /// What reminders of this kind count from.
    public var subject: ReminderSubject {
        switch self {
        case .event: .event
        case .deadline: .deadline
        case .appleReminder, .githubIssue, .localTask: .task
        }
    }
}

/// Texts for reminder offsets, in the language of the locale (plan P4, Task 1).
public enum ReminderText {
    /// "15 Minuten vorher", "1 Tag vorher um 18:00". Distance 0 names what the reminder refers to: "Zur Fälligkeit" (task),
    /// "Zum Beginn" (event), "Zur Deadline" (deadline); for an entry without a time of day "Am Tag selbst".
    /// `subject` has no default on purpose, so no caller silently writes "Zur Fälligkeit" for an event.
    public static func describe(_ offset: ReminderOffset, subject: ReminderSubject, isAllDay: Bool = false,
                                locale: Locale = .current, calendar: Calendar = .current) -> String {
        let language = VoiceLanguage.from(locale: locale)
        func text(_ key: String.LocalizationValue) -> String { Localized.string(key, in: language, bundle: .module) }
        switch offset {
        case .before(let amount, let unit):
            if amount == 0 {
                if isAllDay { return text("Am Tag selbst") }
                switch subject {
                case .task: return text("Zur Fälligkeit")
                case .event: return text("Zum Beginn")
                case .deadline: return text("Zur Deadline")
                }
            }
            switch unit {
            case .minutes: return text("\(amount) Minuten vorher")
            case .hours: return text("\(amount) Stunden vorher")
            case .days: return text("\(amount) Tage vorher")
            case .weeks: return text("\(amount) Wochen vorher")
            }
        case .at(let daysBefore, let hour, let minute):
            let clock = DateText.time(minutes: hour * 60 + minute, calendar: calendar, locale: locale)
            switch daysBefore {
            case 0: return text("Am Tag selbst um \(clock)")
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
    public static func summary(_ list: [ReminderOffset], subject: ReminderSubject, isAllDay: Bool = false,
                               locale: Locale = .current, calendar: Calendar = .current) -> String {
        let language = VoiceLanguage.from(locale: locale)
        guard let first = list.first else { return Localized.string("Keine", in: language, bundle: .module) }
        let firstText = describe(first, subject: subject, isAllDay: isAllDay, locale: locale, calendar: calendar)
        guard list.count > 1 else { return firstText }
        return Localized.string("\(firstText) + \(list.count - 1) weitere", in: language, bundle: .module)
    }

    /// The row in a form: "Standard · 1 Tag vorher um 18:00 + 1 weitere" while the default applies, without the prefix
    /// for an own list, "Keine" for an own empty list.
    public static func rowSummary(_ list: [ReminderOffset], isDefault: Bool, subject: ReminderSubject, isAllDay: Bool = false,
                                  locale: Locale = .current, calendar: Calendar = .current) -> String {
        let text = summary(list, subject: subject, isAllDay: isAllDay, locale: locale, calendar: calendar)
        guard isDefault else { return text }
        return Localized.string("Standard · \(text)", in: VoiceLanguage.from(locale: locale), bundle: .module)
    }
}
