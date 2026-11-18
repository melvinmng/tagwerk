import Foundation

/// A local notification Tagwerk wants to have pending (design 2b §9, Phase 2 §8).
public struct PlannedNotification: Sendable, Hashable, Identifiable {
    /// What a tap on the notification opens.
    public enum Target: Sendable, Hashable {
        case task(TaskID)
        case event(id: String, day: PlanDay)
    }

    /// Stable identifier: "tagwerk.task.<task key>" or "tagwerk.event.<event id>".
    public let id: String
    public let fireDate: Date
    public let title: String
    public let body: String
    public let target: Target
    /// Source of the task; `nil` for deadline calendar events.
    public let source: TaskSource?

    /// Prefix of every notification identifier Tagwerk owns.
    public static let identifierPrefix = "tagwerk."

    public static func identifier(for task: TaskID) -> String { "\(identifierPrefix)task.\(task.key)" }
    public static func identifier(forEvent id: String) -> String { "\(identifierPrefix)event.\(id)" }

    /// Identifier prefix of all task notifications of one source.
    public static func identifierPrefix(for source: TaskSource) -> String { "\(identifierPrefix)task.\(source.rawValue):" }
    public static let eventIdentifierPrefix = "\(identifierPrefix)event."
}

/// Settings that shape the notification plan.
public struct NotificationRules: Sendable, Hashable {
    public var leadTimeMinutes: Int
    public var includesDeadlineCalendars: Bool
    /// Task sources that get notifications; each has its own switch in the settings.
    public var taskSources: Set<TaskSource>
    /// At most this many pending notifications (iOS keeps 64).
    public var limit: Int
    /// Hour on the due day at which a task without time reminds, without lead time (a morning heads-up).
    public var dateOnlyHour: Int
    /// Hour on the evening before at which an all-day deadline event reminds.
    public var allDayEventHour: Int
    /// Notifications must fire at least this long after `now`; earlier ones are skipped.
    public var minimumDelay: TimeInterval

    /// Margin before a new notification may fire.
    public static let defaultMinimumDelay: TimeInterval = 60

    public init(leadTimeMinutes: Int, includesDeadlineCalendars: Bool,
                taskSources: Set<TaskSource> = Set(TaskSource.allCases), limit: Int = 50, dateOnlyHour: Int = 9,
                allDayEventHour: Int = 18, minimumDelay: TimeInterval = defaultMinimumDelay) {
        self.leadTimeMinutes = leadTimeMinutes
        self.includesDeadlineCalendars = includesDeadlineCalendars
        self.taskSources = taskSources
        self.limit = limit
        self.dateOnlyHour = dateOnlyHour
        self.allDayEventHour = allDayEventHour
        self.minimumDelay = minimumDelay
    }
}

/// Notifications for open tasks with a due date from the enabled sources and, if enabled, for deadline calendar
/// events. Reminders are included on purpose: the Reminders app only alerts at the due moment, if at all. The result holds the earliest
/// `rules.limit` notifications that fire at least `rules.minimumDelay` after `now`, ordered by fire date. Texts and formats follow `locale`.
public func notificationPlan(tasks: [TaskItem], deadlineEvents: [CalendarEvent], rules: NotificationRules,
                             now: Date, calendar: Calendar, locale: Locale = .current) -> [PlannedNotification] {
    let earliest = now.addingTimeInterval(rules.minimumDelay)
    let texts = NotificationTexts(calendar: calendar, locale: locale)
    var result: [PlannedNotification] = []

    for task in tasks where !task.isCompleted && rules.taskSources.contains(task.id.source) {
        guard let due = task.due else { continue }
        var parts = due.dayComponents()
        parts.hour = due.hour ?? rules.dateOnlyHour
        parts.minute = due.minute ?? 0
        // A due date without time reminds on the morning of the due day; the lead time applies to timed ones only.
        guard let dueMoment = calendar.date(from: parts),
              let fire = due.hasTime ? calendar.date(byAdding: .minute, value: -rules.leadTimeMinutes, to: dueMoment) : dueMoment,
              fire >= earliest else { continue }
        let time = due.hasTime ? dueMoment : nil
        result.append(PlannedNotification(
            id: PlannedNotification.identifier(for: task.id), fireDate: fire, title: texts.title(task.title),
            body: texts.taskBody(dueDay: PlanDay(due), time: time, fire: fire, container: task.container.name),
            target: .task(task.id), source: task.id.source))
    }

    if rules.includesDeadlineCalendars {
        var seen = Set<String>()
        for event in deadlineEvents where seen.insert(event.id).inserted {
            let day = PlanDay(date: event.start, calendar: calendar)
            let fire: Date?
            if event.isAllDay {
                // All-day deadlines remind on the evening before, without lead time (design 2b §11.13).
                var parts = day.adding(days: -1, calendar: calendar).startDate(in: calendar).components(in: calendar)
                parts.hour = rules.allDayEventHour
                parts.minute = 0
                fire = calendar.date(from: parts)
            } else {
                fire = calendar.date(byAdding: .minute, value: -rules.leadTimeMinutes, to: event.start)
            }
            guard let fire, fire >= earliest else { continue }
            result.append(PlannedNotification(
                id: PlannedNotification.identifier(forEvent: event.id), fireDate: fire, title: texts.title(event.title),
                body: texts.eventBody(day: day, time: event.isAllDay ? nil : event.start, fire: fire),
                target: .event(id: event.id, day: day), source: nil))
        }
    }

    return Array(result.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }.prefix(rules.limit))
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

    func taskBody(dueDay: PlanDay, time: Date?, fire: Date, container: String) -> String {
        let moment = moment(day: dueDay, time: time, fire: fire)
        return text("Fällig \(moment) · \(container)")
    }

    func eventBody(day: PlanDay, time: Date?, fire: Date) -> String {
        if time == nil {
            let dayPart = dayText(day, fire: fire)
            return text("Deadline \(dayPart), ganztägig")
        }
        let moment = moment(day: day, time: time, fire: fire)
        return text("Deadline \(moment)")
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
        let weekday = DateText.shortWeekday(day, calendar: calendar, locale: locale)
        let date = DateText.numericDay(day, calendar: calendar, locale: locale)
        return text("am \(weekday), \(date)")
    }
}

private extension Date {
    func components(in calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.year, .month, .day], from: self)
    }
}
