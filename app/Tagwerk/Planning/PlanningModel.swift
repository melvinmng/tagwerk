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
    /// Event ID → task for `blocks`.
    let links: [String: TaskID]
    /// Assigned tasks whose planned day lies after their due date.
    let isPastDue: Set<TaskID>
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
    private(set) var leftovers: [TaskItem] = []
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
        let links = Dictionary(resolveLinks(events: events, tasks: open, manual: blocks.links.manualLinks())
                                .map { ($0.eventID, $0.taskID) }, uniquingKeysWith: { first, _ in first })
        let deadlines = importantDeadlines(tasks: open, events: events,
                                           deadlineCalendarIDs: Set(settings.deadlineCalendarIDs ?? []),
                                           in: range, calendar: calendar)
        let assignments = planStore.assignments(in: range)
        let overrides = planStore.overrides(in: range)
        let tasksByID = Dictionary(open.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var result: [DayPlan] = []
        var day = range.lowerBound
        while day <= range.upperBound {
            result.append(dayPlan(day, events: events, links: links, deadlines: deadlines, assignments: assignments,
                                  overrides: overrides, tasksByID: tasksByID, reminders: reminders,
                                  recurringIDs: recurringIDs))
            day = day.adding(days: 1, calendar: calendar)
        }
        days = result

        let assignedIDs = Set(planStore.assignments(in: PlanDay(year: 1, month: 1, day: 1)...PlanDay(year: 9999, month: 12, day: 31)).keys)
        unplanned = open.filter { !assignedIDs.contains($0.id) }
        leftovers = planStore.leftovers(before: today, openTaskIDs: Set(open.map(\.id))).compactMap { tasksByID[$0] }
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

    func clearError() {
        lastError = nil
    }

    // MARK: Private

    private func dayPlan(_ day: PlanDay, events: [CalendarEvent], links: [String: TaskID], deadlines: [ImportantDeadline],
                         assignments: [TaskID: PlanDay], overrides: [PlanDay: DayOverride], tasksByID: [TaskID: TaskItem],
                         reminders: [ReminderRecord], recurringIDs: Set<String>) -> DayPlan {
        let start = day.startDate(in: calendar)
        let end = day.adding(days: 1, calendar: calendar).startDate(in: calendar)
        let dayEvents = events.filter { $0.end > start && $0.start < end }.sorted { $0.start < $1.start }
        let linkedEvents = dayEvents.filter { links[$0.id] != nil && !$0.isAllDay }
        let tasksWithBlocks = Set(linkedEvents.compactMap { links[$0.id] })
        let assigned = assignments.filter { $0.value == day }.compactMap { tasksByID[$0.key] }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        var planned = linkedEvents.reduce(0) { total, event in
            let from = max(event.start, start), to = min(event.end, end)
            return total + max(0, Int(to.timeIntervalSince(from) / 60))
        }
        var estimated = 0
        for task in assigned where !tasksWithBlocks.contains(task.id) {
            // Recurring reminders count once, through their recurring effort.
            if task.id.source == .reminders, recurringIDs.contains(task.id.rawValue) { continue }
            if let minutes = task.estimateMinutes {
                planned += minutes
            } else {
                planned += settings.defaultTaskMinutes
                estimated += 1
            }
        }
        let input = CapacityInput(
            hours: workHours(on: day, schedule: settings.weekSchedule, overrides: overrides, calendar: calendar),
            lunchStartMinutes: settings.lunchStartMinutes, lunchMinutes: settings.lunchDurationMinutes,
            bufferMinutes: settings.bufferMinutes,
            busyIntervals: busyIntervals(events: dayEvents, on: day, calendar: calendar, excluding: Set(links.keys)),
            recurringMinutes: efforts.reservedMinutes(on: day, reminders: reminders, calendar: calendar),
            plannedMinutes: planned, estimatedCount: estimated
        )
        let pastDue = Set(assigned.filter { task in task.due.map { PlanDay($0) < day } ?? false }.map(\.id))
        return DayPlan(day: day, capacity: capacity(input), deadlines: deadlines.filter { $0.day == day },
                       events: dayEvents.filter { links[$0.id] == nil }, blocks: linkedEvents,
                       assigned: assigned, links: links.filter { id, _ in linkedEvents.contains { $0.id == id } },
                       isPastDue: pastDue)
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
