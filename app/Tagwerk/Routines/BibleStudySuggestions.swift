import Foundation
import TagwerkCore

/// The learned reminder time of Bible Study as the app uses it (BS8): what is suggested, and what "Erinnern", "Zeit ändern" and
/// "Nicht jetzt" do. The suggestion is never applied by itself.
extension AppEnvironment {
    /// The suggestions from the completed sessions that are not snoozed and differ from the times already set.
    func bibleStudySuggestions(now: Date = Date()) -> [BibleStudyHabitTime.Suggestion] {
        BibleStudyHabitTime.suggestions(startTimes: notes.completedSessionStartTimes(), existing: settings.bibleStudyReminderTimes,
                                        snoozedUntil: settings.bibleStudySuggestionSnoozedUntil, now: now, calendar: planning.calendar)
    }

    /// The suggestion whose card is to be shown after a completed session: the first one not shown before. It counts as shown from
    /// here on, so the card comes once per new suggestion.
    func nextBibleStudySuggestionCard(now: Date = Date()) -> BibleStudyHabitTime.Suggestion? {
        let shown = Set((settings.bibleStudySuggestionShownKeys ?? "").split(separator: ",").map(String.init))
        guard let suggestion = bibleStudySuggestions(now: now).first(where: { !shown.contains($0.key) }) else { return nil }
        settings.bibleStudySuggestionShownKeys = shown.union([suggestion.key]).sorted().joined(separator: ",")
        return suggestion
    }

    /// "Erinnern" / "Übernehmen": the time with the weekdays of its group joins the list (taking the days from other times), the
    /// reminder is switched on and the permission is asked for when it was not asked yet.
    func adoptBibleStudySuggestion(_ suggestion: BibleStudyHabitTime.Suggestion) async {
        let time = BibleStudyReminderTime(minutes: suggestion.minutes, weekdays: suggestion.group.weekdays)
        settings.bibleStudyReminderTimes = BibleStudyReminderTimes.saving(time, into: settings.bibleStudyReminderTimes)
        settings.bibleStudyReminderEnabled = true
        if routineNotifications.authorization == .notDetermined { await notifications.requestAuthorization() }
        await routineNotifications.reschedule()
    }

    /// "Nicht jetzt": no suggestion for `BibleStudyHabitTime.snoozeDays` days.
    func snoozeBibleStudySuggestion(now: Date = Date()) {
        settings.bibleStudySuggestionSnoozedUntil = planning.calendar.date(byAdding: .day, value: BibleStudyHabitTime.snoozeDays, to: now)
    }
}

/// Texts of the suggestion as static functions, so they can be tested.
enum BibleStudySuggestionText {
    /// "Du beginnst werktags meist zwischen 06:30 und 07:10. Soll Tagwerk dich Mo–Fr um 06:45 erinnern?"
    static func card(_ suggestion: BibleStudyHabitTime.Suggestion, locale: Locale) -> String {
        let days = BibleStudyReminderText.weekdayList(suggestion.group.weekdays, locale: locale)
        let from = BibleStudyReminderTimes.clock(suggestion.windowStart, locale: locale)
        let to = BibleStudyReminderTimes.clock(suggestion.windowEnd, locale: locale)
        let at = BibleStudyReminderTimes.clock(suggestion.minutes, locale: locale)
        switch suggestion.group {
        case .weekdays: return String(localized: "Du beginnst werktags meist zwischen \(from) und \(to). Soll Tagwerk dich \(days) um \(at) erinnern?")
        case .weekend: return String(localized: "Du beginnst am Wochenende meist zwischen \(from) und \(to). Soll Tagwerk dich \(days) um \(at) erinnern?")
        }
    }

    /// "Sa und So gegen 08:30"
    static func title(_ suggestion: BibleStudyHabitTime.Suggestion, locale: Locale) -> String {
        let days = BibleStudyReminderText.weekdayList(suggestion.group.weekdays, locale: locale)
        let at = BibleStudyReminderTimes.clock(suggestion.minutes, locale: locale)
        return String(localized: "\(days) gegen \(at)")
    }

    /// "An 7 von 8 Sitzungen am Wochenende der letzten 8 Wochen hast du zwischen 08:10 und 08:50 begonnen." The numbers are
    /// sessions, not weekends: a day can hold more than one.
    static func reason(_ suggestion: BibleStudyHabitTime.Suggestion, locale: Locale) -> String {
        let from = BibleStudyReminderTimes.clock(suggestion.windowStart, locale: locale)
        let to = BibleStudyReminderTimes.clock(suggestion.windowEnd, locale: locale)
        let weeks = BibleStudyHabitTime.weeks
        switch suggestion.group {
        case .weekdays:
            return String(localized: "An \(suggestion.sessionsInWindow) von \(suggestion.sessions) Sitzungen an Werktagen der letzten \(weeks) Wochen hast du zwischen \(from) und \(to) begonnen.")
        case .weekend:
            return String(localized: "An \(suggestion.sessionsInWindow) von \(suggestion.sessions) Sitzungen am Wochenende der letzten \(weeks) Wochen hast du zwischen \(from) und \(to) begonnen.")
        }
    }
}
