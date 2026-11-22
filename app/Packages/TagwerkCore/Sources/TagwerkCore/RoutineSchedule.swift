import Foundation

/// One point of the evening checklist; `offsetMinutes` counts back from the target bedtime, `nil` means no reminder.
public struct ChecklistItem: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var order: Int
    public var offsetMinutes: Int?

    public init(id: UUID = UUID(), title: String, order: Int, offsetMinutes: Int?) {
        self.id = id
        self.title = title
        self.order = order
        self.offsetMinutes = offsetMinutes
    }
}

/// What the app stores per day for the routines (phase 7 design §5.2). Gratitude never leaves the device.
public struct RoutineDayValue: Sendable, Hashable {
    public static let maximumGratitude = 3

    public var gratitude: [String]
    public var startCompletedAt: Date?
    public var startDismissed: Bool
    public var closeCompletedAt: Date?
    public var checkedItemIDs: Set<UUID>

    public init(gratitude: [String] = [], startCompletedAt: Date? = nil, startDismissed: Bool = false,
                closeCompletedAt: Date? = nil, checkedItemIDs: Set<UUID> = []) {
        self.gratitude = gratitude
        self.startCompletedAt = startCompletedAt
        self.startDismissed = startDismissed
        self.closeCompletedAt = closeCompletedAt
        self.checkedItemIDs = checkedItemIDs
    }

    public static let empty = RoutineDayValue()

    /// Trimmed, empty entries dropped, at most three.
    public static func normalizedGratitude(_ entries: [String]) -> [String] {
        let trimmed = entries.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return Array(trimmed.prefix(maximumGratitude))
    }
}

/// A reminder of the routines that repeats every day, or every week on one weekday, at the same time (phase 7 design
/// §8.1): the morning start and the weekly planning. The texts are static. The evening reminders are dated instead.
public struct RoutineNotification: Sendable, Hashable, Identifiable {
    /// "tagwerk.routine.morning" or "tagwerk.routine.week".
    public var id: String
    public var hour: Int
    public var minute: Int
    public var title: String
    public var body: String
    /// What a tap opens; carried in the notification as the link path.
    public var route: AppRoute
    /// Calendar weekday (1 = Sunday … 7 = Saturday) for a reminder that repeats weekly; `nil` repeats every day.
    public var weekday: Int?

    public init(id: String, hour: Int, minute: Int, title: String, body: String, route: AppRoute, weekday: Int? = nil) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.title = title
        self.body = body
        self.route = route
        self.weekday = weekday
    }
}

/// A routine reminder for one day; fires once at the clock time of the place the phone is in (no time zone), so a
/// trip moves it with the clock. Planned a few days ahead and left out for a point that is already checked (#173).
public struct DatedRoutineNotification: Sendable, Hashable, Identifiable {
    /// "tagwerk.routine.evening.<item UUID>.<routine day YYYY-MM-DD>".
    public var id: String
    /// The calendar day and clock time it fires; before 04:00 this is the day after the routine day (rule 10).
    public var year: Int
    public var month: Int
    public var day: Int
    public var hour: Int
    public var minute: Int
    public var title: String
    public var body: String
    /// What a tap opens; carried in the notification as the link path.
    public var route: AppRoute

    public init(id: String, year: Int, month: Int, day: Int, hour: Int, minute: Int, title: String, body: String, route: AppRoute) {
        self.id = id
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.title = title
        self.body = body
        self.route = route
    }
}

/// Pure rules of the daily routines (phase 7 design §6, rules 9–11, and §11).
public enum RoutineSchedule {
    /// Before 04:00 the evening wrap-up still belongs to the day before (rule 10).
    public static let eveningBoundaryMinutes = 240
    /// The morning card ends at 12:00.
    public static let morningCardEndMinutes = 720
    /// Without an anchor the evening line starts this long before the bedtime.
    public static let fallbackEveningLeadMinutes = 90
    public static let maximumItems = 8
    public static let maximumReminders = 4
    /// The evening reminders are planned for this many routine days, beginning with the one of `now` (#173, decision D9).
    public static let eveningHorizonDays = 3
    /// Most evening reminders pending at once: four points on each planned day.
    public static let maximumEveningNotifications = maximumReminders * eveningHorizonDays
    /// Routine reminders hold at most this many places: the evening reminders of the next days, the morning start and
    /// the weekly planning.
    public static let maximumRoutineNotifications = maximumEveningNotifications + 2
    public static let offsetRange = 0...240
    public static let offsetStep = 5
    public static let titleLimit = 60

