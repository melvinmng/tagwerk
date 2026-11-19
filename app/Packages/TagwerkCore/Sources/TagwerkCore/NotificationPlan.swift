import Foundation

/// A local notification Tagwerk wants to have pending (design 2b §9, Phase 2 §8).
public struct PlannedNotification: Sendable, Hashable, Identifiable {
    /// What a tap on the notification opens.
    public enum Target: Sendable, Hashable {
        case task(TaskID)
        case event(id: String, day: PlanDay)
    }

    /// Stable identifier: "tagwerk.task.<task key>#<n>" or "tagwerk.event.<event id>#<n>"; `n` is the position of the
    /// reminder in the sorted reminder list of the entry (plan P4).
    public let id: String
    public let fireDate: Date
    public let title: String
    public let body: String
    public let target: Target
    /// Source of the task; `nil` for deadline calendar events.
    public let source: TaskSource?

    /// Prefix of every notification identifier Tagwerk owns.
    public static let identifierPrefix = "tagwerk."

    public static func identifier(for task: TaskID, index: Int = 0) -> String { "\(taskIdentifierPrefix)\(task.key)#\(index)" }
    public static func identifier(forEvent id: String, index: Int = 0) -> String { "\(eventIdentifierPrefix)\(id)#\(index)" }

    /// Identifier prefix of all task notifications of one source.
    public static func identifierPrefix(for source: TaskSource) -> String { "\(identifierPrefix)task.\(source.rawValue):" }
    public static let taskIdentifierPrefix = "\(identifierPrefix)task."
    public static let eventIdentifierPrefix = "\(identifierPrefix)event."

    /// Whether a pending notification is one of the task and deadline notifications that the rolling plan owns. Other
    /// features use their own prefixes ("tagwerk.routine.", "tagwerk.focus.") and are neither counted nor removed.
    public static func isBudgeted(_ id: String) -> Bool {
        id.hasPrefix(taskIdentifierPrefix) || id.hasPrefix(eventIdentifierPrefix)
    }
    /// Identifier prefix of the repeating routine reminders (phase 7). They live next to the deadline notifications and
    /// are neither counted against their budget nor removed by it.
    public static let routineIdentifierPrefix = "\(identifierPrefix)routine."
}

/// Settings that shape the notification plan.
public struct NotificationRules: Sendable, Hashable {
    public var leadTimeMinutes: Int
    public var includesDeadlineCalendars: Bool
    /// Task sources that get notifications; each has its own switch in the settings.
    public var taskSources: Set<TaskSource>
    /// At most this many pending notifications (iOS keeps 64; see `NotificationBudget`).
    public var limit: Int
    /// Hour on the due day at which a task without time reminds, without lead time (a morning heads-up).
    public var dateOnlyHour: Int
    /// Hour on the evening before at which an all-day deadline event reminds.
    public var allDayEventHour: Int
    /// Notifications must fire at least this long after `now`; earlier ones are skipped.
    public var minimumDelay: TimeInterval
    /// Daily window in which task and deadline notifications are moved to the window end instead of firing; `nil` is off.
    public var quietHours: QuietHours?
    /// While a Focus filter holds notifications back: those that would fire inside it move to its end.
    public var focusHold: FocusHold?
    /// After a Focus filter ended: notifications that came due while it held them back fire once at its `at`.
    public var focusCatchUp: FocusCatchUp?

    /// Reminders of entries without a list of their own; `nil` means the legacy rules from `leadTimeMinutes`,
    /// `dateOnlyHour` and `allDayEventHour` (the behaviour before reminders became flexible).
    public var defaults: ReminderDefaults?
    /// Lists that replace the defaults, by `ReminderOverride.itemKey`.
    public var overrides: [String: [ReminderOverride]]
    /// Series identifier of recurring deadline occurrences, by occurrence ID; other events are their own series.
    public var seriesKey: [String: String]

    /// The defaults in effect.
    var effectiveDefaults: ReminderDefaults {
        defaults ?? .legacy(leadTimeMinutes: leadTimeMinutes, dateOnlyHour: dateOnlyHour, allDayEventHour: allDayEventHour)
    }

    /// Margin before a new notification may fire.
    public static let defaultMinimumDelay: TimeInterval = 60

