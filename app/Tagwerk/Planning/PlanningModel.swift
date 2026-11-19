import Foundation
import Observation
import RemindersKit
import TagwerkCore

extension PlanScope {
    var title: String {
        switch self {
        case .day: String(localized: "Tag")
        case .week: String(localized: "Woche")
        case .month: String(localized: "Monat")
        }
    }
}

/// Effort a repeating task (recurring reminder or local task) reserves on one day.
struct RecurringItem: Hashable, Identifiable {
    var id: String { taskID.key }
    let taskID: TaskID
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
    /// A free stretch to drop tasks into (list mode, design §13.4 C2).
    case gap(Range<Int>)

    var id: String {
        switch self {
        case .event(let event), .block(let event, _): event.id
        case .lunch: "lunch"
        case .gap(let range): "gap-\(range.lowerBound)"
        }
    }

    var label: String {
        switch self {
        case .event(let event), .block(let event, _): event.title
        case .lunch: String(localized: "Mittagspause")
        case .gap: String(localized: "frei")
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
    /// Today only: open tasks due today (recurring ones too) that are not planned for today and have no block
    /// today ("Heute offen, nicht zugeordnet"); non-recurring ones count as load (design §13.9).
    let openToday: [TaskItem]
    /// Event ID → task for `blocks`.
    let links: [String: TaskID]
    /// Assigned tasks whose planned day lies after their due date.
    let isPastDue: Set<TaskID>
    /// Recurring effort reserved on this day.
    let recurring: [RecurringItem]
    /// The day as the AI planner sees it, built from the same numbers as `capacity` (design §8.2).
    var planInput: PlanInputDay? = nil
    /// Open AI suggestions for this day (purple, dashed; mockup a).
    var suggestions: [PlanSuggestion] = []
    /// The day lies before today.
    let isPast: Bool
}

/// Planning changes made in the task editor; applied together with "Sichern" (design §13.4 C4, §13.8 G4).
struct PlannedEdit: Equatable {
    struct Block: Equatable, Identifiable {
        var id: String { event.id }
        let event: CalendarEvent
        var start: Date
        var minutes: Int
        var isDeleted = false
    }

    struct NewBlock: Equatable, Identifiable {
        let id = UUID()
        var start: Date
        var minutes: Int
    }

    var day: PlanDay?
    /// Moving to another day moves future blocks along (otherwise they are deleted).
    var moveBlocks = true
    var blocks: [Block]
    var newBlocks: [NewBlock] = []
    /// Recurring reminders only: effort in minutes and whether it applies from this day on.
    var recurringMinutes: Int?
    var recurringForAll = false
    let originalDay: PlanDay?
    let originalRecurringMinutes: Int?
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
    /// Plans of the neighbouring days (day scope) or weeks (week scope) for the page previews while swiping. They
    /// carry no AI suggestions; see `loadNeighbours()`.
    var neighbourPlans: [PlanDay: DayPlan] = [:]
    @ObservationIgnored var neighbourLoad: Task<Void, Never>?
    /// The app turns this on; tests leave it off, so no background load outlives a test's store.
    @ObservationIgnored var loadsNeighboursAfterReload = false
    /// Tasks that are the open focus of today (phase 7); set by `RoutinesModel`. The day view puts a star on them.
    var focusTaskIDs: Set<TaskID> = []
    private(set) var unplanned: [TaskItem] = []
    /// Open tasks planned before today or due before today without a planned day; not counted as load until
    /// they are moved to a day (design §13.9).
    private(set) var overdue: [TaskItem] = []
    /// Important deadlines from the anchor day over the next 14 days (deadline card of the day view).
    private(set) var upcomingDeadlines: [ImportantDeadline] = []
    /// Tasks with a repetition: reminders with a rule and local tasks (for "Aufwand ändern …" and ↻).
    private(set) var recurringTaskIDs: Set<TaskID> = []
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
    let marks: EventMarkStore
    let suggestionStore: SuggestionStore?

    /// Minutes in blocks against the effort of a task (user rule 2026-11-18).
    struct SessionProgress: Equatable {
        let blocked: Int
        let estimate: Int
        var remaining: Int { max(0, estimate - blocked) }
    }

    /// Progress of every open task with an effort that already has blocks.
    private(set) var sessionProgress: [TaskID: SessionProgress] = [:]
    /// Tasks whose blocks hold less time than their effort ("Noch einzuplanen", mockup RZ1).
    private(set) var toSchedule: [TaskItem] = []
    /// Minutes already in blocks per task (session window), for the AI's remaining effort.
    private(set) var blockedMinutesByTask: [TaskID: Int] = [:]
    /// Repetition rules of repeating tasks, for their session window.
    private var recurrenceRules: [TaskID: RecurrenceRule] = [:]
    /// Full recurrences of open repeating tasks, to compare a changed rule with the current one.
    private var recurrences: [TaskID: Recurrence] = [:]
    /// The block created by the last "Duplizieren", for "Widerrufen".
    private(set) var lastDuplicate: CalendarEvent?
    /// Open AI suggestion batches that touch the shown range.
    private(set) var suggestionBatches: [SuggestionBatch] = []
    /// Duration counted for tasks without effort.
    var defaultTaskMinutes: Int { settings.defaultTaskMinutes }
    /// Placeholder events of the shown days that may belong to a real event (design §13.15 M1).
    private(set) var mergeSuggestions: [MergeSuggestion] = []
    /// Kept event ID → the accepted merges whose copies it hides.
    private var appliedMerges: [String: [MergeSuggestion]] = [:]

    // MARK: Deadline marks state (plan deadline-marking)

    /// Events marked as deadlines in Tagwerk and the calendar events that prepare for a deadline.
    let deadlineMarks: DeadlineMarkStore
    /// Events of the shown range that are deadlines: from a deadline calendar or marked.
    private(set) var deadlineEventIDs: Set<String> = []
    /// Marks whose event could not be found again; shown in the deadline card, never deleted silently.
    private(set) var orphanedMarks: [OrphanedMark] = []
    /// Preparation of the deadlines in `upcomingDeadlines` that have linked events (key: `preparationKey`).
    private(set) var preparation: [String: PreparationSummary] = [:]
    /// Upcoming events whose title looks like an exam or a submission (keyword card DL3).
    private(set) var deadlineSuggestions: [CalendarEvent] = []
    /// Event ID → the deadline it prepares for, for the shown range.
    private var preparationTargets: [String: PreparationTarget] = [:]
    /// Called after marks change, so notifications and the widget follow.
    var onDeadlinesChanged: (() -> Void)?

    init(taskList: TaskListModel, calendarStore: CalendarStore, reminderStore: ReminderStore, planStore: PlanStore,
         efforts: RecurringEffortStore, blocks: BlockPlanner, settings: AppSettings, marks: EventMarkStore,
         deadlineMarks: DeadlineMarkStore? = nil,
         suggestions: SuggestionStore? = nil, now: @escaping () -> Date = Date.init, calendar: Calendar = .tagwerk) {
        self.deadlineMarks = deadlineMarks ?? DeadlineMarkStore(context: marks.modelContext)
        self.suggestionStore = suggestions
        self.marks = marks
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

    /// Open reminders of all lists, read past the list selection to recognize recurring ones; the shopping
    /// list is left out, because its entries are not tasks.
    private func planningReminders() async -> [ReminderRecord] {
        guard reminderStore.accessState == .fullAccess else { return [] }
        let shoppingListID = settings.shoppingListID
        return await reminderStore.openReminders(in: nil).filter { $0.listID != shoppingListID }
    }

    func reload() async {
        let range = self.range
        let open = taskList.items.filter { !$0.isCompleted }
        pruneAssignments(open: open)

        let series = await recurringSeries(open: open)
        let recurringIDs = Set(series.map(\.id))
        let interval = DateInterval(start: range.lowerBound.startDate(in: calendar),
                                    end: range.upperBound.adding(days: 1, calendar: calendar).startDate(in: calendar))
        // Marks first: follow moved events and report vanished ones before anything reads the marked IDs.
        deadlineMarks.prune(now: now())
        orphanedMarks = resolveDeadlineMarks()
        let raw = calendarStore.events(in: interval, calendarIDs: readableCalendarIDs())
        let marked = deadlineMarks.markedIDs(in: raw)
        let (events, suggestions) = markedEvents(raw, keeping: marked)
        mergeSuggestions = suggestions
        let deadlineIDs = deadlineIDs(in: events, marked: marked)
        deadlineEventIDs = deadlineIDs
        preparationTargets = deadlineMarks.preparationTargets(for: events)
        let resolved = resolveLinks(events: events, tasks: open, manual: blocks.links.manualLinks())
        resolvedLinks = Dictionary(resolved.map { ($0.eventID, $0) }, uniquingKeysWith: { first, _ in first })
        recurringTaskIDs = recurringIDs
        recurrenceRules = Dictionary(series.map { ($0.id, $0.recurrence.rule) }, uniquingKeysWith: { first, _ in first })
        recurrences = Dictionary(series.map { ($0.id, $0.recurrence) }, uniquingKeysWith: { first, _ in first })
        updateSessions(open: open)
        let links = resolvedLinks.mapValues(\.taskID)
        let deadlines = importantDeadlines(tasks: open, events: events,
                                           deadlineCalendarIDs: Set(settings.deadlineCalendarIDs ?? []),
                                           markedEventIDs: marked, in: range, calendar: calendar)
        let assignments = planStore.assignments(in: range)
        let overrides = planStore.overrides(in: range)
        let tasksByID = Dictionary(open.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let everything = PlanDay(year: 1, month: 1, day: 1)...PlanDay(year: 9999, month: 12, day: 31)
        let allAssignments = planStore.assignments(in: everything)

        suggestionBatches = suggestionStore?.batches(in: range) ?? []
        // A move shows on the day the task leaves, where the user decides about it.
        let suggestionsByDay = Dictionary(grouping: suggestionBatches.flatMap(\.suggestions)) { suggestion in
            suggestion.kind == .move ? (suggestion.fromDay ?? suggestion.day) : suggestion.day
        }
        var result: [DayPlan] = []
        var day = range.lowerBound
        while day <= range.upperBound {
            var plan = dayPlan(day, events: events, links: links, deadlines: deadlines, assignments: assignments,
                               overrides: overrides, tasksByID: tasksByID, series: series,
                               recurringIDs: recurringIDs, open: open, allAssignments: allAssignments,
                               deadlineIDs: deadlineIDs)
            plan.suggestions = suggestionsByDay[day] ?? []
            result.append(plan)
            day = day.adding(days: 1, calendar: calendar)
        }
        days = result

        // Left over from a past day ("liegen geblieben") counts as unplanned again, also in week and month.
        unplanned = open.filter { task in allAssignments[task.id].map { $0 < self.today } ?? true }
        upcomingDeadlines = loadUpcomingDeadlines(open: open)
        let today = self.today
        // Overdue: due before today, or planned for an earlier day and not due today or later ("liegen geblieben").
        // Planned for today or later, or due today, is not overdue.
        overdue = sortedTasks(open.filter { task in
            let due = task.due.map(PlanDay.init)
            if let planned = allAssignments[task.id], planned >= today { return false }
            if let due, due >= today { return false }
            if let due { return due < today }
            return allAssignments[task.id].map { $0 < today } ?? false
        }, calendar: calendar)
        await updateEvening(open: open, allAssignments: allAssignments, recurringIDs: recurringIDs)
        scheduleNeighbourLoad()
    }

    /// Open tasks with a time block (own or linked event) on `day`, read without changing what is shown.
    func taskIDsWithBlocks(on day: PlanDay) -> Set<TaskID> {
        let open = taskList.items.filter { !$0.isCompleted }
        let interval = DateInterval(start: day.startDate(in: calendar),
                                    end: day.adding(days: 1, calendar: calendar).startDate(in: calendar))
        let events = calendarStore.events(in: interval, calendarIDs: readableCalendarIDs())
        return Set(resolveLinks(events: events, tasks: open, manual: blocks.links.manualLinks()).map(\.taskID))
    }

    /// The AI view of days outside the shown range (e.g. the next week as targets for moving tasks away
    /// from a full day). Computed like `reload()` without changing what is shown.
    func planInputs(in range: ClosedRange<PlanDay>) async -> [PlanInputDay] {
        await dayPlans(in: range, withDeadlines: false).compactMap(\.planInput)
    }

    /// The plans of days outside (or inside) the shown range, computed like `reload()` without changing what is shown.
    /// Page previews ask for the deadlines too; the AI view does not need them.
    func dayPlans(in range: ClosedRange<PlanDay>, withDeadlines: Bool = true) async -> [DayPlan] {
        let open = taskList.items.filter { !$0.isCompleted }
        let series = await recurringSeries(open: open)
        let recurringIDs = Set(series.map(\.id))
        let interval = DateInterval(start: range.lowerBound.startDate(in: calendar),
                                    end: range.upperBound.adding(days: 1, calendar: calendar).startDate(in: calendar))
        let raw = calendarStore.events(in: interval, calendarIDs: readableCalendarIDs())
        let marked = deadlineMarks.markedIDs(in: raw)
        let (events, _) = markedEvents(raw, keeping: marked)
        let deadlineIDs = deadlineIDs(in: events, marked: marked)
        let links = Dictionary(resolveLinks(events: events, tasks: open, manual: blocks.links.manualLinks()).map { ($0.eventID, $0.taskID) },
                               uniquingKeysWith: { first, _ in first })
        let deadlines = withDeadlines
            ? importantDeadlines(tasks: open, events: events, deadlineCalendarIDs: Set(settings.deadlineCalendarIDs ?? []),
                                 markedEventIDs: marked, in: range, calendar: calendar)
            : []
        let assignments = planStore.assignments(in: range)
        let overrides = planStore.overrides(in: range)
        let tasksByID = Dictionary(open.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let everything = PlanDay(year: 1, month: 1, day: 1)...PlanDay(year: 9999, month: 12, day: 31)
        let allAssignments = planStore.assignments(in: everything)
        var result: [DayPlan] = []
        var day = range.lowerBound
        while day <= range.upperBound {
            result.append(dayPlan(day, events: events, links: links, deadlines: deadlines, assignments: assignments,
                                  overrides: overrides, tasksByID: tasksByID, series: series,
                                  recurringIDs: recurringIDs, open: open, allAssignments: allAssignments,
                                  deadlineIDs: deadlineIDs))
            day = day.adding(days: 1, calendar: calendar)
        }
        return result
    }

    /// Events, time blocks and deadlines of `count` days from `first` for the widget snapshot (phase 4).
    /// Read-only: anchor, scope, `days` and the merge suggestions stay as they are; EventKit only, no network.
    func snapshotInput(from first: PlanDay, days count: Int) -> [SnapshotDayInput] {
        let open = taskList.items.filter { !$0.isCompleted }
        let range = first...first.adding(days: max(0, count - 1), calendar: calendar)
        let interval = DateInterval(start: range.lowerBound.startDate(in: calendar),
                                    end: range.upperBound.adding(days: 1, calendar: calendar).startDate(in: calendar))
        let raw = calendarStore.events(in: interval, calendarIDs: readableCalendarIDs())
        let marked = deadlineMarks.markedIDs(in: raw)
        let (events, _) = markedEvents(raw, keeping: marked)
        let deadlineIDs = deadlineIDs(in: events, marked: marked)
        // A deadline event linked to a task is that task's anchor, not a time block (decision 5).
        let links = Set(resolveLinks(events: events, tasks: open, manual: blocks.links.manualLinks()).map(\.eventID))
            .subtracting(deadlineIDs)
        let deadlines = importantDeadlines(tasks: open, events: events, deadlineCalendarIDs: Set(settings.deadlineCalendarIDs ?? []),
                                           markedEventIDs: marked, in: range, calendar: calendar)
        let colors = Dictionary(calendarStore.eventCalendars().map { ($0.id, $0.colorHex) }, uniquingKeysWith: { first, _ in first })
        return (0..<count).map { offset in
            let day = first.adding(days: offset, calendar: calendar)
            let start = day.startDate(in: calendar)
            let end = day.adding(days: 1, calendar: calendar).startDate(in: calendar)
            let dayEvents = events.filter { $0.end > start && $0.start < end }
            let isBlock = { (event: CalendarEvent) in links.contains(event.id) && !event.isAllDay }
            return SnapshotDayInput(day: day, events: dayEvents.filter { !isBlock($0) }, blocks: dayEvents.filter(isBlock),
                                    deadlines: deadlines.filter { $0.day == day }, colorHex: { colors[$0] ?? nil })
        }
    }

    /// Day picked in the month grid (mockup E1); see `monthSelection`.
    var selectedDay: PlanDay?

    /// The picked day when it lies in the shown month, else today when it does, else the first of the month.
    var monthSelection: PlanDay {
        let inMonth = { (day: PlanDay) in day.year == self.anchor.year && day.month == self.anchor.month }
        if let selectedDay, inMonth(selectedDay) { return selectedDay }
        if inMonth(today) { return today }
        return PlanDay(year: anchor.year, month: anchor.month, day: 1)
    }

    /// Unplanned tasks for the drawer (mockup D1): due within the shown range first, then the rest
    /// (by due date, then title); `search` filters both.
    func unplannedSections(search: String) -> (dueInRange: [TaskItem], other: [TaskItem]) {
        let query = search.trimmingCharacters(in: .whitespaces)
        let matching = unplanned.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
        let range = self.range
        let sorted = sortedTasks(matching, calendar: calendar)
        let inRange = { (task: TaskItem) in task.due.map { range.contains(PlanDay($0)) } ?? false }
        return (sorted.filter(inRange), sorted.filter { !inRange($0) })
    }

    // MARK: Actions

    /// The day picked in the month moves one day; leaving the month shows the neighbouring month.
    func stepSelectedDay(_ direction: Int) {
        let next = monthSelection.adding(days: direction, calendar: calendar)
        if next.month != anchor.month || next.year != anchor.year { anchor = next }
        selectedDay = next
    }

    /// One day, week or month forward (`1`) or back (`-1`), for arrows and swiping.
    func step(_ direction: Int) {
        switch scope {
        case .day: anchor = anchor.adding(days: direction, calendar: calendar)
        case .week: anchor = anchor.adding(days: 7 * direction, calendar: calendar)
        case .month:
            let moved = calendar.date(byAdding: .month, value: direction, to: anchor.startDate(in: calendar))
            anchor = moved.map { PlanDay(date: $0, calendar: calendar) } ?? anchor
        }
    }

    /// Plans `id` for `day` (Tagwerk only). Future time blocks require a decision first.
    func assign(_ id: TaskID, to day: PlanDay) async {
        if !blocks.futureBlocks(for: id, after: now()).isEmpty {
            pendingBlockDecision = PendingBlockDecision(taskID: id, day: day)
            return
        }
        planStore.assign(id, to: day)
        await reload()
    }

    /// Assigns with a decision made beforehand (editor switch "Zeitblöcke mitverschieben").
    func assign(_ id: TaskID, to day: PlanDay, moveBlocks: Bool) async {
        do {
            if moveBlocks {
                try blocks.moveFutureBlocks(of: id, to: day, after: now())
            } else {
                try blocks.deleteFutureBlocks(of: id, after: now())
            }
        } catch {
            lastError = TaskListModel.message(for: error)
        }
        planStore.assign(id, to: day)
        await reload()
    }

    /// Current planning of a task for the editor.
    func plannedEdit(for task: TaskItem) -> PlannedEdit {
        let info = plannedInfo(for: task.id)
        let recurring = recurringItem(for: task, on: today)
        return PlannedEdit(day: info.day, blocks: info.blocks.map {
            PlannedEdit.Block(event: $0, start: $0.start, minutes: Int($0.end.timeIntervalSince($0.start) / 60))
        }, recurringMinutes: recurring?.minutes, originalDay: info.day, originalRecurringMinutes: recurring?.minutes)
    }

    /// Writes only what changed: blocks first (so moving the day sees their new times), then the day and effort.
    func applyPlanning(_ edit: PlannedEdit, for task: TaskItem) async {
        for block in edit.blocks {
            let original = Int(block.event.end.timeIntervalSince(block.event.start) / 60)
            do {
                if block.isDeleted {
                    try calendarStore.deleteBlock(id: block.event.id, expectedVersion: block.event.version)
                } else if block.start != block.event.start || block.minutes != original {
                    _ = try calendarStore.moveBlock(id: block.event.id, to: block.start,
                                                    end: block.start.addingTimeInterval(TimeInterval(max(15, block.minutes) * 60)),
                                                    expectedVersion: block.event.version)
                }
            } catch {
                lastError = TaskListModel.message(for: error)
            }
        }
        for new in edit.newBlocks {
            do {
                try blocks.createBlock(for: task, start: new.start, minutes: max(15, new.minutes))
            } catch {
                lastError = TaskListModel.message(for: error)
            }
        }
        if edit.day != edit.originalDay {
            if let day = edit.day {
                await assign(task.id, to: day, moveBlocks: edit.moveBlocks)
            } else {
                planStore.unassign(task.id)
            }
        }
        if edit.recurringMinutes != edit.originalRecurringMinutes, recurringItem(for: task, on: today) != nil {
            await setRecurringEffort(edit.recurringMinutes, task: task.id, day: today, forAll: edit.recurringForAll)
        }
        await reload()
    }

    /// Plans a selection for `day`; future blocks move along without asking (one decision for many tasks).
    func plan(_ ids: [TaskID], to day: PlanDay) async {
        for id in ids {
            do {
                try blocks.moveFutureBlocks(of: id, to: day, after: now())
            } catch {
                lastError = TaskListModel.message(for: error)
            }
            planStore.assign(id, to: day)
        }
        await reload()
    }

    /// "Für heute einplanen" from the task list selection: planned day only, the source stays unchanged.
    func planToday(_ ids: [TaskID]) async {
        await plan(ids, to: today)
    }

    /// Current planned day for the menu row (mockup F1).
    func plannedText(for id: TaskID) -> String {
        guard let day = planStore.assignment(for: id) else { return String(localized: "noch nicht eingeplant") }
        return String(localized: "Arbeitstag: \(day.startDate(in: calendar).formatted(.dateTime.weekday(.abbreviated).day().month()))")
    }

    /// Block menu and dragging only for Tagwerk's own blocks in a writable calendar; other linked events
    /// open their event detail (with the series question) instead.
    func canEditAsBlock(_ event: CalendarEvent) -> Bool {
        event.url.flatMap(TaskLinkURL.parse) != nil && event.isEditable && !event.isInvitation
    }

    /// Effort of the given tasks, counting tasks without effort with the default duration.
    func plannedMinutes(for ids: [TaskID]) -> Int {
        let wanted = Set(ids)
        return taskList.items.filter { wanted.contains($0.id) }.reduce(0) { $0 + ($1.estimateMinutes ?? settings.defaultTaskMinutes) }
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
    func setRecurringEffort(_ minutes: Int?, task: TaskID, day: PlanDay, forAll: Bool) async {
        if forAll {
            efforts.setForAll(minutes, task: task, from: day)
        } else {
            efforts.setForDay(minutes ?? 0, task: task, day: day)
        }
        await reload()
    }

    /// The recurring-effort entry of a repeating task on `day`; `nil` for other tasks. A task carrying a rule counts
    /// before the next reload (a local task that just got one).
    func recurringItem(for task: TaskItem, on day: PlanDay) -> RecurringItem? {
        guard task.recurrence != nil || recurringTaskIDs.contains(task.id) else { return nil }
        return RecurringItem(taskID: task.id, title: task.title, minutes: efforts.minutes(for: task.id, on: day) ?? 0)
    }

    /// Future blocks of `task` whose occurrence disappears under `recurrence`. A block prepares the occurrence of
    /// the current rule on or after its day (a Tuesday block for Thursday's occurrence); it is listed when the new
    /// rule has no occurrence on that day. Without a current rule the block's own day counts. Empty for rules
    /// Tagwerk cannot read. Blocks are never changed here (decision 2026-11-18: they stay in the calendar; the
    /// save question names them).
    func blocksOffSeries(for task: TaskItem, recurrence: Recurrence) -> [CalendarEvent] {
        if case .unsupported = recurrence.rule { return [] }
        let current = task.recurrence ?? recurrences[task.id]
        return blocks.futureBlocks(for: task.id, after: now()).filter { block in
            let day = PlanDay(date: block.start, calendar: calendar)
            let served: PlanDay = if let current, case .unsupported = current.rule { day }
                else { current.flatMap { nextOccurrence(of: $0, onOrAfter: day, calendar: calendar) } ?? day }
            return nextOccurrence(of: recurrence, onOrAfter: served, calendar: calendar) != served
        }
    }

    /// Completing a repeating task in Tagwerk frees today's effort; reopening reserves it again (design §13.3).
    func didChangeCompletion(_ id: TaskID, isCompleted: Bool) async {
        guard recurringTaskIDs.contains(id) else { return }
        if isCompleted {
            efforts.markDone(task: id, day: today)
        } else {
            efforts.unmarkDone(task: id, day: today)
        }
        await reload()
    }

    /// Blocks of a task that start after this moment; exactly those a hand-over deletes.
    func futureBlockCount(for id: TaskID) -> Int {
        blocks.futureBlocks(for: id, after: now()).count
    }

    /// The issue left the user's lists: its planned day and its future blocks go, past blocks stay.
    func didHandOver(_ id: TaskID) async {
        planStore.unassign(id)
        do {
            try blocks.deleteFutureBlocks(of: id, after: now())
        } catch {
            lastError = TaskListModel.message(for: error)
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
        if !plan.capacity.isDayOff, let lunch = lunch(on: plan.day) {
            rows.append((lunch.lowerBound, .lunch(startMinutes: lunch.lowerBound, minutes: lunch.count)))
        }
        return rows.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// All-day events of the day; all-day events from deadline calendars appear as deadlines instead.
    /// The timeline with free stretches between the rows, ordered by start time.
    func timelineWithGaps(for plan: DayPlan) -> [TimelineRow] {
        let dayStart = plan.day.startDate(in: calendar)
        func start(_ row: TimelineRow) -> Int {
            switch row {
            case .event(let event), .block(let event, _): minutes(event.start, from: dayStart)
            case .lunch(let start, _): start
            case .gap(let range): range.lowerBound
            }
        }
        let rows = timeline(for: plan) + gaps(for: plan).map(TimelineRow.gap)
        return rows.enumerated().sorted { lhs, rhs in
            let left = start(lhs.element), right = start(rhs.element)
            return left != right ? left < right : lhs.offset < rhs.offset
        }
        .map(\.element)
    }

    /// Dropping a task on a free stretch or the hour grid creates a block there (effort or 60 min).
    func dropTask(key: String, atMinutes startMinutes: Int, on day: PlanDay) async {
        guard let id = TaskID(key: key), let task = taskList.items.first(where: { $0.id == id }) else { return }
        let length = suggestedBlockMinutes(for: task, on: day)
        let range = clampedBlock(startMinutes: snapped(minutes: startMinutes), duration: length, dayLength: dayLength(day))
        await createBlock(for: task, start: day.startDate(in: calendar).addingTimeInterval(TimeInterval(range.lowerBound * 60)),
                          minutes: range.count)
    }

    /// All-day events of the day; all-day deadline events (deadline calendars and marked) appear as deadlines instead.
    func allDayEvents(for plan: DayPlan) -> [CalendarEvent] {
        let deadlineCalendars = Set(settings.deadlineCalendarIDs ?? [])
        return (plan.events + plan.blocks).filter {
            $0.isAllDay && !deadlineCalendars.contains($0.calendarID) && !deadlineEventIDs.contains($0.id)
        }
    }

    /// Tasks without a time planned for this day, for the "Ohne Uhrzeit" panel (design §13.15 D1): only what the
    /// user committed to the day; due-today, recurring and overdue tasks wait in their own sections below.
    func timelessTasks(for plan: DayPlan) -> [TaskItem] {
        plan.assigned
    }

    /// Events whose time can change by dragging: writable, timed and not someone else's invitation.
    func canDrag(_ event: CalendarEvent) -> Bool {
        event.isEditable && !event.isInvitation && !event.isAllDay
    }

    /// Sets start and end of an event on its day in one write (snapped to 15 min, at least 15 min, inside the
    /// day). Other fields stay. A Tagwerk block keeps its task's planned day in step.
    func setTime(of event: CalendarEvent, startMinutes: Int, endMinutes: Int, span: EventSpan) async {
        let day = PlanDay(date: event.start, calendar: calendar)
        let start = snapped(minutes: startMinutes)
        let range = clampedBlock(startMinutes: start, duration: snapped(minutes: endMinutes) - start, dayLength: dayLength(day))
        var draft = EventDraft(event)
        draft.start = day.startDate(in: calendar).addingTimeInterval(TimeInterval(range.lowerBound * 60))
        draft.end = draft.start.addingTimeInterval(TimeInterval(range.count * 60))
        do {
            _ = try calendarStore.updateEvent(id: event.id, with: draft, span: span, expectedVersion: event.version)
        } catch {
            lastError = TaskListModel.message(for: error)
        }
        await reload()
    }

    // MARK: Lunch per day (design §13.15 L1)

    /// The lunch break of a day: a day's own value, else the setting; `nil` without a break.
    func lunch(on day: PlanDay) -> Range<Int>? {
        let value = marks.lunch(on: day) ?? (settings.lunchStartMinutes, settings.lunchDurationMinutes)
        return value.minutes > 0 ? value.startMinutes..<(value.startMinutes + value.minutes) : nil
    }

    /// Moves or resizes the break on this day only (snapped to 15 min, kept inside the day).
    func setLunch(startMinutes: Int, minutes: Int, on day: PlanDay) async {
        let range = clampedBlock(startMinutes: snapped(minutes: startMinutes), duration: snapped(minutes: minutes),
                                 dayLength: dayLength(day))
        marks.setLunch(startMinutes: range.lowerBound, minutes: range.count, on: day)
        await reload()
    }

    /// No break on this day.
    func removeLunch(on day: PlanDay) async {
        marks.setLunch(startMinutes: settings.lunchStartMinutes, minutes: 0, on: day)
        await reload()
    }

    /// "Widerrufen": back to the setting for this day.
    func resetLunch(on day: PlanDay) async {
        marks.clearLunch(on: day)
        await reload()
    }

    /// "Für alle Tage": the day's break becomes the setting.
    func applyLunchToAllDays(from day: PlanDay) async {
        if let value = marks.lunch(on: day) {
            settings.lunchStartMinutes = value.startMinutes
            settings.lunchDurationMinutes = value.minutes
            marks.clearLunch(on: day)
        }
        await reload()
    }

    /// The day has its own break that differs from the setting.
    func hasOwnLunch(on day: PlanDay) -> Bool { marks.lunch(on: day) != nil }

    // MARK: Free marks and merge suggestions (design §13.15 F1, M1)

    /// Marks events as "Frei" (`free`) or "Belegt" in Tagwerk only; `series` applies to all later occurrences.
    func setFree(_ events: [CalendarEvent], free: Bool, series: Bool) async {
        for event in events { marks.mark(event, isFree: free, series: series && event.isRecurring) }
        await reload()
    }

    /// Busy minutes the selection would free on its day (shown before "Auf Frei setzen").
    func busyMinutes(of events: [CalendarEvent]) -> Int {
        events.filter { $0.isBusy && !$0.isAllDay }.reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
    }

    /// Stored merge rules ("künftig immer"): title, calendar name and whether they merge or keep apart.
    func mergeRules() -> [(key: String, title: String, calendar: String, merges: Bool)] {
        marks.mergeDecisions().compactMap { decision in
            guard let title = decision.ruleTitle, let calendarID = decision.ruleCalendarID else { return nil }
            return (decision.key, title, calendarTitle(calendarID) ?? "Kalender", decision.isMerged)
        }
        .sorted { $0.title < $1.title }
    }

    func deleteMergeRule(key: String) async {
        marks.deleteMergeDecision(key: key)
        await reload()
    }

    /// Forgets every "Zusammenfassen / Getrennt lassen" decision, including "künftig immer" rules.
    func resetMergeDecisions() async {
        marks.clearMergeDecisions()
        await reload()
    }

    /// Per calendar over the next 7 days: whether Tagwerk reads it, how many events it has, how many the
    /// day views show and why the others are hidden (settings › "Kalender-Diagnose").
    func calendarDiagnostics() -> [CalendarDiagnostic] {
        let start = today.startDate(in: calendar)
        let interval = DateInterval(start: start, end: today.adding(days: 7, calendar: calendar).startDate(in: calendar))
        let all = calendarStore.events(in: interval, calendarIDs: nil)
        let readable = readableCalendarIDs()
        let read = all.filter { readable?.contains($0.calendarID) ?? true }
        let deadlineMarked = deadlineMarks.markedIDs(in: read)
        let (marked, _) = markedEvents(read, keeping: deadlineMarked)
        let markedIDs = Set(marked.map(\.id))
        let deadlineCalendars = Set(settings.deadlineCalendarIDs ?? [])
        let isAllDayDeadline = { (event: CalendarEvent) in
            event.isAllDay && (deadlineCalendars.contains(event.calendarID) || deadlineMarked.contains(event.id))
        }
        var shownIDs = Set<String>()
        var day = today
        while day < today.adding(days: 7, calendar: calendar) {
            let dayStart = day.startDate(in: calendar), dayEnd = day.adding(days: 1, calendar: calendar).startDate(in: calendar)
            let dayEvents = marked.filter { $0.end > dayStart && $0.start < dayEnd }
            let merged = dayEvents
            shownIDs.formUnion(merged.filter { !isAllDayDeadline($0) }.map(\.id))
            day = day.adding(days: 1, calendar: calendar)
        }
        return calendarStore.eventCalendars().map { info in
            let own = all.filter { $0.calendarID == info.id }
            let isRead = readable?.contains(info.id) ?? true
            let hiddenByPlaceholder = isRead ? own.filter { !markedIDs.contains($0.id) }.count : 0
            let shown = isRead ? own.filter { shownIDs.contains($0.id) }.count : 0
            let asDeadline = isRead ? own.filter(isAllDayDeadline).count : 0
            return CalendarDiagnostic(calendarID: info.id, title: info.title, kind: info.kind, isRead: isRead,
                                      isDeadlineCalendar: deadlineCalendars.contains(info.id), events: own.count, shown: shown,
                                      hiddenByMerge: isRead ? max(0, own.count - shown - asDeadline - hiddenByPlaceholder) : 0,
                                      hiddenByPlaceholderDecision: hiddenByPlaceholder, shownAsDeadline: asDeadline)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    #if DEBUG
    /// Local and server identifiers of a few events of one calendar (Kalender-Diagnose, debug builds only).
    struct IdentifierSample: Equatable {
        struct Entry: Equatable, Identifiable {
            let id: String
            let externalID: String?
            let start: Date
        }

        let calendarID: String
        let calendarTitle: String
        let events: [Entry]
    }

    /// Up to five events per calendar over the next 14 days, for checking whether a subscription keeps its identifiers
    /// after a refresh (plan deadline-marking, Task 1). Titles stay out on purpose.
    func eventIdentifierSamples(limit: Int = 5) -> [IdentifierSample] {
        let interval = DateInterval(start: today.startDate(in: calendar),
                                    end: today.adding(days: 14, calendar: calendar).startDate(in: calendar))
        let events = calendarStore.events(in: interval, calendarIDs: nil)
        return calendarStore.eventCalendars().compactMap { info in
            let own = events.filter { $0.calendarID == info.id }.sorted { $0.start < $1.start }.prefix(limit)
            guard !own.isEmpty else { return nil }
            return IdentifierSample(calendarID: info.id, calendarTitle: info.title,
                                    events: own.map { IdentifierSample.Entry(id: $0.id, externalID: $0.externalID, start: $0.start) })
        }
    }
    #endif

    func decideMerge(_ suggestion: MergeSuggestion, merge: Bool, always: Bool) async {
        marks.decide(suggestion, merge: merge, always: always)
        await reload()
    }

    /// Applies Tagwerk's free marks and accepted merges; returns the undecided merge suggestions. Events in
    /// `keeping` (marked as deadlines) never take part in merging, so a deadline is never hidden.
    private func markedEvents(_ raw: [CalendarEvent], keeping: Set<String> = []) -> ([CalendarEvent], [MergeSuggestion]) {
        let freeMarks = marks.allMarks()
        var events = raw.map { event in
            var event = event
            if let free = marks.isFree(event, marks: freeMarks) { event.isBusy = !free }
            return event
        }
        // Switching merging off ("Termine zusammenfassen") shows every event and asks nothing.
        guard settings.mergeDuplicateEvents else { appliedMerges = [:]; return (events, []) }
        let decisions = marks.mergeDecisions()
        var hidden = [String: MergeSuggestion]()
        var open: [MergeSuggestion] = []
        let deadlineCalendars = Set(settings.deadlineCalendarIDs ?? [])
        for suggestion in TagwerkCore.mergeSuggestions(events, excluding: deadlineCalendars, excludingEventIDs: keeping) {
            switch marks.decision(for: suggestion, in: decisions) {
            case true?: hidden[suggestion.placeholderID] = suggestion
            case false?: break
            case nil: open.append(suggestion)
            }
        }
        // The kept event names the calendars of its hidden copies ("2 Kalender").
        var merges: [String: [MergeSuggestion]] = [:]
        for suggestion in hidden.values { merges[suggestion.keptID, default: []].append(suggestion) }
        appliedMerges.merge(merges) { _, new in new }
        events = events.filter { hidden[$0.id] == nil }.map { event in
            var event = event
            event.mergedCalendarIDs = (merges[event.id] ?? []).map(\.placeholderCalendarID)
            return event
        }
        return (events, open)
    }

    // MARK: Deadline marks and preparation (plan deadline-marking, DL2 + DV1 + DL3)

    /// From a deadline calendar or marked in Tagwerk.
    func isDeadlineEvent(_ event: CalendarEvent) -> Bool {
        deadlineEventIDs.contains(event.id) || isInDeadlineCalendar(event) || deadlineMarks.isMarked(event)
    }

    /// The deadline events (deadline calendars and marked) among `events`.
    func deadlineEventIDs(among events: [CalendarEvent]) -> Set<String> {
        deadlineIDs(in: events, marked: deadlineMarks.markedIDs(in: events))
    }

    func isInDeadlineCalendar(_ event: CalendarEvent) -> Bool {
        (settings.deadlineCalendarIDs ?? []).contains(event.calendarID)
    }

    func isMarkedDeadline(_ event: CalendarEvent) -> Bool { deadlineMarks.isMarked(event) }

    /// Marks an event as a deadline in Tagwerk only; `series` marks every occurrence of a recurring event.
    func markDeadline(_ event: CalendarEvent, series: Bool) async {
        deadlineMarks.mark(event, series: series && event.isRecurring)
        await deadlinesChanged()
    }

    /// Removes the mark of the event (or its series) and dissolves the preparation links to it.
    func unmarkDeadline(_ event: CalendarEvent) async {
        deadlineMarks.unmark(event)
        await deadlinesChanged()
    }

    /// "Entfernen" on a mark whose event is gone.
    func removeOrphanedMark(_ orphan: OrphanedMark) async {
        deadlineMarks.unmark(key: orphan.eventKey)
        await deadlinesChanged()
    }

    /// "übernehmen": the mark moves to the suggested event.
    func adoptCandidate(_ orphan: OrphanedMark) async {
        guard let candidate = orphan.candidate else { return }
        deadlineMarks.adopt(orphan, candidate: candidate)
        await deadlinesChanged()
    }

    /// Events within 14 days around a vanished mark's date, to carry the mark from now on ("Termin zuordnen …").
    func reassignCandidates(for orphan: OrphanedMark) -> [CalendarEvent] {
        let margin = TimeInterval(eventReferenceTitleWindowDays * 86_400)
        let interval = DateInterval(start: max(now(), orphan.start.addingTimeInterval(-margin)),
                                    end: max(now(), orphan.start.addingTimeInterval(margin)))
        let calendars = readableCalendarIDs().map { $0.union([orphan.calendarID]) }
        return calendarStore.events(in: interval, calendarIDs: calendars).sorted { $0.start < $1.start }
    }

    /// Moves a vanished mark to an event the user picked.
    func reassignMark(_ orphan: OrphanedMark, to event: CalendarEvent) async {
        deadlineMarks.adopt(orphan, candidate: event)
        await deadlinesChanged()
    }

    /// Shows the day of `event` in "Tag" (a tap on a preparation row).
    func showDay(of event: CalendarEvent) {
        anchor = PlanDay(date: event.start, calendar: calendar)
        scope = .day
    }

    /// The event is a deadline through a mark on its whole series.
    func isSeriesMark(_ event: CalendarEvent) -> Bool {
        deadlineMarks.mark(for: event)?.isSeries ?? false
    }

    /// Removing the mark asks first when it dissolves preparation links or covers a whole series (never silently).
    func needsUnmarkConfirmation(_ event: CalendarEvent) -> Bool {
        isSeriesMark(event) || preparationLinkCount(forDeadlineEvent: event) > 0
    }

    /// Preparation links that removing the mark of `event` would dissolve (asked before removing).
    func preparationLinkCount(forDeadlineEvent event: CalendarEvent) -> Int {
        deadlineMarks.linkCount(forMarkOf: event)
    }

    private func deadlinesChanged() async {
        await reload()
        onDeadlinesChanged?()
    }

    /// The deadline an event is, for the event sheet ("⚑ Klausur Statistik · in 9 Tagen"); `nil` for other events.
    func importantDeadline(for event: CalendarEvent) -> ImportantDeadline? {
        let day = PlanDay(date: event.start, calendar: calendar)
        return importantDeadlines(tasks: [], events: [event], deadlineCalendarIDs: Set(settings.deadlineCalendarIDs ?? []),
                                  markedEventIDs: deadlineMarks.markedIDs(in: [event]), in: day...day, calendar: calendar).first
    }

    /// Events between now and the deadline that can be linked as preparation (the deadline event itself excluded).
    func preparationCandidates(for deadline: ImportantDeadline) -> [CalendarEvent] {
        let current = now(), end = deadlineMoment(deadline)
        guard end > current else { return [] }
        // Read-only (called from view bodies): no merge pass, which would write `appliedMerges`.
        let events = calendarStore.events(in: DateInterval(start: current, end: end), calendarIDs: readableCalendarIDs())
        var seen = Set<String>()
        return events.filter { $0.id != deadline.eventID && $0.end > current && $0.start < end && seen.insert($0.id).inserted }
            .sorted { $0.start < $1.start }
    }

    /// Linked preparation events of a deadline, earlier ones included, ordered by start.
    func preparationEvents(for deadline: ImportantDeadline) -> [CalendarEvent] {
        let links = deadlineMarks.links(forDeadline: deadline.preparationKey)
        guard let first = links.map(\.start).min() else { return [] }
        let start = min(first, now()), end = deadlineMoment(deadline)
        guard end > start else { return [] }
        let events = calendarStore.events(in: DateInterval(start: start, end: end), calendarIDs: preparationCalendarIDs())
        return deadlineMarks.linkedEvents(forDeadline: deadline.preparationKey, among: events)
    }

    /// Links `event` (or, with `series`, its occurrences until the deadline) as preparation; Tagwerk only.
    func linkPreparation(_ event: CalendarEvent, to deadline: ImportantDeadline, series: Bool) async {
        deadlineMarks.link(event, toDeadline: deadline.preparationKey, title: deadline.title, until: deadlineMoment(deadline),
                           series: series && event.isRecurring)
        await reload()
    }

    /// Dissolves the link that makes `event` part of the preparation for `deadline`.
    func unlinkPreparation(_ event: CalendarEvent, from deadline: ImportantDeadline) async {
        guard let link = deadlineMarks.link(for: event, deadlineKey: deadline.preparationKey) else { return }
        deadlineMarks.unlink(key: link.key)
        await reload()
    }

    /// Whether a series link (not only this occurrence) makes `event` preparation for `deadline`.
    func isSeriesPreparation(_ event: CalendarEvent, for deadline: ImportantDeadline) -> Bool {
        deadlineMarks.link(for: event, deadlineKey: deadline.preparationKey)?.isSeries ?? false
    }

    /// The deadline a shown event prepares for (the mark "→ Klausur Statistik · in 8 Tagen").
    func preparationTarget(forEventID id: String) -> PreparationTarget? { preparationTargets[id] }

    /// The deadline behind a preparation target, if it still lies within the next 120 days.
    func deadline(for target: PreparationTarget) -> ImportantDeadline? {
        let from = PlanDay(date: min(now(), target.until), calendar: calendar)
        return deadlines(in: from...from.adding(days: 120, calendar: calendar)).first { $0.preparationKey == target.deadlineKey }
    }

    /// Deadlines after `event` (within 120 days) it can be linked to as preparation ("Zu Deadline zuordnen …").
    func linkableDeadlines(for event: CalendarEvent) -> [ImportantDeadline] {
        let from = PlanDay(date: max(event.start, now()), calendar: calendar)
        return deadlines(in: from...from.adding(days: 120, calendar: calendar))
            .filter { $0.eventID != event.id && deadlineMoment($0) > event.start }
    }

    /// All important deadlines in `range`, including events from deadline calendars and marked events.
    private func deadlines(in range: ClosedRange<PlanDay>) -> [ImportantDeadline] {
        let interval = DateInterval(start: range.lowerBound.startDate(in: calendar),
                                    end: range.upperBound.adding(days: 1, calendar: calendar).startDate(in: calendar))
        let deadlineCalendars = Set(settings.deadlineCalendarIDs ?? [])
        let calendars = deadlineCalendars.union(deadlineMarks.marks().map(\.calendarID))
        let events = calendars.isEmpty ? [] : calendarStore.events(in: interval, calendarIDs: calendars)
        return importantDeadlines(tasks: taskList.items.filter { !$0.isCompleted }, events: events,
                                  deadlineCalendarIDs: deadlineCalendars, markedEventIDs: deadlineMarks.markedIDs(in: events),
                                  in: range, calendar: calendar)
    }

    /// "Nein" on the keyword card: this event is not suggested again.
    func dismissDeadlineSuggestion(_ event: CalendarEvent) async {
        deadlineMarks.dismissSuggestion(event)
        await reload()
    }

    // MARK: Time blocks (design §13.4)

    /// The day timeline as an hour grid instead of rows (switch in the day view, stored in the settings).
    var showsHourGrid: Bool {
        get { !settings.prefersTimelineList }
        set { settings.prefersTimelineList = !newValue }
    }

    /// Moves a block to `toStartMinutes` (snapped to 15 min, kept inside the day) on `day`, keeping its length.
    /// Moving to another day also moves the task's planned day.
    func moveBlock(_ block: CalendarEvent, toStartMinutes: Int, on day: PlanDay) async {
        let dayStart = day.startDate(in: calendar)
        let length = Int(block.end.timeIntervalSince(block.start) / 60)
        let range = clampedBlock(startMinutes: snapped(minutes: toStartMinutes), duration: length, dayLength: dayLength(day))
        let start = dayStart.addingTimeInterval(TimeInterval(range.lowerBound * 60))
        do {
            _ = try calendarStore.moveBlock(id: block.id, to: start, end: start.addingTimeInterval(TimeInterval(range.count * 60)),
                                            expectedVersion: block.version)
            if PlanDay(date: block.start, calendar: calendar) != day, let taskID = resolvedLinks[block.id]?.taskID
                ?? block.url.flatMap(TaskLinkURL.parse) {
                planStore.assign(taskID, to: day)
            }
        } catch {
            lastError = TaskListModel.message(for: error)
        }
        await reload()
    }

    /// Changes the length of a block (snapped to 15 min, at least 15 min), keeping its start.
    func resizeBlock(_ block: CalendarEvent, minutes: Int) async {
        let day = PlanDay(date: block.start, calendar: calendar)
        let startMinutes = Int(block.start.timeIntervalSince(day.startDate(in: calendar)) / 60)
        let range = clampedBlock(startMinutes: startMinutes, duration: snapped(minutes: minutes), dayLength: dayLength(day))
        do {
            _ = try calendarStore.moveBlock(id: block.id, to: block.start,
                                            end: block.start.addingTimeInterval(TimeInterval(range.count * 60)),
                                            expectedVersion: block.version)
        } catch {
            lastError = TaskListModel.message(for: error)
        }
        await reload()
    }

    /// Moves the start of a block (snapped to 15 min) and keeps its end; at least 15 minutes remain.
    func resizeBlockStart(_ block: CalendarEvent, toStartMinutes: Int) async {
        let day = PlanDay(date: block.start, calendar: calendar)
        let dayStart = day.startDate(in: calendar)
        let endMinutes = Int(block.end.timeIntervalSince(dayStart) / 60)
        let startMinutes = min(max(0, snapped(minutes: toStartMinutes)), endMinutes - 15)
        do {
            _ = try calendarStore.moveBlock(id: block.id, to: dayStart.addingTimeInterval(TimeInterval(startMinutes * 60)),
                                            end: block.end, expectedVersion: block.version)
        } catch {
            lastError = TaskListModel.message(for: error)
        }
        await reload()
    }

    /// Duration of a new block for `task` on `day` (default: the shown day), see `blockMinutes`: remaining
    /// effort (the day's recurring effort for recurring reminders, else the estimate), capped by six hours and
    /// the day's largest free slot; default duration without effort.
    func suggestedBlockMinutes(for task: TaskItem, on day: PlanDay? = nil) -> Int {
        let target = day ?? anchor
        let slot = days.first { $0.day == target }?.planInput.map { input in
            largestFreeSlot(input, fromMinutes: target == today ? minutes(now(), from: target.startDate(in: calendar)) : nil)
        } ?? 6 * 60
        return blockMinutes(estimate: effortMinutes(of: task, on: target), alreadyBlocked: blockedMinutes(of: task.id, on: target),
                            defaultMinutes: settings.defaultTaskMinutes, largestFreeSlot: slot)
    }

    /// Minutes of the task's blocks that count as work on it for `day` (default: today): for recurring
    /// reminders only the blocks of that day's occurrence (daily: that day, weekly: the six days before and
    /// that day …), otherwise the last 60 days and the future.
    func blockedMinutes(of id: TaskID, on day: PlanDay? = nil) -> Int {
        let window = sessionWindow(of: id, on: day ?? today)
        return blockedMinutes(in: blocks.futureBlocks(for: id, after: window.lowerBound), window: window)
    }

    private func blockedMinutes(in events: [CalendarEvent], window: Range<Date>) -> Int {
        events.filter { window.contains($0.start) }.reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
    }

    /// The period whose blocks count for `day`: the occurrence of a recurring reminder (ending with `day`),
    /// else from 60 days before today on without end.
    private func sessionWindow(of id: TaskID, on day: PlanDay) -> Range<Date> {
        if let rule = recurrenceRules[id],
           let start = TagwerkCore.sessionWindowStart(for: rule, today: day, calendar: calendar) {
            return start.startDate(in: calendar)..<day.adding(days: 1, calendar: calendar).startDate(in: calendar)
        }
        return today.adding(days: -60, calendar: calendar).startDate(in: calendar)..<Date.distantFuture
    }

    /// The effort of a task on `day` (default: today): the day's recurring effort for recurring reminders
    /// (`nil` when none is set), else the estimate.
    func effortMinutes(of task: TaskItem, on day: PlanDay? = nil) -> Int? {
        if let recurring = recurringItem(for: task, on: day ?? today) { return recurring.minutes > 0 ? recurring.minutes : nil }
        return task.estimateMinutes
    }

    private func updateSessions(open: [TaskItem]) {
        let all = blocks.blocksByTask(after: today.adding(days: -60, calendar: calendar).startDate(in: calendar))
        var progress: [TaskID: SessionProgress] = [:]
        var blocked: [TaskID: Int] = [:]
        for task in open {
            let window = sessionWindow(of: task.id, on: today)
            if let events = all[task.id] {
                let minutes = blockedMinutes(in: events, window: window)
                if minutes > 0 { blocked[task.id] = minutes }
            }
            guard let effort = effortMinutes(of: task), effort > 0, let events = all[task.id] else { continue }
            let blocked = blockedMinutes(in: events, window: window)
            if blocked > 0 { progress[task.id] = SessionProgress(blocked: blocked, estimate: effort) }
        }
        sessionProgress = progress
        blockedMinutesByTask = blocked
        toSchedule = sortedTasks(open.filter { progress[$0.id].map { $0.remaining >= 15 } ?? false }, calendar: calendar)
    }

    // MARK: Moving tasks between days (mockup WT1)

    /// The last move between days, for "Widerrufen".
    struct DayMove: Equatable {
        let taskID: TaskID
        let previousDay: PlanDay?
        /// Moved blocks with their former start.
        let blocks: [(id: String, start: Date)]
        /// Blocks this move created ("In den nächsten freien Block"); taking the move back deletes them.
        var createdBlockIDs: [String] = []
        var movedBlocks: Int { blocks.count }

        static func == (lhs: DayMove, rhs: DayMove) -> Bool {
            lhs.taskID == rhs.taskID && lhs.previousDay == rhs.previousDay && lhs.blocks.map(\.id) == rhs.blocks.map(\.id)
                && lhs.createdBlockIDs == rhs.createdBlockIDs
        }
    }

    private(set) var lastMove: DayMove?

    /// Sets the work day by dragging (user rule 2026-11-18): only the blocks on the former day that still lie
    /// ahead move along, at the same time, or into the next free stretch of the new day if that time is taken.
    func moveTask(_ id: TaskID, to day: PlanDay) async {
        let previous = planStore.assignment(for: id)
        var moved: [(id: String, start: Date)] = []
        if let previous, previous != day {
            let now = now()
            let origin = previous.startDate(in: calendar)
            let originEnd = previous.adding(days: 1, calendar: calendar).startDate(in: calendar)
            let target = days.first { $0.day == day }?.planInput
            var taken: [Range<Int>] = []
            for block in blocks.futureBlocks(for: id, after: max(now, origin)) where block.start < originEnd {
                let length = Int(block.end.timeIntervalSince(block.start) / 60)
                let startMinutes = minutes(block.start, from: origin)
                var slot = startMinutes..<(startMinutes + length)
                if var input = target {
                    input.blocks += taken
                    let free = freeGaps(input, fromMinutes: day == today ? minutes(now, from: day.startDate(in: calendar)) : nil)
                    if !free.contains(where: { $0.contains(slot.lowerBound) && $0.upperBound >= slot.upperBound }),
                       let next = nextFreeSlot(input, after: input.hours?.startMinutes ?? 0, minutes: length, fromMinutes: nil),
                       next.count >= length {
                        slot = next
                    }
                }
                do {
                    try blocks.moveBlock(block, to: day.startDate(in: calendar).addingTimeInterval(TimeInterval(slot.lowerBound * 60)))
                    moved.append((block.id, block.start))
                    taken.append(slot)
                } catch {
                    lastError = TaskListModel.message(for: error)
                }
            }
        }
        planStore.assign(id, to: day)
        lastMove = DayMove(taskID: id, previousDay: previous, blocks: moved)
        await reload()
    }

    // MARK: Planning tomorrow (plan-tomorrow, MP2)

    /// The evening entry "☾ Morgen planen" on today's capacity card.
    struct EveningEntry: Equatable {
        let day: PlanDay
        let freeMinutes: Int
        let leftCount: Int
    }

    /// Today has no working time left: a day off, or the clock has reached the end of today's work.
    private(set) var isTodayOver = false
    /// Once today is over: open tasks planned for today or due today (without a later day) and without a
    /// future time block ("Von heute übrig"). Recurring reminders are left out; their next occurrence follows.
    private(set) var leftFromToday: [TaskItem] = []
    /// The next working day within five days after today (decision 5).
    private(set) var nextPlanDay: PlanDay?
    /// Today's evening line, only while today is shown and over and a working day follows.
    private(set) var eveningEntry: EveningEntry?
    /// The last "Alle auf morgen", for one "Widerrufen".
    private(set) var lastMoveGroup: [DayMove]?

    /// "Überfällig" appears today and tomorrow, not on later days (decision 3).
    func showsOverdue(on day: PlanDay) -> Bool {
        day >= today && day <= today.adding(days: 1, calendar: calendar)
    }

    /// "Von heute übrig" belongs to the next planning day only (decisions 2 and 5): tomorrow, or the next working
    /// day when tomorrow is off.
    func leftovers(on day: PlanDay) -> [TaskItem] {
        isTodayOver && day == nextPlanDay ? leftFromToday : []
    }

    /// The row button of the panel ("Heute", "Morgen", "Einplanen"): commits the task to the shown day.
    func commitToShownDay(_ id: TaskID) async {
        await assign(id, to: anchor)
    }

    /// "Alle auf morgen": moves every task like `moveTask` (blocks go along) with one undo for all.
    func moveTasks(_ ids: [TaskID], to day: PlanDay) async {
        var moves: [DayMove] = []
        for id in ids {
            await moveTask(id, to: day)
            if let move = lastMove { moves.append(move) }
        }
        lastMove = nil
        lastMoveGroup = moves.isEmpty ? nil : moves
    }

    /// What "In den nächsten freien Block" did.
    struct LeftoverOutcome: Equatable {
        var placed: Int
        /// Part of `placed`: the block lies after the due day.
        var late: Int
        var unplaced: Int
    }

    /// "In den nächsten freien Block" (#163): every task gets a time block in the first free stretch from the next working
    /// day on (today only from now), up to its due day while there is room, never overlapping. One undo for all.
    func placeInFreeBlocks(_ ids: [TaskID]) async -> LeftoverOutcome {
        let tasks = ids.compactMap { id in taskList.items.first { $0.id == id && !$0.isCompleted } }
        guard !tasks.isEmpty else { return LeftoverOutcome(placed: 0, late: 0, unplaced: 0) }
        let today = self.today
        // Today plus the next five working days, looked for within the next two weeks.
        var lastDay = today
        var workingDays = 0
        for offset in 1...14 {
            let day = today.adding(days: offset, calendar: calendar)
            lastDay = day
            if (workHours(on: day)?.minutes ?? 0) > 0 { workingDays += 1 }
            if workingDays == 5 { break }
        }
        let inputs = await planInputs(in: today...lastDay)
        let firstDay = inputs.first { $0.day > today && ($0.hours?.minutes ?? 0) > 0 }?.day ?? today
        let items = tasks.map { task in
            LeftoverPlacement.Item(taskKey: task.id.key, minutes: suggestedBlockMinutes(for: task, on: firstDay),
                                   due: task.due.map { PlanDay($0) }, priority: task.priority)
        }
        let nowMinutes = minutes(now(), from: today.startDate(in: calendar))
        let result = LeftoverPlacement.place(tasks: items, days: inputs, nowMinutes: nowMinutes, today: today)
        var moves: [DayMove] = []
        var late = 0
        var failed = 0
        for placed in result.placed {
            guard let task = tasks.first(where: { $0.id.key == placed.taskKey }) else { continue }
            let previous = planStore.assignment(for: task.id)
            let start = placed.day.startDate(in: calendar).addingTimeInterval(TimeInterval(placed.range.lowerBound * 60))
            do {
                let block = try blocks.createBlock(for: task, start: start, minutes: placed.range.count)
                moves.append(DayMove(taskID: task.id, previousDay: previous, blocks: [], createdBlockIDs: [block.id]))
                if placed.lateForDue { late += 1 }
            } catch {
                lastError = TaskListModel.message(for: error)
                failed += 1
            }
        }
        lastMove = nil
        lastMoveGroup = moves.isEmpty ? nil : moves
        await reload()
        return LeftoverOutcome(placed: moves.count, late: late, unplaced: result.unplaced.count + failed)
    }

    func undoMoveGroup() async {
        guard let moves = lastMoveGroup else { return }
        lastMoveGroup = nil
        for move in moves.reversed() { await undo(move) }
    }

    /// Free time after accepting the day's block suggestions (mockup V1, plan-tomorrow F10): a block replaces the
    /// load its task already has on the day (assigned or due that day), so that load is not subtracted twice.
    static func freeAfterAccepting(free: Int, suggestions: [PlanSuggestion], counted: [String: Int]) -> Int {
        let blocks = suggestions.filter { $0.kind == .block }
        let added = blocks.reduce(0) { $0 + ($1.minutes ?? 0) }
        let replaced = Set(blocks.map(\.taskKey)).reduce(0) { $0 + (counted[$1] ?? 0) }
        return max(0, free - added + replaced)
    }

    func clearMoveGroupUndo() {
        lastMoveGroup = nil
    }

    /// Recomputes the evening state from the real today; independent of the shown range.
    private func updateEvening(open: [TaskItem], allAssignments: [TaskID: PlanDay], recurringIDs: Set<TaskID>) async {
        let today = self.today
        let current = now()
        let nowMinutes = minutes(current, from: today.startDate(in: calendar))
        if let hours = workHours(on: today), hours.minutes > 0 {
            isTodayOver = nowMinutes >= hours.endMinutes
        } else {
            isTodayOver = true
        }
        nextPlanDay = (1...5).lazy.map { today.adding(days: $0, calendar: self.calendar) }
            .first { (self.workHours(on: $0)?.minutes ?? 0) > 0 }
        leftFromToday = isTodayOver ? sortedTasks(open.filter { task in
            if recurringIDs.contains(task.id) { return false }
            let planned = allAssignments[task.id]
            let dueToday = task.due.map { PlanDay($0) == today } ?? false
            guard planned == today || (dueToday && (planned.map { $0 <= today } ?? true)) else { return false }
            return blocks.futureBlocks(for: task.id, after: current).isEmpty
        }, calendar: calendar) : []
        if scope == .day, anchor == today, isTodayOver, let next = nextPlanDay,
           let input = await planInputs(in: next...next).first {
            eveningEntry = EveningEntry(day: next, freeMinutes: max(0, input.availableMinutes - input.plannedMinutes),
                                        leftCount: leftFromToday.count)
        } else {
            eveningEntry = nil
        }
    }

    func undoMove() async {
        guard let move = lastMove else { return }
        lastMove = nil
        await undo(move)
    }

    /// Takes a move back: created blocks are deleted, moved blocks go to their former start, the task to its former day.
    func undo(_ move: DayMove) async {
        for id in move.createdBlockIDs {
            guard let block = calendarStore.event(id: id) else { continue }
            try? calendarStore.deleteBlock(id: block.id, expectedVersion: block.version)
        }
        for (id, start) in move.blocks {
            guard let block = calendarStore.event(id: id) else { continue }
            try? blocks.moveBlock(block, to: start)
        }
        if let previous = move.previousDay { planStore.assign(move.taskID, to: previous) } else { planStore.unassign(move.taskID) }
        await reload()
    }

    func clearMoveUndo() {
        lastMove = nil
    }

    // MARK: Duplicating blocks (mockup DU1)

    /// Where "Duplizieren" puts a copy (minutes of the block's day): the next free stretch after the
    /// original (with the buffer); the duration is the time still open, or the default duration when the
    /// estimate is already planned (user rule 2026-11-18).
    func duplicateTarget(for block: CalendarEvent) -> Range<Int>? {
        guard let task = linkedTask(eventID: block.id) else { return nil }
        let day = PlanDay(date: block.start, calendar: calendar)
        guard let input = days.first(where: { $0.day == day })?.planInput else { return nil }
        let dayStart = day.startDate(in: calendar)
        let remaining = effortMinutes(of: task, on: day).map { $0 - blockedMinutes(of: task.id, on: day) } ?? 0
        let length = remaining >= 15 ? suggestedBlockMinutes(for: task, on: day) : settings.defaultTaskMinutes
        return nextFreeSlot(input, after: minutes(block.end, from: dayStart), minutes: length,
                            fromMinutes: day == today ? minutes(now(), from: dayStart) : nil)
    }

    func duplicateBlock(_ block: CalendarEvent) async {
        guard let task = linkedTask(eventID: block.id), let target = duplicateTarget(for: block) else { return }
        let dayStart = PlanDay(date: block.start, calendar: calendar).startDate(in: calendar)
        do {
            lastDuplicate = try blocks.createBlock(for: task, start: dayStart.addingTimeInterval(TimeInterval(target.lowerBound * 60)),
                                                   minutes: target.count)
        } catch {
            lastError = TaskListModel.message(for: error)
        }
        await reload()
    }

    func undoDuplicate() async {
        guard let copy = lastDuplicate else { return }
        lastDuplicate = nil
        await deleteBlock(copy)
    }

    func clearDuplicateUndo() {
        lastDuplicate = nil
    }

    /// Deletes a block; the task keeps its planned day.
    func deleteBlock(_ block: CalendarEvent) async {
        do {
            try calendarStore.deleteBlock(id: block.id, expectedVersion: block.version)
        } catch {
            lastError = TaskListModel.message(for: error)
        }
        await reload()
    }

    /// Free stretches of the day for dropping tasks (today from now on), around events, blocks, lunch and buffer.
    func gaps(for plan: DayPlan) -> [Range<Int>] {
        guard let hours = workHours(on: plan.day) else { return [] }
        let busy = busyIntervals(events: plan.events + plan.blocks, on: plan.day, calendar: calendar, excluding: [])
        let lunch = lunch(on: plan.day)
        let from = plan.day == today ? minutes(now(), from: plan.day.startDate(in: calendar)) : nil
        return freeGaps(hours: hours, busy: busy, lunch: lunch, buffer: settings.bufferMinutes, from: from)
    }

    private func dayLength(_ day: PlanDay) -> Int {
        Int(day.adding(days: 1, calendar: calendar).startDate(in: calendar).timeIntervalSince(day.startDate(in: calendar)) / 60)
    }

    // MARK: Events in all calendars (design §13.10)

    var writableCalendars: [ListInfo] { calendarStore.writableCalendars() }

    func calendarTitle(_ id: String) -> String? {
        calendarStore.eventCalendars().first { $0.id == id }?.title
    }

    /// "überschneidet …" when a planned event overlaps others on its day, else "passt in die freie Zeit".
    func fitText(start: Date, end: Date, excluding eventID: String?) -> String {
        switch overlap(start: start, end: end, excluding: eventID) {
        case .none: String(localized: "passt in die freie Zeit")
        case .one(let title): String(localized: "überschneidet „\(title)“")
        case .several(let count): String(localized: "überschneidet \(count) Termine")
        }
    }

    enum Overlap: Equatable {
        case none
        case one(String)
        case several(Int)
    }

    /// Timed events that overlap the given time, for "passt in die freie Zeit" or "überschneidet …".
    func overlap(start: Date, end: Date, excluding eventID: String?) -> Overlap {
        let interval = DateInterval(start: start, end: max(start, end))
        let overlapping = calendarStore.events(in: interval, calendarIDs: nil)
            .filter { !$0.isAllDay && $0.id != eventID && $0.start < end && $0.end > start }
        switch overlapping.count {
        case 0: return .none
        case 1: return .one(overlapping[0].title)
        default: return .several(overlapping.count)
        }
    }

    /// The alarms of an event (one occurrence for a series), shown in the event editor.
    func alarms(ofEvent id: String) -> [ReminderOffset] { calendarStore.alarms(ofEvent: id) }

    /// The reminders a new event starts with in the editor ("Termine" in the default reminders).
    func defaultEventReminders(isAllDay: Bool) -> [ReminderOffset] {
        settings.reminderDefaults.offsets(for: .event, isAllDay: isAllDay)
    }

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

    // MARK: Events for the assistant (issue #118): errors go back to the model instead of `lastError`.

    var eventCalendars: [ListInfo] { calendarStore.eventCalendars() }

    func event(id: String) -> CalendarEvent? { calendarStore.event(id: id) }

    func createEventReportingErrors(_ draft: EventDraft) async throws -> CalendarEvent {
        let created = try calendarStore.createEvent(draft)
        await reload()
        return created
    }

    func updateEventReportingErrors(_ event: CalendarEvent, with draft: EventDraft, span: EventSpan) async throws -> CalendarEvent {
        let updated = try calendarStore.updateEvent(id: event.id, with: draft, span: span, expectedVersion: event.version)
        await reload()
        return updated
    }

    func deleteEventReportingErrors(_ event: CalendarEvent, span: EventSpan) async throws {
        try calendarStore.deleteEvent(id: event.id, span: span, expectedVersion: event.version)
        await reload()
    }

    /// "Getrennt anzeigen": undoes the merges into this event, so its copies appear again.
    func showSeparately(_ event: CalendarEvent) async {
        for suggestion in appliedMerges[event.id] ?? [] {
            marks.decide(suggestion, merge: false, always: false)
        }
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

    /// Repeating tasks whose effort is reserved: reminders with a rule (read from Reminders, all lists) and open
    /// tasks of other sources with a repetition (local tasks). A reminder counts once even when the task list
    /// carries its rule too.
    private func recurringSeries(open: [TaskItem]) async -> [RecurringSeries] {
        let reminders = await planningReminders()
        let fromReminders = reminders.compactMap { record in
            record.recurrence.map { RecurringSeries(id: TaskID(source: .reminders, rawValue: record.id), title: record.title, recurrence: $0) }
        }
        let others = open.compactMap { task in
            task.id.source == .reminders ? nil : task.recurrence.map { RecurringSeries(id: task.id, title: task.title, recurrence: $0) }
        }
        var seen: Set<TaskID> = []
        return (fromReminders + others).filter { seen.insert($0.id).inserted }
    }

    private func dayPlan(_ day: PlanDay, events: [CalendarEvent], links taskLinks: [String: TaskID], deadlines: [ImportantDeadline],
                         assignments: [TaskID: PlanDay], overrides: [PlanDay: DayOverride], tasksByID: [TaskID: TaskItem],
                         series: [RecurringSeries], recurringIDs: Set<TaskID>, open: [TaskItem],
                         allAssignments: [TaskID: PlanDay], deadlineIDs: Set<String>) -> DayPlan {
        // A deadline event linked to a task is the task's anchor (AI, event sheet), not work on it: it stays an event,
        // counts as busy and is no time block (decision 5, plan deadline-marking Task 10).
        let links = taskLinks.filter { !deadlineIDs.contains($0.key) }
        let start = day.startDate(in: calendar)
        let end = day.adding(days: 1, calendar: calendar).startDate(in: calendar)
        let dayEvents = events.filter { $0.end > start && $0.start < end }.sorted { $0.start < $1.start }
        let linkedEvents = dayEvents.filter { links[$0.id] != nil && !$0.isAllDay }
        let tasksWithBlocks = Set(linkedEvents.compactMap { links[$0.id] })
        // Tasks with a time block on this day appear in the timeline only, not as "planned without time".
        let assigned = assignments.filter { $0.value == day && !tasksWithBlocks.contains($0.key) }
            .compactMap { tasksByID[$0.key] }
        let assignedSorted = sortedTasks(assigned, calendar: calendar)

        // Due on this day (today or later) and not committed to a day from today on; an assignment before
        // today is stale and does not count (plan-tomorrow, F1, decision 11).
        let openToday = day >= today
            ? sortedTasks(open.filter { task in
                allAssignments[task.id] != day && !tasksWithBlocks.contains(task.id)
                    && task.due.map { PlanDay($0) == day } == true
                    && (allAssignments[task.id].map { $0 < today } ?? true)
            }, calendar: calendar)
            : []

        var planned = linkedEvents.reduce(0) { total, event in
            let from = max(event.start, start), to = min(event.end, end)
            return total + max(0, Int(to.timeIntervalSince(from) / 60))
        }
        var estimated = 0
        var counted: [String: Int] = [:]
        for task in assignedSorted + openToday where !tasksWithBlocks.contains(task.id) {
            // Repeating tasks count once, through their recurring effort.
            if recurringIDs.contains(task.id) { continue }
            let minutes = task.estimateMinutes ?? settings.defaultTaskMinutes
            if task.estimateMinutes == nil { estimated += 1 }
            planned += minutes
            counted[task.id.key, default: 0] += minutes
        }
        let hours = TagwerkCore.workHours(on: day, schedule: settings.weekSchedule, overrides: overrides, calendar: calendar)
        let linkedIDs = Set(links.keys).union(copiesOfLinked(dayEvents, links: links))
        // A block for a recurring reminder is that reminder's work: its reserved effort counts only for the
        // part the blocks of the day do not cover (otherwise the time would count twice).
        var blockMinutesByTask: [TaskID: Int] = [:]
        for event in linkedEvents {
            guard let id = links[event.id] else { continue }
            let from = max(event.start, start), to = min(event.end, end)
            blockMinutesByTask[id, default: 0] += max(0, Int(to.timeIntervalSince(from) / 60))
        }
        let coveredRecurring = series.reduce(0) { total, item in
            guard let blocked = blockMinutesByTask[item.id], let reserved = efforts.minutes(for: item.id, on: day) else { return total }
            return total + min(reserved, blocked)
        }
        let recurringMinutes = max(0, efforts.reservedMinutes(on: day, series: series, calendar: calendar) - coveredRecurring)
        var input = CapacityInput(
            hours: hours,
            lunchStartMinutes: lunch(on: day)?.lowerBound ?? 0, lunchMinutes: lunch(on: day)?.count ?? 0,
            bufferMinutes: settings.bufferMinutes,
            busyIntervals: busyIntervals(events: dayEvents, on: day, calendar: calendar, excluding: linkedIDs),
            recurringMinutes: recurringMinutes,
            plannedMinutes: planned, estimatedCount: estimated
        )
        // For the AI, the reserved effort of recurring reminders is the load of those tasks: a block for one
        // of them replaces its reservation instead of adding to it.
        var aiCounted = counted
        var reservedLoad = 0
        for item in series {
            let key = item.id
            guard let reserved = efforts.minutes(for: key, on: day), reserved > 0,
                  !occurrences(of: item.recurrence, in: day...day, calendar: calendar).isEmpty else { continue }
            let open = max(0, reserved - (blockMinutesByTask[key] ?? 0))
            guard open > 0 else { continue }
            aiCounted[key.key, default: 0] += open
            reservedLoad += open
        }
        let planInput = PlanInputDay(
            day: day, hours: hours, lunch: lunch(on: day), events: dayEvents, linkedEventIDs: linkedIDs,
            deadlineCalendarIDs: Set(settings.deadlineCalendarIDs ?? []),
            blocks: linkedEvents.map { minutes($0.start, from: start)..<minutes($0.end, from: start) },
            recurringMinutes: max(0, recurringMinutes - reservedLoad), plannedMinutes: planned + reservedLoad,
            bufferMinutes: settings.bufferMinutes, calendar: calendar, countedTaskMinutes: aiCounted,
            deadlineEventIDs: deadlineIDs
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
        let recurring = series.compactMap { item -> RecurringItem? in
            guard !occurrences(of: item.recurrence, in: day...day, calendar: calendar).isEmpty,
                  let minutes = efforts.minutes(for: item.id, on: day), minutes > 0 else { return nil }
            return RecurringItem(taskID: item.id, title: item.title, minutes: minutes, isDone: efforts.isDone(task: item.id, day: day))
        }
        // Merging only affects the display; capacity above used every event (overlaps are unified).
        // Merged copies were removed in `markedEvents` (only after the user's answer, design §13.15 M1).
        let shown = dayEvents
        return DayPlan(day: day, capacity: capacity(input), deadlines: deadlines.filter { $0.day == day },
                       events: shown.filter { links[$0.id] == nil }, blocks: shown.filter { links[$0.id] != nil && !$0.isAllDay },
                       assigned: assignedSorted, openToday: openToday, links: links.filter { id, _ in linkedEvents.contains { $0.id == id } },
                       isPastDue: pastDue, recurring: recurring, planInput: planInput, isPast: day < today)
    }

    /// Unlinked copies (same title and time in another calendar) of linked events: their time is already
    /// counted as the task's planned load (design §13.11).
    private func copiesOfLinked(_ events: [CalendarEvent], links: [String: TaskID]) -> Set<String> {
        let linked = events.filter { links[$0.id] != nil }
        return Set(events.filter { event in
            links[event.id] == nil && linked.contains {
                $0.calendarID != event.calendarID && $0.start == event.start && $0.end == event.end
                    && $0.isAllDay == event.isAllDay
                    && $0.title.lowercased().split(whereSeparator: \.isWhitespace) == event.title.lowercased().split(whereSeparator: \.isWhitespace)
            }
        }.map(\.id))
    }

    private func minutes(_ date: Date, from dayStart: Date) -> Int {
        Int(date.timeIntervalSince(dayStart) / 60)
    }

    /// Deadlines from the shown day over the next 14 days: deadline calendars, marked events (also from calendars that
    /// are not shown) and tasks. Also updates the preparation sums and the keyword suggestions (DL3) of that window.
    private func loadUpcomingDeadlines(open: [TaskItem]) -> [ImportantDeadline] {
        let range = anchor...anchor.adding(days: 13, calendar: calendar)
        let interval = DateInterval(start: range.lowerBound.startDate(in: calendar),
                                    end: range.upperBound.adding(days: 1, calendar: calendar).startDate(in: calendar))
        let deadlineCalendars = Set(settings.deadlineCalendarIDs ?? [])
        let readable = readableCalendarIDs()
        let markCalendars = Set(deadlineMarks.marks().map(\.calendarID))
        let events = calendarStore.events(in: interval, calendarIDs: readable.map { $0.union(deadlineCalendars).union(markCalendars) })
        let marked = deadlineMarks.markedIDs(in: events)
        let deadlines = importantDeadlines(tasks: open, events: events, deadlineCalendarIDs: deadlineCalendars,
                                           markedEventIDs: marked, in: range, calendar: calendar)
        let current = now()
        // Time blocks and events linked to a task carry task titles ("Abgabe …"); they are work, not deadlines.
        let linked = Set(resolveLinks(events: events, tasks: open, manual: blocks.links.manualLinks()).map(\.eventID))
        let suggestionCandidates = events.filter { event in
            event.end > current && (readable?.contains(event.calendarID) ?? true)
                && event.url.flatMap(TaskLinkURL.parse) == nil && !linked.contains(event.id)
        }
        deadlineSuggestions = TagwerkCore.deadlineSuggestions(
            events: suggestionCandidates, excludingEventIDs: marked.union(deadlineMarks.dismissedSuggestionIDs()),
            excludingCalendarIDs: deadlineCalendars.union(settings.planCalendarID.map { [$0] } ?? []))
        preparation = preparationSummaries(for: deadlines)
        return deadlines
    }

    /// Preparation sums of the deadlines that have linked events; keeps title and moment on their links current.
    private func preparationSummaries(for deadlines: [ImportantDeadline]) -> [String: PreparationSummary] {
        let links = deadlineMarks.allLinks()
        let keys = Set(links.map(\.deadlineKey))
        let linked = deadlines.filter { keys.contains($0.preparationKey) }
        guard !linked.isEmpty else { return [:] }
        for deadline in linked {
            deadlineMarks.refreshDeadline(key: deadline.preparationKey, title: deadline.title, until: deadlineMoment(deadline))
        }
        let current = now()
        let end = linked.map(deadlineMoment).max() ?? current
        guard end > current else { return [:] }
        let events = calendarStore.events(in: DateInterval(start: current, end: end), calendarIDs: preparationCalendarIDs())
        var result: [String: PreparationSummary] = [:]
        for deadline in linked {
            let prepared = deadlineMarks.linkedEvents(forDeadline: deadline.preparationKey, among: events)
            result[deadline.preparationKey] = preparationSummary(prepared, now: current, deadline: deadlineMoment(deadline))
        }
        return result
    }

    /// Calendars preparation events come from: the read calendars plus those of existing links; `nil` for all.
    private func preparationCalendarIDs() -> Set<String>? {
        readableCalendarIDs().map { $0.union(deadlineMarks.allLinks().map(\.calendarID)) }
    }

    /// Deadline calendar events and marked events among `events`.
    private func deadlineIDs(in events: [CalendarEvent], marked: Set<String>) -> Set<String> {
        let deadlineCalendars = Set(settings.deadlineCalendarIDs ?? [])
        return marked.union(events.filter { deadlineCalendars.contains($0.calendarID) }.map(\.id))
    }

    /// Finds the marks of today and later again (±14 days around each), follows moved events and returns the marks that
    /// are gone. Only calendars EventKit lists take part: without calendar access every mark stays as it is.
    private func resolveDeadlineMarks() -> [OrphanedMark] {
        let marks = deadlineMarks.marks()
        guard !marks.isEmpty else { return [] }
        let listed = Set(calendarStore.eventCalendars().map(\.id))
        let calendars = Set(marks.map(\.calendarID)).intersection(listed)
        guard !calendars.isEmpty else { return [] }
        let todayStart = today.startDate(in: calendar)
        let margin = TimeInterval(eventReferenceTitleWindowDays * 86_400)
        let upcoming = marks.filter { !$0.isSeries && $0.start >= todayStart }
        var lower = todayStart.addingTimeInterval(-margin)
        var upper = todayStart.addingTimeInterval(60 * 86_400)
        if let last = upcoming.map(\.start).max() { upper = max(upper, last.addingTimeInterval(margin)) }
        if let first = upcoming.map(\.start).min() { lower = max(lower, min(todayStart, first.addingTimeInterval(-margin))) }
        let window = DateInterval(start: lower, end: max(upper, lower))
        let events = calendarStore.events(in: window, calendarIDs: calendars)
        let resolution = deadlineMarks.resolve(events: events, readCalendarIDs: calendars, window: window, now: now())
        return resolution.orphans.filter { $0.start >= todayStart }
    }

    /// The moment a deadline falls due: its time, else the end of its day.
    func deadlineMoment(_ deadline: ImportantDeadline) -> Date {
        deadline.time ?? deadline.day.adding(days: 1, calendar: calendar).startDate(in: calendar)
    }

    /// The event a search hit stands for, read the way "Planen" reads its days: the day of the hit in the readable
    /// calendars, so the opened event carries the ID that links and deadline marks expect. `nil` when it changed.
    func resolveEvent(matching hit: CalendarEvent) -> CalendarEvent? {
        let day = PlanDay(date: hit.start, calendar: calendar)
        let interval = DateInterval(start: day.startDate(in: calendar),
                                    end: day.adding(days: 1, calendar: calendar).startDate(in: calendar))
        return SearchEventResolver.resolve(hit, among: calendarStore.events(in: interval, calendarIDs: readableCalendarIDs()))
    }

    /// Selected calendars plus plan and deadline calendars; `nil` (all) when nothing is selected.
    func readableCalendarIDs() -> Set<String>? {
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
