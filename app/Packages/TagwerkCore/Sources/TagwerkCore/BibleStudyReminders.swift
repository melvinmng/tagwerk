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

/// The reminder to read the Bible (BS7): one dated notification a day for the next days, at the time of the weekday.
///
/// Days are calendar days of the place the phone is in: the reminder of a day is for that calendar day, "Heute nicht" is
/// remembered for the calendar day it was tapped on, and a day counts as done when a session of the same day key was completed.
public enum BibleStudyReminders {
    public static let categoryIdentifier = "tagwerk.bible"
    /// "Starten": opens the app on the start sheet.
    public static let startAction = "tagwerk.bible.start"
    /// "Heute nicht": drops the reminder of today without opening the app.
    public static let skipAction = "tagwerk.bible.skip"

    /// "tagwerk.routine.bible.<YYYY-MM-DD>", stable per day, so one day never has two reminders.
    public static func identifier(day: PlanDay) -> String {
        "\(PlannedNotification.routineIdentifierPrefix)bible.\(day.dayKey)"
    }

    /// One reminder per day for the next `days` days, starting today. Left out: days without a time for their weekday, days with
    /// a completed session, the skipped day and moments that are not after `now`. The body is "Zeit für Bible Study." and, when
    /// `nextPassage` is given, " Weiter in Römer ab 3,27." Sorted by the moment they fire.
    public static func notifications(times: [BibleStudyReminderTime], enabled: Bool, completedDays: Set<PlanDay>, skippedDay: PlanDay?,
                                     nextPassage: String?, now: Date, calendar: Calendar, locale: Locale,
                                     days: Int = RoutineSchedule.bibleStudyHorizonDays) -> [DatedRoutineNotification] {
        guard enabled, days > 0, !times.isEmpty else { return [] }
        let language = VoiceLanguage.from(locale: locale)
        let today = PlanDay(date: now, calendar: calendar)
        var planned: [DatedRoutineNotification] = []
        for offset in 0..<days {
            let day = today.adding(days: offset, calendar: calendar)
            guard !completedDays.contains(day), day != skippedDay,
                  let minutes = BibleStudyReminderTimes.minutes(on: day.weekday(in: calendar), in: times) else { continue }
            let clamped = min(max(minutes, 0), 1439)
            guard let moment = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: clamped / 60, minute: clamped % 60)),
                  moment > now else { continue }
            let base = Localized.string("Zeit für Bible Study.", in: language, bundle: .module)
            planned.append(DatedRoutineNotification(
                id: identifier(day: day), year: day.year, month: day.month, day: day.day, hour: clamped / 60, minute: clamped % 60,
                title: Localized.string("Bible Study", in: language, bundle: .module),
                body: nextPassage.map { "\(base) \($0)." } ?? base, route: .bibleStudyStart, categoryIdentifier: categoryIdentifier))
        }
        return planned
    }

    /// "Weiter in Römer ab 3,27" from the book of the latest session and what follows in it; `nil` without a book, for a finished
    /// book, for a session that is free text (`next` is `nil` then) and while the switch "Stelle in der Mitteilung zeigen" is off.
    public static func nextPassageText(bookName: String?, next: BibleProgress.Next?, showsPassage: Bool, locale: Locale) -> String? {
        guard showsPassage, let bookName, case .start(let reference)? = next else { return nil }
        return Localized.string("Weiter in \(bookName) ab \(reference.text)", in: VoiceLanguage.from(locale: locale), bundle: .module)
    }
}