    public init(leadTimeMinutes: Int, includesDeadlineCalendars: Bool,
                taskSources: Set<TaskSource> = Set(TaskSource.allCases), limit: Int = NotificationBudget.tasksAndDeadlines,
                dateOnlyHour: Int = 9, allDayEventHour: Int = 18, minimumDelay: TimeInterval = defaultMinimumDelay,
                quietHours: QuietHours? = nil, focusHold: FocusHold? = nil, focusCatchUp: FocusCatchUp? = nil,
                defaults: ReminderDefaults? = nil, overrides: [String: [ReminderOverride]] = [:],
                seriesKey: [String: String] = [:]) {
        self.defaults = defaults
        self.overrides = overrides
        self.seriesKey = seriesKey
        self.leadTimeMinutes = leadTimeMinutes
        self.includesDeadlineCalendars = includesDeadlineCalendars
        self.taskSources = taskSources
        self.limit = limit
        self.dateOnlyHour = dateOnlyHour
        self.allDayEventHour = allDayEventHour
        self.minimumDelay = minimumDelay
        self.quietHours = quietHours
        self.focusHold = focusHold
        self.focusCatchUp = focusCatchUp
    }

    /// When a notification that would fire at `fire` is delivered: caught up after a Focus filter, held back while one
    /// is active, and finally moved out of the quiet hours. Unchanged when none of the three applies.
    func deliveryDate(for fire: Date, calendar: Calendar) -> Date {
        var delivery = fire
        if let catchUp = focusCatchUp, delivery >= catchUp.from, delivery < catchUp.at { delivery = catchUp.at }
        if let hold = focusHold, delivery >= hold.from, delivery < hold.until { delivery = hold.until }
        if let quietHours { delivery = quietHours.shifted(delivery, calendar: calendar) }
        return delivery
    }
}

/// The planned notifications and how many more were wanted than `rules.limit` allows.
public struct NotificationPlanResult: Sendable, Hashable {
    public var notifications: [PlannedNotification]
    /// Wanted notifications that did not fit the limit; they follow when earlier ones have fired.
    public var omittedCount: Int
}

/// Notifications for open tasks with a due date from the enabled sources and, if enabled, for deadline calendar
/// events. Every entry can have several reminders (defaults per kind, replaced by its own list). Reminders are included
/// on purpose: the Reminders app only alerts at the due moment, if at all. The result holds the earliest
/// `rules.limit` notifications that fire at least `rules.minimumDelay` after `now`, ordered by fire date. Texts and formats follow `locale`.
public func notificationPlan(tasks: [TaskItem], deadlineEvents: [CalendarEvent], rules: NotificationRules,
                             now: Date, calendar: Calendar, locale: Locale = .current) -> [PlannedNotification] {
    notificationPlanResult(tasks: tasks, deadlineEvents: deadlineEvents, rules: rules, now: now, calendar: calendar,
                           locale: locale).notifications
}

