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

/// A reminder of the routines that repeats every day at the same time (phase 7 design §8.1). The texts are static.
public struct RoutineNotification: Sendable, Hashable, Identifiable {
    /// "tagwerk.routine.evening.<UUID>" or "tagwerk.routine.morning".
    public var id: String
    public var hour: Int
    public var minute: Int
    public var title: String
    public var body: String
    /// What a tap opens; carried in the notification as the link path.
    public var route: AppRoute

    public init(id: String, hour: Int, minute: Int, title: String, body: String, route: AppRoute) {
        self.id = id
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
    public static let offsetRange = 0...240
    public static let offsetStep = 5
    public static let titleLimit = 40

    /// The checklist offered for an empty list (design §11): 90, 60 and 30 minutes before bedtime. Read at the time of
    /// adoption, so the titles follow the app language of that moment.
    public static var suggestedItems: [(title: String, offsetMinutes: Int)] {
        [(String(localized: "Tagesabschluss öffnen", bundle: .module), 90),
         (String(localized: "Handy weglegen", bundle: .module), 60),
         (String(localized: "Ins Bett", bundle: .module), 30)]
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

    /// One daily reminder per checklist point with an offset, at most four (design §8.1). Title is the name of the point,
    /// the text counts down to the bedtime. Texts and clock follow `locale`; nothing here depends on today's data.
    public static func eveningNotifications(items: [ChecklistItem], bedtimeMinutes: Int, enabled: Bool, locale: Locale,
                                            calendar: Calendar = Calendar(identifier: .gregorian)) -> [RoutineNotification] {
        guard enabled else { return [] }
        let language = VoiceLanguage.from(locale: locale)
        let bedtime = DateText.time(minutes: bedtimeMinutes, calendar: calendar, locale: locale)
        return reminderItems(items).compactMap { item in
            guard let offset = item.offsetMinutes else { return nil }
            let anchor = anchorMinutes(bedtimeMinutes: bedtimeMinutes, offsetMinutes: offset)
            let body = offset == 0
                ? Localized.string("Schlafzeit (\(bedtime))", in: language, bundle: .module)
                : Localized.string("Noch \(offset) min bis zur Schlafzeit (\(bedtime))", in: language, bundle: .module)
            return RoutineNotification(id: "\(PlannedNotification.routineIdentifierPrefix)evening.\(item.id.uuidString)",
                                       hour: anchor / 60, minute: anchor % 60, title: item.title, body: body, route: .routineEvening)
        }
    }

    /// Checked points that still exist; ids of deleted points are ignored.
    public static func checkedCount(_ day: RoutineDayValue, items: [ChecklistItem]) -> Int {
        items.filter { day.checkedItemIDs.contains($0.id) }.count
    }
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
