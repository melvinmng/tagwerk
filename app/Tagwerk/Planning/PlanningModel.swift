import Foundation
import Observation
import RemindersKit
import TagwerkCore

enum PlanScope: String, CaseIterable, Hashable {
    case day, week, month

    var title: String {
        switch self {
        case .day: "Tag"
        case .week: "Woche"
        case .month: "Monat"
        }
    }
}

/// Effort a recurring reminder reserves on one day.
struct RecurringItem: Hashable, Identifiable {
    var id: String { reminderID }
    let reminderID: String
    let title: String
    let minutes: Int
    /// Completed in Tagwerk on this day: the effort no longer reserves time.
    var isDone = false
}

/// One row of the day timeline, in time order.
enum TimelineRow: Identifiable, Equatable {
    case event(CalendarEvent)
    case block(CalendarEvent, TaskID)
    case lunch(startMinutes: Int, minutes: Int)

    var id: String {
        switch self {
        case .event(let event), .block(let event, _): event.id
        case .lunch: "lunch"
        }
    }

    var label: String {
        switch self {
        case .event(let event), .block(let event, _): event.title
        case .lunch: "Mittagspause"
        }
    }
}

/// Everything one day shows in the planning views.
struct DayPlan: Identifiable, Equatable {
    var id: PlanDay { day }
    let day: PlanDay
    let capacity: DayCapacity
    let deadlines: [ImportantDeadline]
    /// Events of the day that are not linked to a task.
    let events: [CalendarEvent]
    /// Events linked to a task (own blocks and recognised or manual links).
    let blocks: [CalendarEvent]
    /// Tasks planned for this day (day assignment).
    let assigned: [TaskItem]
    /// Today only: open tasks due today without a planned day or block; they count as load (design §13.9).
    let dueToday: [TaskItem]
    /// Event ID → task for `blocks`.
    let links: [String: TaskID]
    /// Assigned tasks whose planned day lies after their due date.
    let isPastDue: Set<TaskID>
    /// Recurring effort reserved on this day.
    let recurring: [RecurringItem]
    /// The day lies before today.
    let isPast: Bool
}

/// Moving a task with future time blocks needs a decision: move the blocks along or delete them.
struct PendingBlockDecision: Equatable {
    let taskID: TaskID
    let day: PlanDay
}

/// State of the planning tab: capacity, deadlines, assignments and blocks for day, week or month.
@MainActor
@Observable
final class PlanningModel {
    var scope: PlanScope = .day
    var anchor: PlanDay
    private(set) var days: [DayPlan] = []
    private(set) var unplanned: [TaskItem] = []
    /// Open tasks planned before today or due before today without a planned day; not counted as load until
    /// they are moved to a day (design §13.9).
    private(set) var overdue: [TaskItem] = []
    /// Important deadlines from the anchor day over the next 14 days (deadline card of the day view).
    private(set) var upcomingDeadlines: [ImportantDeadline] = []
    /// Reminder IDs with a repetition rule (for "Aufwand ändern …").
    private(set) var recurringReminderIDs: Set<String> = []
    private var resolvedLinks: [String: ResolvedLink] = [:]
    private(set) var pendingBlockDecision: PendingBlockDecision?
    private(set) var lastError: String?

    let taskList: TaskListModel
    private let calendarStore: CalendarStore
    private let reminderStore: ReminderStore
    let planStore: PlanStore
    let efforts: RecurringEffortStore
    let blocks: BlockPlanner
    private let settings: AppSettings
    let now: () -> Date
    let calendar: Calendar

    init(taskList: TaskListModel, calendarStore: CalendarStore, reminderStore: ReminderStore, planStore: PlanStore,
         efforts: RecurringEffortStore, blocks: BlockPlanner, settings: AppSettings,
         now: @escaping () -> Date = Date.init, calendar: Calendar = .tagwerk) {
        self.taskList = taskList
        self.calendarStore = calendarStore
        self.reminderStore = reminderStore
        self.planStore = planStore
        self.efforts = efforts
        self.blocks = blocks
        self.settings = settings
        self.now = now
        self.calendar = calendar
        self.anchor = PlanDay(date: now(), calendar: calendar)
    }

