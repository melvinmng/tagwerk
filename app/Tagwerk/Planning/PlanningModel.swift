import Foundation
import Observation
import RemindersKit
import TagwerkCore

extension PlanScope {
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
        case .lunch: "Mittagspause"
        case .gap: "frei"
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
    /// Repetition rules of recurring reminders (reminder ID → rule), for their session window.
    private var recurrenceRules: [String: RecurrenceRule] = [:]
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

    init(taskList: TaskListModel, calendarStore: CalendarStore, reminderStore: ReminderStore, planStore: PlanStore,
         efforts: RecurringEffortStore, blocks: BlockPlanner, settings: AppSettings, marks: EventMarkStore,
         suggestions: SuggestionStore? = nil, now: @escaping () -> Date = Date.init, calendar: Calendar = .tagwerk) {
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

    func reload() async {
        let range = self.range
        let open = taskList.items.filter { !$0.isCompleted }
        pruneAssignments(open: open)

        let reminders = reminderStore.accessState == .fullAccess ? await reminderStore.openReminders(in: nil) : []
        let recurringIDs = Set(reminders.filter { $0.recurrence != nil }.map(\.id))
        let interval = DateInterval(start: range.lowerBound.startDate(in: calendar),
                                    end: range.upperBound.adding(days: 1, calendar: calendar).startDate(in: calendar))
        let (events, suggestions) = markedEvents(calendarStore.events(in: interval, calendarIDs: readableCalendarIDs()))
        mergeSuggestions = suggestions
        let resolved = resolveLinks(events: events, tasks: open, manual: blocks.links.manualLinks())
        resolvedLinks = Dictionary(resolved.map { ($0.eventID, $0) }, uniquingKeysWith: { first, _ in first })
        recurringReminderIDs = recurringIDs
        recurrenceRules = Dictionary(reminders.compactMap { record in record.recurrence.map { (record.id, $0.rule) } },
                                     uniquingKeysWith: { first, _ in first })
        updateSessions(open: open)
        let links = resolvedLinks.mapValues(\.taskID)
        let deadlines = importantDeadlines(tasks: open, events: events,
                                           deadlineCalendarIDs: Set(settings.deadlineCalendarIDs ?? []),
                                           in: range, calendar: calendar)
        let assignments = planStore.assignments(in: range)
        let overrides = planStore.overrides(in: range)
        let tasksByID = Dictionary(open.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let everything = PlanDay(year: 1, month: 1, day: 1)...PlanDay(year: 9999, month: 12, day: 31)
        let allAssignments = planStore.assignments(in: everything)

        suggestionBatches = suggestionStore?.batches(in: range) ?? []
        let suggestionsByDay = Dictionary(grouping: suggestionBatches.flatMap(\.suggestions), by: \.day)
        var result: [DayPlan] = []
        var day = range.lowerBound
        while day <= range.upperBound {
            var plan = dayPlan(day, events: events, links: links, deadlines: deadlines, assignments: assignments,
                               overrides: overrides, tasksByID: tasksByID, reminders: reminders,
                               recurringIDs: recurringIDs, open: open, allAssignments: allAssignments)
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
            await setRecurringEffort(edit.recurringMinutes, reminderID: task.id.rawValue, day: today, forAll: edit.recurringForAll)
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
        guard let day = planStore.assignment(for: id) else { return "noch nicht eingeplant" }
        return "Arbeitstag: " + day.startDate(in: calendar).formatted(.dateTime.weekday(.abbreviated).day().month())
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

    func allDayEvents(for plan: DayPlan) -> [CalendarEvent] {
        let deadlineCalendars = Set(settings.deadlineCalendarIDs ?? [])
        return (plan.events + plan.blocks).filter { $0.isAllDay && !deadlineCalendars.contains($0.calendarID) }
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
        let (marked, _) = markedEvents(read)
        let markedIDs = Set(marked.map(\.id))
        let deadlineCalendars = Set(settings.deadlineCalendarIDs ?? [])
        var shownIDs = Set<String>()
        var day = today
        while day < today.adding(days: 7, calendar: calendar) {
            let dayStart = day.startDate(in: calendar), dayEnd = day.adding(days: 1, calendar: calendar).startDate(in: calendar)
            let dayEvents = marked.filter { $0.end > dayStart && $0.start < dayEnd }
            let merged = dayEvents
            shownIDs.formUnion(merged.filter { !($0.isAllDay && deadlineCalendars.contains($0.calendarID)) }.map(\.id))
            day = day.adding(days: 1, calendar: calendar)
        }
        return calendarStore.eventCalendars().map { info in
            let own = all.filter { $0.calendarID == info.id }
            let isRead = readable?.contains(info.id) ?? true
            let hiddenByPlaceholder = isRead ? own.filter { !markedIDs.contains($0.id) }.count : 0
            let shown = isRead ? own.filter { shownIDs.contains($0.id) }.count : 0
            let asDeadline = isRead && deadlineCalendars.contains(info.id) ? own.filter(\.isAllDay).count : 0
            return CalendarDiagnostic(calendarID: info.id, title: info.title, kind: info.kind, isRead: isRead,
                                      isDeadlineCalendar: deadlineCalendars.contains(info.id), events: own.count, shown: shown,
                                      hiddenByMerge: isRead ? max(0, own.count - shown - asDeadline - hiddenByPlaceholder) : 0,
                                      hiddenByPlaceholderDecision: hiddenByPlaceholder, shownAsDeadline: asDeadline)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func decideMerge(_ suggestion: MergeSuggestion, merge: Bool, always: Bool) async {
        marks.decide(suggestion, merge: merge, always: always)
        await reload()
    }

    /// Applies Tagwerk's free marks and accepted merges; returns the undecided merge suggestions.
    private func markedEvents(_ raw: [CalendarEvent]) -> ([CalendarEvent], [MergeSuggestion]) {
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
        for suggestion in TagwerkCore.mergeSuggestions(events, excluding: deadlineCalendars) {
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

    /// Length for a new block: what is left of the estimate after existing blocks, else the estimate,
    /// and the default duration for tasks without an estimate.
    /// Duration of a new block for `task` on `day` (default: the shown day), see `blockMinutes`:
    /// remaining estimate, capped by six hours and the day's largest free slot; default duration without estimate.
    func suggestedBlockMinutes(for task: TaskItem, on day: PlanDay? = nil) -> Int {
        let target = day ?? anchor
        let slot = days.first { $0.day == target }?.planInput.map { input in
            largestFreeSlot(input, fromMinutes: target == today ? minutes(now(), from: target.startDate(in: calendar)) : nil)
        } ?? 6 * 60
        return blockMinutes(estimate: task.estimateMinutes, alreadyBlocked: blockedMinutes(of: task.id),
                            defaultMinutes: settings.defaultTaskMinutes, largestFreeSlot: slot)
    }

    /// Minutes of the task's blocks that count as work on it: for recurring reminders only the current
    /// period (daily: today, weekly: the last six days and today …), otherwise the last 60 days and the future.
    func blockedMinutes(of id: TaskID) -> Int {
        blockedMinutes(of: id, in: blocks.futureBlocks(for: id, after: sessionWindowStart(of: id)))
    }

    private func blockedMinutes(of id: TaskID, in events: [CalendarEvent]) -> Int {
        let since = sessionWindowStart(of: id)
        return events.filter { $0.start >= since }.reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
    }

    private func sessionWindowStart(of id: TaskID) -> Date {
        if id.source == .reminders, let rule = recurrenceRules[id.rawValue],
           let start = TagwerkCore.sessionWindowStart(for: rule, today: today, calendar: calendar) {
            return start.startDate(in: calendar)
        }
        return today.adding(days: -60, calendar: calendar).startDate(in: calendar)
    }

    /// The effort of a task: the day's recurring effort for recurring reminders, else the estimate.
    func effortMinutes(of task: TaskItem) -> Int? {
        if let recurring = recurringItem(for: task, on: today) { return recurring.minutes }
        return task.estimateMinutes
    }

    private func updateSessions(open: [TaskItem]) {
        let all = blocks.blocksByTask(after: today.adding(days: -60, calendar: calendar).startDate(in: calendar))
        var progress: [TaskID: SessionProgress] = [:]
        for task in open {
            guard let effort = effortMinutes(of: task), effort > 0, let events = all[task.id] else { continue }
            let blocked = blockedMinutes(of: task.id, in: events)
            if blocked > 0 { progress[task.id] = SessionProgress(blocked: blocked, estimate: effort) }
        }
        sessionProgress = progress
        toSchedule = sortedTasks(open.filter { progress[$0.id].map { $0.remaining >= 15 } ?? false }, calendar: calendar)
    }

    // MARK: Moving tasks between days (mockup WT1)

    /// The last move between days, for "Widerrufen".
    struct DayMove: Equatable {
        let taskID: TaskID
        let previousDay: PlanDay?
        /// Moved blocks with their former start.
        let blocks: [(id: String, start: Date)]
        var movedBlocks: Int { blocks.count }

        static func == (lhs: DayMove, rhs: DayMove) -> Bool {
            lhs.taskID == rhs.taskID && lhs.previousDay == rhs.previousDay && lhs.blocks.map(\.id) == rhs.blocks.map(\.id)
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

    func undoMove() async {
        guard let move = lastMove else { return }
        lastMove = nil
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
    /// original; the duration is the time still open, or the original duration when nothing is open.
    func duplicateTarget(for block: CalendarEvent) -> Range<Int>? {
        guard let task = linkedTask(eventID: block.id) else { return nil }
        let day = PlanDay(date: block.start, calendar: calendar)
        guard let input = days.first(where: { $0.day == day })?.planInput else { return nil }
        let dayStart = day.startDate(in: calendar)
        let original = Int(block.end.timeIntervalSince(block.start) / 60)
        let remaining = effortMinutes(of: task).map { $0 - blockedMinutes(of: task.id) } ?? 0
        let length = remaining >= 15 ? suggestedBlockMinutes(for: task, on: day) : original
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
        let interval = DateInterval(start: start, end: max(start, end))
        let overlapping = calendarStore.events(in: interval, calendarIDs: nil)
            .filter { !$0.isAllDay && $0.id != eventID && $0.start < end && $0.end > start }
        if let first = overlapping.first {
            return overlapping.count == 1 ? "überschneidet „\(first.title)“" : "überschneidet \(overlapping.count) Termine"
        }
        return "passt in die freie Zeit"
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
        let assignedSorted = sortedTasks(assigned, calendar: calendar)

        let openToday = day == today
            ? sortedTasks(open.filter { task in
                allAssignments[task.id] != day && !tasksWithBlocks.contains(task.id)
                    && task.due.map { PlanDay($0) == day } == true
                    && (allAssignments[task.id].map { $0 < day } ?? true)
            }, calendar: calendar)
            : []

        var planned = linkedEvents.reduce(0) { total, event in
            let from = max(event.start, start), to = min(event.end, end)
            return total + max(0, Int(to.timeIntervalSince(from) / 60))
        }
        var estimated = 0
        var counted: [String: Int] = [:]
        for task in assignedSorted + openToday where !tasksWithBlocks.contains(task.id) {
            // Recurring reminders count once, through their recurring effort.
            if task.id.source == .reminders, recurringIDs.contains(task.id.rawValue) { continue }
            let minutes = task.estimateMinutes ?? settings.defaultTaskMinutes
            if task.estimateMinutes == nil { estimated += 1 }
            planned += minutes
            counted[task.id.key, default: 0] += minutes
        }
        let hours = TagwerkCore.workHours(on: day, schedule: settings.weekSchedule, overrides: overrides, calendar: calendar)
        let linkedIDs = Set(links.keys).union(copiesOfLinked(dayEvents, links: links))
        let recurringMinutes = efforts.reservedMinutes(on: day, reminders: reminders, calendar: calendar)
        var input = CapacityInput(
            hours: hours,
            lunchStartMinutes: lunch(on: day)?.lowerBound ?? 0, lunchMinutes: lunch(on: day)?.count ?? 0,
            bufferMinutes: settings.bufferMinutes,
            busyIntervals: busyIntervals(events: dayEvents, on: day, calendar: calendar, excluding: linkedIDs),
            recurringMinutes: recurringMinutes,
            plannedMinutes: planned, estimatedCount: estimated
        )
        let planInput = PlanInputDay(
            day: day, hours: hours, lunch: lunch(on: day), events: dayEvents, linkedEventIDs: linkedIDs,
            deadlineCalendarIDs: Set(settings.deadlineCalendarIDs ?? []),
            blocks: linkedEvents.map { minutes($0.start, from: start)..<minutes($0.end, from: start) },
            recurringMinutes: recurringMinutes, plannedMinutes: planned, bufferMinutes: settings.bufferMinutes,
            calendar: calendar, countedTaskMinutes: counted
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