/// Like `notificationPlan`, and also reports how many wanted notifications were left out by the limit.
public func notificationPlanResult(tasks: [TaskItem], deadlineEvents: [CalendarEvent], rules: NotificationRules,
                                   now: Date, calendar: Calendar, locale: Locale = .current) -> NotificationPlanResult {
    let earliest = now.addingTimeInterval(rules.minimumDelay)
    let texts = NotificationTexts(calendar: calendar, locale: locale)
    let defaults = rules.effectiveDefaults
    var result: [PlannedNotification] = []

    /// The moments an entry's reminders are delivered at: each offset moved out of quiet hours and Focus, at least
    /// `earliest`, and only the first of several that end up in the same minute.
    func deliveries(_ offsets: [ReminderOffset], anchor: Date, isAllDay: Bool) -> [(index: Int, fire: Date)] {
        var minutes = Set<Int>()
        var found: [(index: Int, fire: Date)] = []
        for (index, offset) in offsets.enumerated() {
            guard let original = offset.fireDate(anchor: anchor, isAllDay: isAllDay, calendar: calendar) else { continue }
            // Moved before the check: a notification that was due during the quiet hours is still wanted after they began.
            let fire = rules.deliveryDate(for: original, calendar: calendar)
            guard fire >= earliest, minutes.insert(Int(fire.timeIntervalSince1970 / 60)).inserted else { continue }
            found.append((index, fire))
        }
        return found
    }

    for task in tasks where !task.isCompleted && rules.taskSources.contains(task.id.source) {
        guard let due = task.due else { continue }
        // A due date without time has its day as anchor; its reminders are "N days before" or at a time of day.
        let isAllDay = !due.hasTime
        let anchor = due.startDate(in: calendar)
        let resolved = ReminderOverrideResolution.resolve(
            itemKey: ReminderOverride.key(task: task.id), due: due, isAllDay: isAllDay, overrides: rules.overrides,
            defaults: defaults.offsets(for: .forTask(source: task.id.source), isAllDay: isAllDay))
        // Alarms written to the Reminders app: iOS fires them, Tagwerk adds none of its own.
        guard resolved.storage == .tagwerk else { continue }
        let time = due.hasTime ? anchor : nil
        let dueDay = PlanDay(due)
        for (index, fire) in deliveries(resolved.offsets, anchor: anchor, isAllDay: isAllDay) {
            let isOverdue = texts.isOverdue(day: dueDay, time: time, fire: fire)
            result.append(PlannedNotification(
                id: PlannedNotification.identifier(for: task.id, index: index), fireDate: fire, title: texts.title(task.title),
                body: texts.taskBody(dueDay: dueDay, time: time, fire: fire, container: task.container.name, overdue: isOverdue),
                target: .task(task.id), source: task.id.source))
        }
    }

    if rules.includesDeadlineCalendars {
        var seen = Set<String>()
        for event in deadlineEvents where seen.insert(event.id).inserted {
            let day = PlanDay(date: event.start, calendar: calendar)
            let resolved = ReminderOverrideResolution.resolve(
                itemKey: ReminderOverride.key(deadlineSeries: rules.seriesKey[event.id] ?? event.id), occurrenceID: event.id,
                day: day, isAllDay: event.isAllDay, overrides: rules.overrides,
                defaults: defaults.offsets(for: .deadline, isAllDay: event.isAllDay))
            guard resolved.storage == .tagwerk else { continue }
            let time = event.isAllDay ? nil : event.start
            for (index, fire) in deliveries(resolved.offsets, anchor: event.start, isAllDay: event.isAllDay) {
                result.append(PlannedNotification(
                    id: PlannedNotification.identifier(forEvent: event.id, index: index), fireDate: fire, title: texts.title(event.title),
                    body: texts.eventBody(day: day, time: time, fire: fire, overdue: texts.isOverdue(day: day, time: time, fire: fire)),
                    target: .event(id: event.id, day: day), source: nil))
            }
        }
    }

    let sorted = result.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
    return NotificationPlanResult(notifications: Array(sorted.prefix(rules.limit)), omittedCount: max(0, sorted.count - rules.limit))
}

/// Notification texts, relative to the day the notification fires, in the language of `locale`.
private struct NotificationTexts {
    let calendar: Calendar
    let locale: Locale

    private var language: VoiceLanguage { .from(locale: locale) }

    private func text(_ key: String.LocalizationValue) -> String { Localized.string(key, in: language, bundle: .module) }

    func title(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? text("Ohne Titel") : trimmed
    }

    /// A notification moved past its due moment (quiet hours, Focus): a timed one after the time, one for a whole day
    /// from the day after.
    func isOverdue(day: PlanDay, time: Date?, fire: Date) -> Bool {
        if let time { return fire > time }
        return PlanDay(date: fire, calendar: calendar) > day
    }

    func taskBody(dueDay: PlanDay, time: Date?, fire: Date, container: String, overdue: Bool = false) -> String {
        let moment = moment(day: dueDay, time: time, fire: fire)
        return overdue ? text("War fällig \(moment) · \(container)") : text("Fällig \(moment) · \(container)")
    }

    func eventBody(day: PlanDay, time: Date?, fire: Date, overdue: Bool = false) -> String {
        if time == nil {
            let dayPart = dayText(day, fire: fire)
            return overdue ? text("Deadline war \(dayPart), ganztägig") : text("Deadline \(dayPart), ganztägig")
        }
        let moment = moment(day: day, time: time, fire: fire)
        return overdue ? text("Deadline war \(moment)") : text("Deadline \(moment)")
    }

    private func moment(day: PlanDay, time: Date?, fire: Date) -> String {
        let dayPart = dayText(day, fire: fire)
        guard let time else { return dayPart }
        let clock = DateText.time(time, calendar: calendar, locale: locale)
        return text("\(dayPart) um \(clock)")
    }

    private func dayText(_ day: PlanDay, fire: Date) -> String {
        let fireDay = PlanDay(date: fire, calendar: calendar)
        if day == fireDay { return text("heute") }
        if day == fireDay.adding(days: 1, calendar: calendar) { return text("morgen") }
        if day == fireDay.adding(days: -1, calendar: calendar) { return text("gestern") }
        let weekday = DateText.shortWeekday(day, calendar: calendar, locale: locale)
        let date = DateText.numericDay(day, calendar: calendar, locale: locale)
        return text("am \(weekday), \(date)")
    }
}