    var today: PlanDay { PlanDay(date: now(), calendar: calendar) }

    /// Day: the anchor; week: Monday–Sunday around it; month: full weeks covering its month.
    var range: ClosedRange<PlanDay> {
        switch scope {
        case .day:
            return anchor...anchor
        case .week:
            let start = weekStart(of: anchor)
            return start...start.adding(days: 6, calendar: calendar)
        case .month:
            let first = PlanDay(year: anchor.year, month: anchor.month, day: 1)
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: first.startDate(in: calendar)) ?? first.startDate(in: calendar)
            let last = PlanDay(date: nextMonth, calendar: calendar).adding(days: -1, calendar: calendar)
            return weekStart(of: first)...weekStart(of: last).adding(days: 6, calendar: calendar)
        }
    }

    func reload() async {
        let range = self.range
        let open = taskList.items.filter { !$0.isCompleted }
        pruneAssignments(open: open)

        let reminders = reminderStore.accessState == .fullAccess ? await reminderStore.openReminders(in: nil) : []
        let recurringIDs = Set(reminders.filter { $0.recurrence != nil }.map(\.id))
        let interval = DateInterval(start: range.lowerBound.startDate(in: calendar),
                                    end: range.upperBound.adding(days: 1, calendar: calendar).startDate(in: calendar))
        let events = calendarStore.events(in: interval, calendarIDs: readableCalendarIDs())
        let resolved = resolveLinks(events: events, tasks: open, manual: blocks.links.manualLinks())
        resolvedLinks = Dictionary(resolved.map { ($0.eventID, $0) }, uniquingKeysWith: { first, _ in first })
        recurringReminderIDs = recurringIDs
        let links = resolvedLinks.mapValues(\.taskID)
        let deadlines = importantDeadlines(tasks: open, events: events,
                                           deadlineCalendarIDs: Set(settings.deadlineCalendarIDs ?? []),
                                           in: range, calendar: calendar)
        let assignments = planStore.assignments(in: range)
        let overrides = planStore.overrides(in: range)
        let tasksByID = Dictionary(open.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let everything = PlanDay(year: 1, month: 1, day: 1)...PlanDay(year: 9999, month: 12, day: 31)
        let allAssignments = planStore.assignments(in: everything)

        var result: [DayPlan] = []
        var day = range.lowerBound
        while day <= range.upperBound {
            result.append(dayPlan(day, events: events, links: links, deadlines: deadlines, assignments: assignments,
                                  overrides: overrides, tasksByID: tasksByID, reminders: reminders,
                                  recurringIDs: recurringIDs, open: open, allAssignments: allAssignments))
            day = day.adding(days: 1, calendar: calendar)
        }
        days = result

        unplanned = open.filter { allAssignments[$0.id] == nil }
        upcomingDeadlines = loadUpcomingDeadlines(open: open)
        let today = self.today
        overdue = open.filter { task in
            if let planned = allAssignments[task.id] { return planned < today }
            return task.due.map { PlanDay($0) < today } ?? false
        }
        .sorted { lhs, rhs in
            let left = lhs.due.map(PlanDay.init), right = rhs.due.map(PlanDay.init)
            if left != right { return (left ?? PlanDay(year: 9999, month: 12, day: 31)) < (right ?? PlanDay(year: 9999, month: 12, day: 31)) }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    // MARK: Actions

    /// Plans `id` for `day` (Tagwerk only). Future time blocks require a decision first.
    func assign(_ id: TaskID, to day: PlanDay) async {
        if !blocks.futureBlocks(for: id, after: now()).isEmpty {
            pendingBlockDecision = PendingBlockDecision(taskID: id, day: day)
            return
        }
        planStore.assign(id, to: day)
        await reload()
    }

    /// Completes a pending `assign`: move future blocks to the new day or delete them.
    func resolveBlocks(move: Bool) async {
        guard let decision = pendingBlockDecision else { return }
        pendingBlockDecision = nil
        do {
            if move {
                try blocks.moveFutureBlocks(of: decision.taskID, to: decision.day, after: now())
            } else {
                try blocks.deleteFutureBlocks(of: decision.taskID, after: now())
            }
        } catch {
            lastError = TaskListModel.message(for: error)
        }
        planStore.assign(decision.taskID, to: decision.day)
        await reload()
    }

    /// "Einplanen: Heute / Morgen / …" – sets only the planned day, never the source's due date.
    func plan(_ id: TaskID, option: RescheduleOption) async {
        await assign(id, to: planDay(for: option))
    }

    func link(eventID: String, to taskID: TaskID) async {
        blocks.links.link(eventID: eventID, to: taskID)
        await reload()
    }

    func unlink(eventID: String) async {
        blocks.links.unlink(eventID: eventID)
        await reload()
    }

    func linkOrigin(eventID: String) -> LinkOrigin? {
        resolvedLinks[eventID]?.origin
    }

    func linkedTask(eventID: String) -> TaskItem? {
        resolvedLinks[eventID].flatMap { link in taskList.items.first { $0.id == link.taskID } }
    }

    /// "Nur dieser Tag" (`forAll == false`) or "Alle" from this day on.
    func setRecurringEffort(_ minutes: Int?, reminderID: String, day: PlanDay, forAll: Bool) async {
        if forAll {
            efforts.setForAll(minutes, reminderID: reminderID, from: day)
        } else {
            efforts.setForDay(minutes ?? 0, reminderID: reminderID, day: day)
        }
        await reload()
    }

    /// The recurring-effort entry of a reminder with a repetition rule on `day`; `nil` for other tasks.
    func recurringItem(for task: TaskItem, on day: PlanDay) -> RecurringItem? {
        guard task.id.source == .reminders, recurringReminderIDs.contains(task.id.rawValue) else { return nil }
        return RecurringItem(reminderID: task.id.rawValue, title: task.title,
                             minutes: efforts.minutes(for: task.id.rawValue, on: day) ?? 0)
    }

    /// Completing a recurring reminder in Tagwerk frees today's effort; reopening reserves it again (design §13.3).
    func didChangeCompletion(_ id: TaskID, isCompleted: Bool) async {
        guard id.source == .reminders, recurringReminderIDs.contains(id.rawValue) else { return }
        if isCompleted {
            efforts.markDone(reminderID: id.rawValue, day: today)
        } else {
            efforts.unmarkDone(reminderID: id.rawValue, day: today)
        }
        await reload()
    }

    /// Planned day and future blocks of a task, for the editor's "Geplant" section.
    func plannedInfo(for id: TaskID) -> (day: PlanDay?, blocks: [CalendarEvent]) {
        (planStore.assignment(for: id), blocks.futureBlocks(for: id, after: today.startDate(in: calendar)))
    }

    /// Writes a time block for `task` into the plan calendar (and plans the task for that day).
    func createBlock(for task: TaskItem, start: Date, minutes: Int) async {
        do {
            try blocks.createBlock(for: task, start: start, minutes: minutes)
        } catch {
            lastError = TaskListModel.message(for: error)
        }
        await reload()
    }

    /// Timed rows of a day: events, linked blocks and the lunch break, ordered by start time.
    func timeline(for plan: DayPlan) -> [TimelineRow] {
        let dayStart = plan.day.startDate(in: calendar)
        var rows: [(Int, TimelineRow)] = plan.events.filter { !$0.isAllDay }.map { (minutes($0.start, from: dayStart), .event($0)) }
        rows += plan.blocks.compactMap { block in plan.links[block.id].map { (minutes(block.start, from: dayStart), .block(block, $0)) } }
        if !plan.capacity.isDayOff, settings.lunchDurationMinutes > 0 {
            rows.append((settings.lunchStartMinutes, .lunch(startMinutes: settings.lunchStartMinutes, minutes: settings.lunchDurationMinutes)))
        }
        return rows.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// All-day events of the day; all-day events from deadline calendars appear as deadlines instead.
    func allDayEvents(for plan: DayPlan) -> [CalendarEvent] {
        let deadlineCalendars = Set(settings.deadlineCalendarIDs ?? [])
        return (plan.events + plan.blocks).filter { $0.isAllDay && !deadlineCalendars.contains($0.calendarID) }
    }

    // MARK: Events in all calendars (design §13.10)

    var writableCalendars: [ListInfo] { calendarStore.writableCalendars() }

    /// New events go to the plan calendar unless the user picks another one.
    var defaultEventCalendarID: String? { calendarStore.planCalendar(id: settings.planCalendarID)?.id }

    @discardableResult
    func createEvent(_ draft: EventDraft) async -> CalendarEvent? {
        var created: CalendarEvent?
        do {
            created = try calendarStore.createEvent(draft)
        } catch {
            lastError = TaskListModel.message(for: error)
        }
        await reload()
        return created
    }

    func updateEvent(_ event: CalendarEvent, with draft: EventDraft, span: EventSpan) async {
        do {
            _ = try calendarStore.updateEvent(id: event.id, with: draft, span: span, expectedVersion: event.version)
        } catch {
            lastError = TaskListModel.message(for: error)
        }
        await reload()
    }

    func deleteEvent(_ event: CalendarEvent, span: EventSpan) async {
        do {
            try calendarStore.deleteEvent(id: event.id, span: span, expectedVersion: event.version)
        } catch {
            lastError = TaskListModel.message(for: error)
        }
        await reload()
    }

    /// "Getrennt anzeigen": turns merging of identical events off (setting in "Einstellungen").
    func showDuplicatesSeparately() async {
        settings.mergeDuplicateEvents = false
        await reload()
    }

    func cancelBlockDecision() {
        pendingBlockDecision = nil
    }

    func unassign(_ id: TaskID) async {
        planStore.unassign(id)
        await reload()
    }

    func setDayOverride(_ value: DayOverride?, on day: PlanDay) {
        planStore.setOverride(value, on: day)
    }

    /// The day an "Einplanen" option stands for, using the same rules as rescheduling.
    func planDay(for option: RescheduleOption) -> PlanDay {
        PlanDay(rescheduled(nil, option: option, now: now(), calendar: calendar))
    }

    func workHours(on day: PlanDay) -> WorkHours? {
        TagwerkCore.workHours(on: day, schedule: settings.weekSchedule, overrides: planStore.overrides(in: day...day),
                              calendar: calendar)
    }

    func clearError() {
        lastError = nil
    }

    // MARK: Private

    private func dayPlan(_ day: PlanDay, events: [CalendarEvent], links: [String: TaskID], deadlines: [ImportantDeadline],
                         assignments: [TaskID: PlanDay], overrides: [PlanDay: DayOverride], tasksByID: [TaskID: TaskItem],
                         reminders: [ReminderRecord], recurringIDs: Set<String>, open: [TaskItem],
                         allAssignments: [TaskID: PlanDay]) -> DayPlan {
        let start = day.startDate(in: calendar)
        let end = day.adding(days: 1, calendar: calendar).startDate(in: calendar)
        let dayEvents = events.filter { $0.end > start && $0.start < end }.sorted { $0.start < $1.start }
        let linkedEvents = dayEvents.filter { links[$0.id] != nil && !$0.isAllDay }
        let tasksWithBlocks = Set(linkedEvents.compactMap { links[$0.id] })
        // Tasks with a time block on this day appear in the timeline only, not as "planned without time".
        let assigned = assignments.filter { $0.value == day && !tasksWithBlocks.contains($0.key) }
            .compactMap { tasksByID[$0.key] }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        let dueToday = day == today
            ? open.filter { task in
                allAssignments[task.id] == nil && !tasksWithBlocks.contains(task.id)
                    && task.due.map { PlanDay($0) == day } == true
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            : []

        var planned = linkedEvents.reduce(0) { total, event in
            let from = max(event.start, start), to = min(event.end, end)
            return total + max(0, Int(to.timeIntervalSince(from) / 60))
        }
        var estimated = 0
        for task in assigned + dueToday where !tasksWithBlocks.contains(task.id) {
            // Recurring reminders count once, through their recurring effort.
            if task.id.source == .reminders, recurringIDs.contains(task.id.rawValue) { continue }
            if let minutes = task.estimateMinutes {
                planned += minutes
            } else {
                planned += settings.defaultTaskMinutes
                estimated += 1
            }
        }
        var input = CapacityInput(
            hours: TagwerkCore.workHours(on: day, schedule: settings.weekSchedule, overrides: overrides, calendar: calendar),
            lunchStartMinutes: settings.lunchStartMinutes, lunchMinutes: settings.lunchDurationMinutes,
            bufferMinutes: settings.bufferMinutes,
            busyIntervals: busyIntervals(events: dayEvents, on: day, calendar: calendar, excluding: Set(links.keys)),
            recurringMinutes: efforts.reservedMinutes(on: day, reminders: reminders, calendar: calendar),
            plannedMinutes: planned, estimatedCount: estimated
        )
        if day == today {
            let current = now()
            input.nowMinutes = minutes(current, from: start)
            input.remainingPlannedMinutes = planned - linkedEvents.reduce(0) { total, event in
                let from = max(event.start, start), to = min(event.end, end, max(current, start))
                return total + max(0, Int(to.timeIntervalSince(from) / 60))
            }
        }
        let pastDue = Set(assigned.filter { task in task.due.map { PlanDay($0) < day } ?? false }.map(\.id))
        let recurring = reminders.compactMap { reminder -> RecurringItem? in
            guard let recurrence = reminder.recurrence,
                  !occurrences(of: recurrence, in: day...day, calendar: calendar).isEmpty,
                  let minutes = efforts.minutes(for: reminder.id, on: day), minutes > 0 else { return nil }
            return RecurringItem(reminderID: reminder.id, title: reminder.title, minutes: minutes,
                                 isDone: efforts.isDone(reminderID: reminder.id, day: day))
        }
        // Merging only affects the display; capacity above used every event (overlaps are unified).
        let shown = settings.mergeDuplicateEvents ? mergingDuplicates(dayEvents, links: links) : dayEvents
        return DayPlan(day: day, capacity: capacity(input), deadlines: deadlines.filter { $0.day == day },
                       events: shown.filter { links[$0.id] == nil }, blocks: shown.filter { links[$0.id] != nil && !$0.isAllDay },
                       assigned: assigned, dueToday: dueToday, links: links.filter { id, _ in linkedEvents.contains { $0.id == id } },
                       isPastDue: pastDue, recurring: recurring, isPast: day < today)
    }

    private func minutes(_ date: Date, from dayStart: Date) -> Int {
        Int(date.timeIntervalSince(dayStart) / 60)
    }

    /// Deadlines from the shown day over the next 14 days.
    private func loadUpcomingDeadlines(open: [TaskItem]) -> [ImportantDeadline] {
        let range = anchor...anchor.adding(days: 13, calendar: calendar)
        let interval = DateInterval(start: range.lowerBound.startDate(in: calendar),
                                    end: range.upperBound.adding(days: 1, calendar: calendar).startDate(in: calendar))
        let deadlineCalendars = Set(settings.deadlineCalendarIDs ?? [])
        let events = deadlineCalendars.isEmpty ? [] : calendarStore.events(in: interval, calendarIDs: deadlineCalendars)
        return importantDeadlines(tasks: open, events: events, deadlineCalendarIDs: deadlineCalendars, in: range, calendar: calendar)
    }

    /// Selected calendars plus plan and deadline calendars; `nil` (all) when nothing is selected.
    private func readableCalendarIDs() -> Set<String>? {
        guard let selected = settings.selectedCalendarIDs else { return nil }
        var ids = Set(selected)
        if let plan = settings.planCalendarID { ids.insert(plan) }
        ids.formUnion(settings.deadlineCalendarIDs ?? [])
        return ids
    }

    /// Drops assignments of tasks that are gone, but only for sources that loaded completely:
    /// an offline or failing source must not lose its plan (design §11.8, Review Focus 4).
    private func pruneAssignments(open: [TaskItem]) {
        let loaded = Set(taskList.sourceStates.filter { $0.value == .loaded }.map(\.key))
        let everything = PlanDay(year: 1, month: 1, day: 1)...PlanDay(year: 9999, month: 12, day: 31)
        let keep = Set(open.map(\.id)).union(planStore.assignments(in: everything).keys.filter { !loaded.contains($0.source) })
        planStore.prune(keeping: keep)
    }

    private func weekStart(of day: PlanDay) -> PlanDay {
        let start = calendar.dateInterval(of: .weekOfYear, for: day.startDate(in: calendar))?.start ?? day.startDate(in: calendar)
        return PlanDay(date: start, calendar: calendar)
    }
}