    /// The checklist offered for an empty list: the order of the original evening template. The offsets apply to the
    /// default bedtime of 23:00; "from 22:00" is left out of the first title because the bedtime is adjustable. Four
    /// points remind, the limit (RO6b, RO7b): the lights 60 minutes before bedtime (22:00 at the default bedtime, as in
    /// the original template, but moving with the bedtime), then 90, 60 and 30 minutes before. Two points therefore
    /// remind at the same minute, which the planner allows. Read at the time of adoption, so the titles follow the app
    /// language of that moment.
    public static var suggestedItems: [(title: String, offsetMinutes: Int?)] {
        [(String(localized: "Helle Lichter ausmachen", bundle: .module), 60),
         (String(localized: "Alle Aufgaben bis eine Stunde vorm Schlafen erledigen", bundle: .module), 90),
         (String(localized: "Eine Stunde vorm Schlafen fertig machen", bundle: .module), 60),
         (String(localized: "Zähne putzen, umziehen, Haus/Wohnung aufräumen", bundle: .module), nil),
         (String(localized: "Eine halbe Stunde vorm Schlafen ins Bett legen", bundle: .module), 30)]
    }

    /// The titles of the former three-point suggestion, German and English, as fixed strings (not translated): they are
    /// compared with what is stored, which was written in one of the two languages.
    public static let legacySuggestionTitles: [[String]] = [
        ["Tagesabschluss öffnen", "Handy weglegen", "Ins Bett"],
        ["Open evening wrap-up", "Put the phone away", "Go to bed"],
    ]
    private static let legacySuggestionOffsets = [90, 60, 30]

    /// The titles of the five-point suggestion in which "Helle Lichter ausmachen" had no time, German and English, as fixed
    /// strings for the same reason as above.
    public static let fivePointSuggestionTitles: [[String]] = [
        ["Helle Lichter ausmachen", "Alle Aufgaben bis eine Stunde vorm Schlafen erledigen", "Eine Stunde vorm Schlafen fertig machen",
         "Zähne putzen, umziehen, Haus/Wohnung aufräumen", "Eine halbe Stunde vorm Schlafen ins Bett legen"],
        ["Turn off bright lights", "Finish all tasks one hour before sleep", "Get ready one hour before sleep",
         "Brush teeth, change, tidy up the home", "Go to bed half an hour before sleep"],
    ]

    /// The former five-point suggestion in which "Helle Lichter ausmachen" had no time. An untouched list of exactly these
    /// points (titles, order and the offsets nil, 90, 60, nil, 30) gets the offset 60 for the first point (RO6b); any list
    /// the user changed gives `nil`, and so does a list that already has the offset, so the call is safe to repeat. The
    /// caller runs it once per installation, because a user who clears the time of the lights again would otherwise get
    /// it back at every start.
    public static func upgradedLightsOffset(_ items: [ChecklistItem]) -> [ChecklistItem]? {
        let sorted = items.sorted { $0.order < $1.order }
        guard sorted.map(\.offsetMinutes) == [nil, 90, 60, nil, 30],
              fivePointSuggestionTitles.contains(where: { $0 == sorted.map(\.title) }) else { return nil }
        var upgraded = sorted
        upgraded[0].offsetMinutes = 60
        return upgraded
    }

    /// Whether `items` are exactly the former suggestion, untouched: same titles in the same order (by `order`) with
    /// the offsets 90, 60 and 30. Any other list (renamed, reordered, other offset, more or fewer points) is the user's.
    public static func isLegacySuggestion(_ items: [ChecklistItem]) -> Bool {
        let sorted = items.sorted { $0.order < $1.order }
        guard sorted.map(\.offsetMinutes) == legacySuggestionOffsets.map({ Optional($0) }) else { return false }
        return legacySuggestionTitles.contains { $0 == sorted.map(\.title) }
    }

    /// Rule 9: bedtime minus offset, modulo 24 hours.
    public static func anchorMinutes(bedtimeMinutes: Int, offsetMinutes: Int) -> Int {
        (((bedtimeMinutes - offsetMinutes) % 1440) + 1440) % 1440
    }

    /// Rule 10: the day a routine at `date` belongs to; between 00:00 and 03:59 that is the day before.
    public static func routineDay(at date: Date, calendar: Calendar) -> PlanDay {
        let today = PlanDay(date: date, calendar: calendar)
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return minutes < eveningBoundaryMinutes ? today.adding(days: -1, calendar: calendar) : today
    }

    /// Which routine a single entry point ("Tagesroutine" control, #167) opens at `date`: the morning start from 04:00
    /// to 11:59 (the span of the morning card, rule 11), the evening wrap-up otherwise. Between 00:00 and 03:59 that is
    /// still the evening of the day before (rule 10; `routineDay` names the day).
    public static func currentRoutine(at date: Date, calendar: Calendar) -> AppRoute {
        let minutes = minutesOfDay(date, calendar: calendar)
        return minutes >= eveningBoundaryMinutes && minutes < morningCardEndMinutes ? .routineStart : .routineEvening
    }

    /// Minutes since midnight of `date`.
    public static func minutesOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Rule 11: the morning card from 04:00 to 12:00 while the start is neither completed nor dismissed.
    public static func showsMorningCard(minutesOfDay: Int, completed: Bool, dismissed: Bool) -> Bool {
        !completed && !dismissed && minutesOfDay >= eveningBoundaryMinutes && minutesOfDay < morningCardEndMinutes
    }

    /// Rule 11: the evening line from the earliest anchor (without anchors 90 minutes before bedtime) to 03:59.
    public static func showsEveningLine(minutesOfDay: Int, bedtimeMinutes: Int, offsets: [Int]) -> Bool {
        let lead = offsets.max() ?? fallbackEveningLeadMinutes
        let start = anchorMinutes(bedtimeMinutes: bedtimeMinutes, offsetMinutes: lead)
        if start < eveningBoundaryMinutes { return minutesOfDay >= start && minutesOfDay < eveningBoundaryMinutes }
        return minutesOfDay >= start || minutesOfDay < eveningBoundaryMinutes
    }

    /// The points that remind: the first four with an offset, by order.
    public static func reminderItems(_ items: [ChecklistItem]) -> [ChecklistItem] {
        Array(items.sorted { $0.order < $1.order }.filter { $0.offsetMinutes != nil }.prefix(maximumReminders))
    }

    /// The identifier of one evening reminder: the point and the routine day it is planned for.
    public static func eveningIdentifier(item: UUID, day: PlanDay) -> String {
        "\(PlannedNotification.routineIdentifierPrefix)evening.\(item.uuidString).\(day.dayKey)"
    }

    /// One reminder per checklist point with an offset (at most four, design §8.1) and per routine day, beginning with the
    /// routine day of `now` and covering `days` routine days, sorted by the moment they fire. Title is the name of the
    /// point, the text counts down to the bedtime. Left out: points that are checked on that routine day (`checked`) and
    /// moments that are not after `now`. An anchor before 04:00 lies on the calendar day after its routine day (rule 10),
    /// so a point checked in the evening is also quiet after midnight. Whether the wrap-up was completed does not matter:
    /// open points keep reminding (decision D11). Texts and clock follow `locale`; evening reminders are exempt from the
    /// quiet hours (decision D10).
    public static func eveningNotifications(items: [ChecklistItem], bedtimeMinutes: Int, enabled: Bool,
                                            checked: (PlanDay) -> Set<UUID>, now: Date, calendar: Calendar,
                                            locale: Locale, days: Int = eveningHorizonDays) -> [DatedRoutineNotification] {
        guard enabled, days > 0 else { return [] }
        let points = reminderItems(items)
        guard !points.isEmpty else { return [] }
        let language = VoiceLanguage.from(locale: locale)
        let bedtime = DateText.time(minutes: bedtimeMinutes, calendar: calendar, locale: locale)
        let firstDay = routineDay(at: now, calendar: calendar)
        var planned: [(moment: Date, order: Int, notification: DatedRoutineNotification)] = []
        for offsetDay in 0..<days {
            let routineDay = firstDay.adding(days: offsetDay, calendar: calendar)
            let checkedToday = checked(routineDay)
            for (order, item) in points.enumerated() {
                guard let offset = item.offsetMinutes, !checkedToday.contains(item.id) else { continue }
                let anchor = anchorMinutes(bedtimeMinutes: bedtimeMinutes, offsetMinutes: offset)
                let calendarDay = anchor < eveningBoundaryMinutes ? routineDay.adding(days: 1, calendar: calendar) : routineDay
                let moment = calendar.date(from: DateComponents(year: calendarDay.year, month: calendarDay.month, day: calendarDay.day,
                                                                hour: anchor / 60, minute: anchor % 60))
                guard let moment, moment > now else { continue }
                let body = offset == 0
                    ? Localized.string("Schlafzeit (\(bedtime))", in: language, bundle: .module)
                    : Localized.string("Noch \(offset) min bis zur Schlafzeit (\(bedtime))", in: language, bundle: .module)
                planned.append((moment, order, DatedRoutineNotification(
                    id: eveningIdentifier(item: item.id, day: routineDay), year: calendarDay.year, month: calendarDay.month,
                    day: calendarDay.day, hour: anchor / 60, minute: anchor % 60, title: item.title, body: body, route: .routineEvening)))
            }
        }
        return planned.sorted { ($0.moment, $0.order) < ($1.moment, $1.order) }.map(\.notification)
    }

    /// The optional reminder to start the day; `nil` while switched off (design §8.1).
    public static func morningNotification(enabled: Bool, minutes: Int, locale: Locale) -> RoutineNotification? {
        guard enabled else { return nil }
        let language = VoiceLanguage.from(locale: locale)
        let clamped = ((minutes % 1440) + 1440) % 1440
        return RoutineNotification(id: "\(PlannedNotification.routineIdentifierPrefix)morning", hour: clamped / 60, minute: clamped % 60,
                                   title: Localized.string("Tagesstart", in: language, bundle: .module),
                                   body: Localized.string("Ein ruhiger Start in den Tag?", in: language, bundle: .module), route: .routineStart)
    }

    /// The optional weekly reminder for the weekly planning (#164); `nil` while switched off. `weekday` counts like
    /// `Calendar` (1 = Sunday), `minutes` since midnight.
    public static func weekPlanningNotification(enabled: Bool, weekday: Int, minutes: Int, locale: Locale) -> RoutineNotification? {
        guard enabled else { return nil }
        let language = VoiceLanguage.from(locale: locale)
        let clamped = ((minutes % 1440) + 1440) % 1440
        let day = min(7, max(1, weekday))
        return RoutineNotification(id: "\(PlannedNotification.routineIdentifierPrefix)week", hour: clamped / 60, minute: clamped % 60,
                                   title: Localized.string("Wochenplanung", in: language, bundle: .module),
                                   body: Localized.string("5 Minuten für die neue Woche?", in: language, bundle: .module),
                                   route: .routineWeek, weekday: day)
    }

    /// Which routine reminders sit inside the quiet hours. They are exempt (plan quiet-hours, decision 4): the settings
    /// say so instead of moving them.
    public static func quietHoursConflict(_ quietHours: QuietHours?, items: [ChecklistItem], bedtimeMinutes: Int,
                                          eveningEnabled: Bool, morningEnabled: Bool, morningMinutes: Int,
                                          weekEnabled: Bool = false, weekMinutes: Int = 0) -> QuietHoursConflict {
        guard let quietHours else { return QuietHoursConflict(evening: false, morning: false) }
        let evening = eveningEnabled && reminderItems(items).contains { item in
            item.offsetMinutes.map { quietHours.contains(minutes: anchorMinutes(bedtimeMinutes: bedtimeMinutes, offsetMinutes: $0)) } ?? false
        }
        return QuietHoursConflict(evening: evening, morning: morningEnabled && quietHours.contains(minutes: morningMinutes),
                                  week: weekEnabled && quietHours.contains(minutes: weekMinutes))
    }

    /// Checked points that still exist; ids of deleted points are ignored.
    public static func checkedCount(_ day: RoutineDayValue, items: [ChecklistItem]) -> Int {
        items.filter { day.checkedItemIDs.contains($0.id) }.count
    }
}

/// Routine reminders that fall inside the quiet hours.
public struct QuietHoursConflict: Equatable, Sendable {
    public let evening: Bool
    public let morning: Bool
    public let week: Bool

    public init(evening: Bool, morning: Bool, week: Bool = false) {
        self.evening = evening
        self.morning = morning
        self.week = week
    }

    public var isEmpty: Bool { !evening && !morning && !week }
}

/// Rules of the daily focus (phase 7 design §6, rule 12).
public enum FocusRules {
    public static let maximumMarks = 3

    /// Open tasks of `today`: planned for that day, due that day or with a time block that day; recurring occurrences
    /// are left out. Sorted: priority 1 and tasks due that day first, then the usual order of `sortedTasks`.
    public static func candidates(_ tasks: [TaskItem], plannedToday: Set<TaskID>, blockedToday: Set<TaskID>,
                                  recurring: Set<TaskID>, today: PlanDay, calendar: Calendar) -> [TaskItem] {
        func isDueToday(_ task: TaskItem) -> Bool { task.due.map { PlanDay($0) == today } ?? false }
        let chosen = tasks.filter { task in
            !task.isCompleted && !recurring.contains(task.id)
                && (plannedToday.contains(task.id) || blockedToday.contains(task.id) || isDueToday(task))
        }
        let sorted = sortedTasks(chosen, calendar: calendar)
        let urgent = sorted.filter { $0.priority == .p1 || isDueToday($0) }
        let rest = sorted.filter { !($0.priority == .p1 || isDueToday($0)) }
        return urgent + rest
    }
}
