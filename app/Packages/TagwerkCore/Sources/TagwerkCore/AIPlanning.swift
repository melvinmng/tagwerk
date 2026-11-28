import Foundation

// AI planning rules (design §8.2, §11.7, §11.10): what goes to the model and how its answer is
// checked locally before anything is shown. Pure functions, no AI and no I/O.

/// The planning view and the period an AI plan covers.
public enum PlanScope: String, Sendable, Codable, CaseIterable, Hashable {
    case day, week, month
}

// MARK: - Input

/// An event of a day as the model sees it.
public struct PlanInputEvent: Sendable, Hashable {
    public var title: String
    /// Minutes since midnight, clipped to the day; `nil` for all-day events.
    public var start: Int?
    public var end: Int?
    public var allDay: Bool
    /// Counts as occupied time (not free, not declined, not linked to a task).
    public var busy: Bool
    /// From a deadline calendar or marked as a deadline.
    public var deadline: Bool
    /// Linked to a task: it counts as that task's planned load.
    public var linkedToTask: Bool
    /// The way to an event with a place. It carries no place: the model only learns that the time is taken.
    public var travel = false
}

/// One day of the planning period with everything the checks need.
public struct PlanInputDay: Sendable, Hashable {
    public var day: PlanDay
    /// `nil` on a day off.
    public var hours: WorkHours?
    /// Lunch of this day in minutes since midnight.
    public var lunch: Range<Int>?
    /// Occupied minutes from busy, unlinked events and the travel time (without buffer).
    public var busy: [Range<Int>]
    /// The travel time part of `busy`; the capacity counts it without buffer.
    public var travel: [Range<Int>]
    /// The busy events alone, to compute the capacity again for other hours.
    var eventBusy: [Range<Int>]
    /// Existing time blocks and other task-linked events.
    public var blocks: [Range<Int>]
    public var bufferMinutes: Int
    /// Load for the AI checks: tasks without a time block (assigned, due that day) plus the part of the time blocks that
    /// uses free working time. Effort that recurring tasks only reserve is not load; their time blocks are. The free
    /// time shown to the user (`freeMinutes`) does not count the tasks without a time block.
    public var plannedMinutes: Int
    /// The part of the time blocks that uses free working time; tasks without a time block are not part of it.
    public var blockMinutes: Int
    /// Part of `plannedMinutes` per task (`TaskID.key`), for tasks counted without a block (assigned,
    /// due today). A new block or assignment for such a task replaces this load instead of adding to it.
    public var countedTaskMinutes: [String: Int]
    /// Working time left for tasks after events with buffer, lunch and travel time.
    public var availableMinutes: Int
    public var events: [PlanInputEvent]

    /// Free working time of the day as the capacity card shows it: tasks without a time block take none of it.
    public var freeMinutes: Int { availableMinutes - blockMinutes }

    /// Builds a day from calendar events; occupied time and capacity come from `busyIntervals` and `capacity`.
    public init(day: PlanDay, hours: WorkHours?, lunch: Range<Int>?, events: [CalendarEvent], linkedEventIDs: Set<String>,
                deadlineCalendarIDs: Set<String>, blocks: [Range<Int>], untimedPlannedMinutes: Int,
                bufferMinutes: Int, calendar: Calendar, countedTaskMinutes: [String: Int] = [:],
                deadlineEventIDs: Set<String> = [], travel: [Range<Int>] = []) {
        self.day = day
        self.countedTaskMinutes = countedTaskMinutes
        self.hours = hours
        self.lunch = lunch
        self.blocks = blocks
        self.bufferMinutes = bufferMinutes
        let busy = busyIntervals(events: events, on: day, calendar: calendar, excluding: linkedEventIDs)
        self.eventBusy = busy
        self.travel = travel
        self.busy = busy + travel
        let dayCapacity = capacity(CapacityInput(
            hours: hours, lunchStartMinutes: lunch?.lowerBound ?? 0, lunchMinutes: lunch?.count ?? 0,
            bufferMinutes: bufferMinutes, busyIntervals: busy, untimedPlannedMinutes: untimedPlannedMinutes,
            estimatedCount: 0, travelIntervals: travel, blockIntervals: blocks))
        self.availableMinutes = dayCapacity.availableMinutes
        // The load for the AI checks keeps counting tasks without a time block, although the capacity does not.
        self.plannedMinutes = dayCapacity.plannedMinutes + untimedPlannedMinutes
        self.blockMinutes = dayCapacity.plannedMinutes

        let dayStart = day.startDate(in: calendar)
        let dayEnd = day.adding(days: 1, calendar: calendar).startDate(in: calendar)
        let dayLength = Int(dayEnd.timeIntervalSince(dayStart) / 60)
        var listed = events
            .filter { $0.end > dayStart && $0.start < dayEnd }
            .sorted { $0.start < $1.start }
            .map { event in
                let linked = linkedEventIDs.contains(event.id)
                return PlanInputEvent(
                    title: event.title,
                    start: event.isAllDay ? nil : max(0, Int(event.start.timeIntervalSince(dayStart) / 60)),
                    end: event.isAllDay ? nil : min(dayLength, Int(event.end.timeIntervalSince(dayStart) / 60)),
                    allDay: event.isAllDay,
                    busy: event.isBusy && !event.isAllDay && !linked,
                    deadline: deadlineCalendarIDs.contains(event.calendarID) || deadlineEventIDs.contains(event.id),
                    linkedToTask: linked
                )
            }
        // The trips are listed like events, with a fixed title and no place (privacy: places never leave the device).
        listed += travel.map { range in
            PlanInputEvent(title: "Fahrzeit", start: max(0, range.lowerBound), end: min(dayLength, range.upperBound),
                           allDay: false, busy: true, deadline: false, linkedToTask: false, travel: true)
        }
        self.events = listed.enumerated().sorted { lhs, rhs in
            let left = lhs.element.start ?? -1, right = rhs.element.start ?? -1
            return left != right ? left < right : lhs.offset < rhs.offset
        }.map(\.element)
    }
}

extension PlanInputDay {
    /// The same day with other working hours; capacity is computed again. The time blocks keep counting for the part
    /// inside the new hours; load added since (moved tasks) stays.
    public func withHours(_ hours: WorkHours) -> PlanInputDay {
        func capacity(for hours: WorkHours?) -> DayCapacity {
            TagwerkCore.capacity(CapacityInput(
                hours: hours, lunchStartMinutes: lunch?.lowerBound ?? 0, lunchMinutes: lunch?.count ?? 0,
                bufferMinutes: bufferMinutes, busyIntervals: eventBusy, untimedPlannedMinutes: 0, estimatedCount: 0,
                travelIntervals: travel, blockIntervals: blocks))
        }
        var day = self
        day.hours = hours
        let updated = capacity(for: hours)
        day.availableMinutes = updated.availableMinutes
        day.plannedMinutes = plannedMinutes - capacity(for: self.hours).plannedMinutes + updated.plannedMinutes
        day.blockMinutes = updated.plannedMinutes
        return day
    }
}

/// An open task offered to the model.
public struct PlanInputTask: Sendable, Hashable {
    /// `TaskID.key`.
    public var id: String
    public var source: TaskSource
    public var title: String
    public var due: DueDate?
    public var priority: Priority?
    /// Effort; `nil` lets the model estimate it.
    public var minutes: Int?
    public var important: Bool
    /// Work day already assigned in Tagwerk.
    public var plannedDay: PlanDay?
    /// The important deadline the task belongs to (epic due date or a linked deadline event).
    public var anchor: DueDate?
    /// Effort still open (estimate minus existing blocks); `nil` without estimate.
    public var remainingMinutes: Int?
    /// Suggested share for one day when a large effort is spread over the days before its deadline.
    public var sessionMinutes: Int?
    /// The day work has to start at the latest so the effort fits before the deadline.
    public var latestStart: PlanDay?
    /// Expected effort from the person's earlier measurements (plan P3, #162); `nil` without enough measurements.
    /// Only this number leaves the device, never the measurements themselves.
    public var expectedMinutes: Int?

    public init(id: String, source: TaskSource, title: String, due: DueDate?, priority: Priority?, minutes: Int?,
                important: Bool, plannedDay: PlanDay?, anchor: DueDate?) {
        self.id = id
        self.source = source
        self.title = title
        self.due = due
        self.priority = priority
        self.minutes = minutes
        self.important = important
        self.plannedDay = plannedDay
        self.anchor = anchor
    }
}

public struct PlanInput: Sendable, Hashable {
    public var scope: PlanScope
    public var days: [PlanInputDay]
    public var tasks: [PlanInputTask]
    public var today: PlanDay
    public var nowMinutes: Int
    public var timeZoneID: String
    /// Load of a task without effort (design §6.1).
    public var defaultTaskMinutes: Int
    /// Day plan only: the next days, as targets for moving tasks away from a full day.
    public var laterDays: [PlanInputDay] = []
    /// Core tasks left out because of the maximum count; the summary should mention them.
    public var omittedCount = 0
    /// The first day work can still happen on: today, or the day after once today's working time is over
    /// (plan-tomorrow, decision 6). Limits before it are no longer enforced, like those of overdue tasks.
    public var earliestWorkDay: PlanDay

    public init(scope: PlanScope, days: [PlanInputDay], tasks: [PlanInputTask], today: PlanDay, nowMinutes: Int,
                timeZoneID: String, defaultTaskMinutes: Int) {
        self.scope = scope
        self.days = days
        self.tasks = tasks
        self.today = today
        self.nowMinutes = nowMinutes
        self.timeZoneID = timeZoneID
        self.defaultTaskMinutes = defaultTaskMinutes
        self.earliestWorkDay = today
    }
}


/// Selection rules for planning calls (proposal 2026-11-18, §1). Starting values, tuned on the device.
public enum PlanSelectionRules {
    /// Due-date window from today: day 3 days, week 14, month 45.
    public static func windowDays(_ scope: PlanScope) -> Int {
        switch scope { case .day: 3; case .week: 14; case .month: 45 }
    }

    /// The fill-up stops once the selected effort reaches this multiple of the free time.
    public static func budgetFactor(_ scope: PlanScope) -> Double {
        switch scope { case .day: 2.0; case .week: 1.5; case .month: 1.25 }
    }

    public static func bounds(_ scope: PlanScope) -> (minimum: Int, maximum: Int) {
        switch scope { case .day: (8, 25); case .week: (15, 40); case .month: (20, 60) }
    }

    public static let maximumP1 = 10
    /// At most this much work on one task per day when a large effort is spread (user rule 2026-11-18).
    public static let maximumDailyMinutesPerTask = 4 * 60
    /// Week/month: assigned tasks of overbooked days that may be moved.
    public static let maximumMovable = 10
    public static let maximumUndatedFill = 5
}

/// Selects and orders the tasks for a planning call (proposal 2026-11-18, §1 with the user's change):
/// - **Core** (always, limited only by the maximum): planned on the day, overdue (any age; counts as due
///   today), due or anchored within the window, every P1 (at most 10).
/// - **Fill-up** while the summed effort stays below the budget (factor × free time) or below the minimum
///   count: day tasks of the next days (work ahead), due within twice the window, P2 without date, other
///   undated tasks (at most 5).
/// - `only`: exactly these tasks ("Mit KI planen", re-checks), without rules and limits.
/// - `excluding`: recurring reminders (their effort is reserved elsewhere).
/// Order: core before fill-up; overdue/today first, then P1, then target date, priority, due, source, title.
public func makePlanInput(scope: PlanScope, days: [PlanInputDay], tasks: [TaskItem], assignments: [TaskID: PlanDay],
                          anchors: [TaskID: DueDate], today: PlanDay, nowMinutes: Int, timeZoneID: String,
                          defaultTaskMinutes: Int, only: Set<TaskID>? = nil, excluding: Set<TaskID> = [],
                          lookaheadDays: Set<PlanDay> = [], blockedMinutes: [TaskID: Int] = [:],
                          earliestWorkDay: PlanDay? = nil, expectedMinutes: [String: Int] = [:],
                          calendar: Calendar = .current) -> PlanInput {
    // A day plan counts window, daily share and order from the planned day (plan-tomorrow, F5); "overdue"
    // stays measured against the real today. `earliest` moves past today only once today's work time is over.
    let reference = scope == .day ? max(today, days.first?.day ?? today) : today
    let earliest = max(today, earliestWorkDay ?? today)
    func anchor(of task: TaskItem) -> DueDate? {
        anchors[task.id] ?? (task.epic?.isEpic == true ? task.epic?.due : nil)
    }
    func isImportant(_ task: TaskItem) -> Bool {
        task.priority == .p1 || (task.isEpic && task.due != nil) || anchor(of: task) != nil
    }
    func remaining(_ task: TaskItem) -> Int? {
        task.estimateMinutes.map { max(0, $0 - (blockedMinutes[task.id] ?? 0)) }
    }
    func minutes(_ task: TaskItem) -> Int { remaining(task) ?? defaultTaskMinutes }
    func deadline(_ task: TaskItem) -> PlanDay? {
        [task.due.map(PlanDay.init), anchor(of: task).map(PlanDay.init)].compactMap { $0 }.min()
    }
    /// Large efforts are spread over the days before the deadline: at most 4 h a day, so 20 h due on the
    /// 28th must start on the 24th at the latest, whatever the priority.
    func latestStart(_ task: TaskItem) -> PlanDay? {
        guard let deadline = deadline(task), let open = remaining(task), open > 0 else { return nil }
        let daysNeeded = Int((Double(open) / Double(PlanSelectionRules.maximumDailyMinutesPerTask)).rounded(.up))
        return deadline.adding(days: -(daysNeeded - 1), calendar: calendar)
    }
    /// The earliest of due date, anchor and latest start; overdue counts as the reference day.
    func target(_ task: TaskItem) -> PlanDay? {
        let dates = [deadline(task), latestStart(task)].compactMap { $0 }
        return dates.min().map { max($0, reference) }
    }
    /// Share for the reference day: the open effort divided by the days left until the deadline.
    func session(_ task: TaskItem) -> Int? {
        guard let open = remaining(task), open > PlanSelectionRules.maximumDailyMinutesPerTask / 2,
              let deadline = deadline(task), deadline > reference else { return nil }
        let daysLeft = max(1, calendar.dateComponents([.day], from: reference.startDate(in: calendar),
                                                      to: deadline.startDate(in: calendar)).day ?? 1)
        let share = Int((Double(open) / Double(daysLeft)).rounded(.up))
        return min(PlanSelectionRules.maximumDailyMinutesPerTask, max(30, (share + 14) / 15 * 15))
    }
    func makeTask(_ task: TaskItem) -> PlanInputTask {
        var item = PlanInputTask(id: task.id.key, source: task.id.source, title: task.title, due: task.due, priority: task.priority,
                                 minutes: task.estimateMinutes, important: isImportant(task), plannedDay: assignments[task.id],
                                 anchor: anchor(of: task))
        item.remainingMinutes = remaining(task)
        item.sessionMinutes = session(task)
        item.latestStart = latestStart(task)
        item.expectedMinutes = expectedMinutes[task.id.key]
        return item
    }

    let open = tasks.filter { !$0.isCompleted && !excluding.contains($0.id) }
    if let only {
        let picked = open.filter { only.contains($0.id) }
        var input = PlanInput(scope: scope, days: days, tasks: picked.map(makeTask), today: today, nowMinutes: nowMinutes,
                              timeZoneID: timeZoneID, defaultTaskMinutes: defaultTaskMinutes)
        input.earliestWorkDay = earliest
        return input
    }

    let windowEnd = reference.adding(days: PlanSelectionRules.windowDays(scope), calendar: calendar)
    let doubleEnd = reference.adding(days: 2 * PlanSelectionRules.windowDays(scope), calendar: calendar)
    let overbooked = Set(days.filter { $0.plannedMinutes > $0.availableMinutes }.map(\.day))

    var core: [TaskItem] = []
    var p1Count = 0
    var movable: [TaskItem] = []
    var fill: [[TaskItem]] = [[], [], [], []]
    for task in open {
        let assigned = assignments[task.id]
        let isOverdue = task.due.map { PlanDay($0) < today } ?? false
        let targetDay = target(task)
        if scope == .day {
            let day = days.first?.day ?? today
            // Planned for another day that can still be worked on: only as fill-up for working ahead.
            if let assigned, assigned != day, assigned >= earliest {
                if lookaheadDays.contains(assigned) { fill[0].append(task) }
                continue
            }
            // Planned for a day whose work time is over (today after work end): left over, like overdue work.
            let isLeftOver = assigned.map { $0 >= today && $0 < earliest } ?? false
            // A limit before the planned day that can still be met on an earlier day: the task belongs there.
            if assigned != day, let limit = deadline(task), limit >= earliest, limit < day { continue }
            if assigned == day || days.first?.countedTaskMinutes[task.id.key] != nil || isOverdue || isLeftOver
                || targetDay.map({ $0 <= windowEnd }) == true {
                core.append(task); continue
            }
        } else {
            if let assigned, assigned >= today {
                if overbooked.contains(assigned) { movable.append(task) }
                continue
            }
            if isOverdue || targetDay.map({ $0 <= windowEnd }) == true { core.append(task); continue }
        }
        if task.priority == .p1 && p1Count < PlanSelectionRules.maximumP1 {
            p1Count += 1
            core.append(task); continue
        }
        if let targetDay, targetDay <= doubleEnd { fill[1].append(task); continue }
        if targetDay == nil && task.priority == .p2 { fill[2].append(task); continue }
        if targetDay == nil { fill[3].append(task) }
    }

    let sourceOrder: [TaskSource: Int] = [.github: 0, .reminders: 1, .local: 2]
    func ordered(_ list: [TaskItem]) -> [TaskItem] {
        list.sorted { lhs, rhs in
            func bucket(_ task: TaskItem) -> Int {
                if task.due.map({ PlanDay($0) < today }) == true { return 0 }
                guard let day = target(task) else { return task.priority == .p1 ? 2 : 3 }
                return day <= reference ? 1 : (task.priority == .p1 ? 2 : 3)
            }
            if bucket(lhs) != bucket(rhs) { return bucket(lhs) < bucket(rhs) }
            if bucket(lhs) == 0 {
                // Overdue: priority first, then the oldest.
                let lhsPriority = lhs.priority?.rawValue ?? 9, rhsPriority = rhs.priority?.rawValue ?? 9
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            }
            let lhsTarget = target(lhs) ?? PlanDay(year: 9999, month: 12, day: 31)
            let rhsTarget = target(rhs) ?? PlanDay(year: 9999, month: 12, day: 31)
            if lhsTarget != rhsTarget { return lhsTarget < rhsTarget }
            let lhsPriority = lhs.priority?.rawValue ?? 9, rhsPriority = rhs.priority?.rawValue ?? 9
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            let lhsDue = lhs.due.map(PlanDay.init) ?? PlanDay(year: 9999, month: 12, day: 31)
            let rhsDue = rhs.due.map(PlanDay.init) ?? PlanDay(year: 9999, month: 12, day: 31)
            if lhsDue != rhsDue { return lhsDue < rhsDue }
            let lhsSource = sourceOrder[lhs.id.source] ?? 9, rhsSource = sourceOrder[rhs.id.source] ?? 9
            if lhsSource != rhsSource { return lhsSource < rhsSource }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    let (minimum, maximum) = PlanSelectionRules.bounds(scope)
    let budget = Int(PlanSelectionRules.budgetFactor(scope) * Double(periodFreeMinutes(days: days, scope: scope, nowMinutes: nowMinutes, today: today)))
    var selected = ordered(core) + ordered(Array(movable.prefix(PlanSelectionRules.maximumMovable)))
    let omitted = max(0, selected.count - maximum)
    selected = Array(selected.prefix(maximum))
    var effort = selected.reduce(0) { $0 + minutes($1) }
    fill[3] = Array(ordered(fill[3]).prefix(PlanSelectionRules.maximumUndatedFill))
    for tier in fill {
        for task in ordered(tier) {
            guard selected.count < maximum, effort < budget || selected.count < minimum else { break }
            selected.append(task)
            effort += minutes(task)
        }
    }

    var input = PlanInput(scope: scope, days: days, tasks: selected.map(makeTask), today: today, nowMinutes: nowMinutes,
                          timeZoneID: timeZoneID, defaultTaskMinutes: defaultTaskMinutes)
    input.omittedCount = omitted
    input.earliestWorkDay = earliest
    return input
}

/// Free time of the period for the selection budget: the day's free stretches from now, or the free minutes of the
/// working days of a week or month.
func periodFreeMinutes(days: [PlanInputDay], scope: PlanScope, nowMinutes: Int, today: PlanDay) -> Int {
    switch scope {
    case .day:
        guard let day = days.first else { return 0 }
        return freeGaps(day, fromMinutes: day.day == today ? nowMinutes : nil).reduce(0) { $0 + $1.count }
    case .week, .month:
        return days.filter { $0.day >= today && $0.hours != nil }.reduce(0) { $0 + max(0, $1.availableMinutes - $1.plannedMinutes) }
    }
}

// MARK: - Output

public struct PlanBlock: Sendable, Hashable, Codable {
    public var taskId: String
    /// "HH:mm" on the planned day.
    public var start: String
    public var minutes: Int
    public var reason: String

    public init(taskId: String, start: String, minutes: Int, reason: String) {
        self.taskId = taskId
        self.start = start
        self.minutes = minutes
        self.reason = reason
    }
}

public struct PlanAssignment: Sendable, Hashable, Codable {
    public var taskId: String
    /// "YYYY-MM-DD".
    public var day: String
    public var reason: String

    public init(taskId: String, day: String, reason: String) {
        self.taskId = taskId
        self.day = day
        self.reason = reason
    }
}

public struct PlanUnscheduled: Sendable, Hashable, Codable {
    public var taskId: String
    public var reason: String

    public init(taskId: String, reason: String) {
        self.taskId = taskId
        self.reason = reason
    }
}

public struct PlanEstimate: Sendable, Hashable, Codable {
    public var taskId: String
    public var minutes: Int

    public init(taskId: String, minutes: Int) {
        self.taskId = taskId
        self.minutes = minutes
    }
}

/// Moves a task that is planned for one day to a later day ("↷ … verschieben").
public struct PlanMove: Sendable, Hashable, Codable {
    public var taskId: String
    /// "YYYY-MM-DD".
    public var day: String
    public var reason: String

    public init(taskId: String, day: String, reason: String) {
        self.taskId = taskId
        self.day = day
        self.reason = reason
    }
}

/// Longer working hours for one day, or work on a day off (issue #72).
public struct PlanDayChange: Sendable, Hashable, Codable {
    /// "YYYY-MM-DD".
    public var day: String
    /// "HH:mm".
    public var start: String
    public var end: String
    public var reason: String

    public init(day: String, start: String, end: String, reason: String) {
        self.day = day
        self.start = start
        self.end = end
        self.reason = reason
    }
}

/// Bounds for longer days (user rule 2026-11-18): 07:00–21:00, normally at most 10 h, in an emergency 12 h.
public enum WorkdayLimits {
    public static let earliest = 7 * 60
    public static let latest = 21 * 60
    public static let normalMaximum = 10 * 60
    public static let emergencyMaximum = 12 * 60
}

public struct DayPlanOutput: Sendable, Hashable, Codable {
    public var blocks: [PlanBlock]
    public var unscheduled: [PlanUnscheduled]
    public var risks: [String]
    public var estimates: [PlanEstimate]
    /// One or two sentences on the period as a whole.
    public var summary: String
    public var moves: [PlanMove]
    public var dayChanges: [PlanDayChange]

    public init(blocks: [PlanBlock], unscheduled: [PlanUnscheduled], risks: [String], estimates: [PlanEstimate],
                summary: String = "", moves: [PlanMove] = [], dayChanges: [PlanDayChange] = []) {
        self.blocks = blocks
        self.unscheduled = unscheduled
        self.risks = risks
        self.estimates = estimates
        self.summary = summary
        self.moves = moves
        self.dayChanges = dayChanges
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blocks = try container.decode([PlanBlock].self, forKey: .blocks)
        unscheduled = try container.decodeIfPresent([PlanUnscheduled].self, forKey: .unscheduled) ?? []
        risks = try container.decodeIfPresent([String].self, forKey: .risks) ?? []
        estimates = try container.decodeIfPresent([PlanEstimate].self, forKey: .estimates) ?? []
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        moves = try container.decodeIfPresent([PlanMove].self, forKey: .moves) ?? []
        dayChanges = try container.decodeIfPresent([PlanDayChange].self, forKey: .dayChanges) ?? []
    }
}

public struct PeriodPlanOutput: Sendable, Hashable, Codable {
    public var assignments: [PlanAssignment]
    public var unscheduled: [PlanUnscheduled]
    public var risks: [String]
    public var estimates: [PlanEstimate]
    public var summary: String
    public var moves: [PlanMove]
    public var dayChanges: [PlanDayChange]

    public init(assignments: [PlanAssignment], unscheduled: [PlanUnscheduled], risks: [String], estimates: [PlanEstimate],
                summary: String = "", moves: [PlanMove] = [], dayChanges: [PlanDayChange] = []) {
        self.assignments = assignments
        self.unscheduled = unscheduled
        self.risks = risks
        self.estimates = estimates
        self.summary = summary
        self.moves = moves
        self.dayChanges = dayChanges
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assignments = try container.decode([PlanAssignment].self, forKey: .assignments)
        unscheduled = try container.decodeIfPresent([PlanUnscheduled].self, forKey: .unscheduled) ?? []
        risks = try container.decodeIfPresent([String].self, forKey: .risks) ?? []
        estimates = try container.decodeIfPresent([PlanEstimate].self, forKey: .estimates) ?? []
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        moves = try container.decodeIfPresent([PlanMove].self, forKey: .moves) ?? []
        dayChanges = try container.decodeIfPresent([PlanDayChange].self, forKey: .dayChanges) ?? []
    }
}

public enum PlanOutput: Sendable, Hashable {
    case day(DayPlanOutput)
    case period(PeriodPlanOutput)

    /// Decodes the model's JSON answer for `scope`.
    public static func decode(_ data: Data, scope: PlanScope) throws -> PlanOutput {
        switch scope {
        case .day: .day(try JSONDecoder().decode(DayPlanOutput.self, from: data))
        case .week, .month: .period(try JSONDecoder().decode(PeriodPlanOutput.self, from: data))
        }
    }
}

/// A suggestion that failed a local check.
public struct PlanViolation: Sendable, Hashable {
    public enum Reason: Sendable, Hashable {
        case unknownTask, duplicate, invalidMinutes, invalidTime, invalidDay, outsidePeriod, inThePast, dayOff
        case outsideWorkHours, overlapsLunch, overlapsEvent, overlapsBlock, afterDue, afterDeadline
        case alreadyAssigned, overCapacity, wrongScope, invalidDayChange, notAnExtension, notPlannedThatDay, noEffect

        /// The rule that was broken, in the app language (shown on the screen and sent back to the model).
        public var text: String {
            switch self {
            case .unknownTask: String(localized: "Diese Aufgabe gibt es nicht.", bundle: .module)
            case .duplicate: String(localized: "Die Aufgabe wurde doppelt vorgeschlagen.", bundle: .module)
            case .invalidMinutes: String(localized: "Die Dauer ist ungültig.", bundle: .module)
            case .invalidTime: String(localized: "Die Uhrzeit ist ungültig.", bundle: .module)
            case .invalidDay: String(localized: "Das Datum ist ungültig.", bundle: .module)
            case .outsidePeriod: String(localized: "Der Tag liegt außerhalb des Zeitraums.", bundle: .module)
            case .inThePast: String(localized: "Der Vorschlag liegt in der Vergangenheit.", bundle: .module)
            case .dayOff: String(localized: "Der Tag ist frei.", bundle: .module)
            case .outsideWorkHours: String(localized: "Der Block liegt außerhalb der Arbeitszeit.", bundle: .module)
            case .overlapsLunch: String(localized: "Der Block liegt in der Mittagspause.", bundle: .module)
            case .overlapsEvent: String(localized: "Der Block überschneidet sich mit einem Termin oder dessen Puffer.", bundle: .module)
            case .overlapsBlock: String(localized: "Der Block überschneidet sich mit einem anderen Block.", bundle: .module)
            case .afterDue: String(localized: "Der Vorschlag liegt nach der Fälligkeit.", bundle: .module)
            case .afterDeadline: String(localized: "Der Vorschlag liegt nach der zugehörigen Deadline.", bundle: .module)
            case .alreadyAssigned: String(localized: "Die Aufgabe ist schon einem Tag zugeordnet.", bundle: .module)
            case .overCapacity: String(localized: "Die Kapazität des Tages ist überschritten.", bundle: .module)
            case .wrongScope: String(localized: "Die Antwort passt nicht zum Zeitraum.", bundle: .module)
            case .invalidDayChange: String(localized: "Die längere Arbeitszeit liegt außerhalb von 7 bis 21 Uhr oder über 12 Stunden.", bundle: .module)
            case .notAnExtension: String(localized: "Das verlängert die Arbeitszeit nicht.", bundle: .module)
            case .notPlannedThatDay: String(localized: "Die Aufgabe ist an diesem Tag nicht eingeplant.", bundle: .module)
            case .noEffect: String(localized: "Die längere Arbeitszeit wird nicht gebraucht.", bundle: .module)
            }
        }
    }

    public var taskId: String
    public var reason: Reason

    public init(taskId: String, reason: Reason) {
        self.taskId = taskId
        self.reason = reason
    }
}

// MARK: - Validation

/// Checks the model's suggestions against the input. Invalid ones are dropped and reported;
/// estimates and unscheduled entries are kept only for known tasks.
public func validate(_ output: PlanOutput, input: PlanInput) -> (accepted: PlanOutput, violations: [PlanViolation]) {
    let tasks = Dictionary(input.tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    switch (output, input.scope) {
    case (.day(let plan), .day):
        let estimates = knownEstimates(plan.estimates, tasks)
        let stage = validateChanges(dayChanges: plan.dayChanges, moves: plan.moves, input: input, tasks: tasks,
                                    estimates: estimateMap(estimates))
        let effectiveTasks = Dictionary(stage.input.tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let movedIDs = Set(stage.moves.map(\.taskId))
        var violations = stage.violations
        var blocks = plan.blocks
        for block in blocks where movedIDs.contains(block.taskId) {
            violations.append(PlanViolation(taskId: block.taskId, reason: .duplicate))
        }
        blocks.removeAll { movedIDs.contains($0.taskId) }
        let (acceptedBlocks, blockViolations, overbookedAfter) = validateBlocks(blocks, input: stage.input, tasks: effectiveTasks)
        // A longer day needs an effect: a block in the added time or an overbooked day (proposal §3).
        var dayChanges = stage.dayChanges
        if let original = input.days.first {
            let overbooked = original.plannedMinutes > original.availableMinutes
            let blockOutside = acceptedBlocks.contains { block in
                guard let start = minutes(fromTime: block.start), let hours = original.hours else { return true }
                return start < hours.startMinutes || start + block.minutes > hours.endMinutes
            }
            if !overbooked && !blockOutside {
                violations += dayChanges.map { PlanViolation(taskId: "day:\($0.day)", reason: .noEffect) }
                dayChanges = []
            }
        }
        var risks = plan.risks
        if overbookedAfter > 0 { risks.append(String(localized: "Danach noch \(durationText(overbookedAfter)) zu viel.", bundle: .module)) }
        return (.day(DayPlanOutput(blocks: acceptedBlocks, unscheduled: knownUnscheduled(plan.unscheduled, tasks),
                                   risks: risks, estimates: estimates, summary: plan.summary,
                                   moves: stage.moves, dayChanges: dayChanges)), violations + blockViolations)
    case (.period(let plan), .week), (.period(let plan), .month):
        let estimates = knownEstimates(plan.estimates, tasks)
        let stage = validateChanges(dayChanges: plan.dayChanges, moves: plan.moves, input: input, tasks: tasks,
                                    estimates: estimateMap(estimates))
        let effectiveTasks = Dictionary(stage.input.tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let (assignments, violations) = validateAssignments(plan.assignments, input: stage.input, tasks: effectiveTasks,
                                                            estimates: estimateMap(estimates))
        return (.period(PeriodPlanOutput(assignments: assignments, unscheduled: knownUnscheduled(plan.unscheduled, tasks),
                                         risks: plan.risks, estimates: estimates, summary: plan.summary,
                                         moves: stage.moves, dayChanges: stage.dayChanges)), stage.violations + violations)
    case (.day(let plan), _):
        return (.period(PeriodPlanOutput(assignments: [], unscheduled: [], risks: [], estimates: [])),
                plan.blocks.map { PlanViolation(taskId: $0.taskId, reason: .wrongScope) })
    case (.period(let plan), _):
        return (.day(DayPlanOutput(blocks: [], unscheduled: [], risks: [], estimates: [])),
                plan.assignments.map { PlanViolation(taskId: $0.taskId, reason: .wrongScope) })
    }
}

private func estimateMap(_ estimates: [PlanEstimate]) -> [String: Int] {
    Dictionary(estimates.map { ($0.taskId, $0.minutes) }, uniquingKeysWith: { first, _ in first })
}

/// First stage: longer days and moves. Valid ones change the input that blocks and assignments are then
/// checked against (longer hours and more capacity; the origin day loses the moved task's load).
private func validateChanges(dayChanges: [PlanDayChange], moves: [PlanMove], input: PlanInput, tasks: [String: PlanInputTask],
                             estimates: [String: Int])
    -> (input: PlanInput, dayChanges: [PlanDayChange], moves: [PlanMove], violations: [PlanViolation]) {
    var effective = input
    var violations: [PlanViolation] = []
    var acceptedChanges: [PlanDayChange] = []
    var changedDays = Set<PlanDay>()

    for change in dayChanges {
        let key = "day:\(change.day)"
        guard let day = planDay(from: change.day), let index = effective.days.firstIndex(where: { $0.day == day }) else {
            violations.append(PlanViolation(taskId: key, reason: .outsidePeriod)); continue
        }
        guard day >= input.today, !changedDays.contains(day) else {
            violations.append(PlanViolation(taskId: key, reason: day < input.today ? .inThePast : .duplicate)); continue
        }
        guard let start = minutes(fromTime: change.start), let end = minutes(fromTime: change.end), start < end,
              start >= WorkdayLimits.earliest, end <= WorkdayLimits.latest,
              end - start <= WorkdayLimits.emergencyMaximum else {
            violations.append(PlanViolation(taskId: key, reason: .invalidDayChange)); continue
        }
        let current = effective.days[index].hours
        if let current, current.minutes > 0 {
            guard start <= current.startMinutes, end >= current.endMinutes,
                  start < current.startMinutes || end > current.endMinutes else {
                violations.append(PlanViolation(taskId: key, reason: .notAnExtension)); continue
            }
        }
        effective.days[index] = effective.days[index].withHours(WorkHours(startMinutes: start, endMinutes: end))
        changedDays.insert(day)
        acceptedChanges.append(change)
    }

    let targets = Dictionary((effective.days + effective.laterDays).map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
    var extraLoad: [PlanDay: Int] = [:]
    var acceptedMoves: [PlanMove] = []
    var moved = Set<String>()
    for move in moves {
        func reject(_ reason: PlanViolation.Reason) { violations.append(PlanViolation(taskId: move.taskId, reason: reason)) }
        guard !moved.contains(move.taskId) else { reject(.duplicate); continue }
        guard let task = tasks[move.taskId] else { reject(.unknownTask); continue }
        // The task must currently weigh on one of the planned days.
        guard let originIndex = effective.days.firstIndex(where: { day in
            task.plannedDay == day.day || day.countedTaskMinutes[task.id] != nil
        }) else { reject(.notPlannedThatDay); continue }
        guard let target = planDay(from: move.day) else { reject(.invalidDay); continue }
        guard let targetDay = targets[target] else { reject(.outsidePeriod); continue }
        guard target > input.today, target != effective.days[originIndex].day else { reject(.inThePast); continue }
        guard let hours = targetDay.hours, hours.minutes > 0 else { reject(.dayOff); continue }
        let taskMinutes = task.minutes ?? estimates[task.id] ?? effective.days[originIndex].countedTaskMinutes[task.id]
            ?? input.defaultTaskMinutes
        let freeOnTarget = targetDay.availableMinutes - targetDay.plannedMinutes - (extraLoad[target] ?? 0)
        guard taskMinutes <= freeOnTarget else { reject(.overCapacity); continue }
        // The origin day is relieved; the target day carries the task from now on.
        let counted = effective.days[originIndex].countedTaskMinutes.removeValue(forKey: task.id) ?? 0
        effective.days[originIndex].plannedMinutes -= counted
        if let index = effective.days.firstIndex(where: { $0.day == target }) {
            effective.days[index].plannedMinutes += taskMinutes
            effective.days[index].countedTaskMinutes[task.id] = taskMinutes
        } else {
            extraLoad[target, default: 0] += taskMinutes
        }
        if let taskIndex = effective.tasks.firstIndex(where: { $0.id == task.id }) { effective.tasks[taskIndex].plannedDay = target }
        moved.insert(move.taskId)
        acceptedMoves.append(move)
    }
    return (effective, acceptedChanges, acceptedMoves, violations)
}

private func validateBlocks(_ blocks: [PlanBlock], input: PlanInput,
                            tasks: [String: PlanInputTask]) -> ([PlanBlock], [PlanViolation], Int) {
    var violations: [PlanViolation] = []
    guard let day = input.days.first else {
        return ([], blocks.map { PlanViolation(taskId: $0.taskId, reason: .outsidePeriod) }, 0)
    }
    // Events keep the buffer distance, travel time does not (as in `capacity(_:)`).
    let busy = bufferedEventIntervals(day.eventBusy, lunch: day.lunch, travel: day.travel, buffer: day.bufferMinutes) + day.travel
    var seen = Set<String>()
    var accepted: [(block: PlanBlock, range: Range<Int>)] = []

    for block in blocks {
        func reject(_ reason: PlanViolation.Reason) { violations.append(PlanViolation(taskId: block.taskId, reason: reason)) }
        guard !seen.contains(block.taskId) else { reject(.duplicate); continue }
        guard let task = tasks[block.taskId] else { reject(.unknownTask); continue }
        seen.insert(block.taskId)
        guard block.minutes > 0 else { reject(.invalidMinutes); continue }
        guard let start = minutes(fromTime: block.start) else { reject(.invalidTime); continue }
        let range = start..<(start + block.minutes)
        if day.day < input.today || (day.day == input.today && start < input.nowMinutes) { reject(.inThePast); continue }
        guard let hours = day.hours, hours.minutes > 0 else { reject(.dayOff); continue }
        guard range.lowerBound >= hours.startMinutes, range.upperBound <= hours.endMinutes else {
            reject(.outsideWorkHours); continue
        }
        if let lunch = day.lunch, lunch.overlaps(range) { reject(.overlapsLunch); continue }
        if busy.contains(where: { $0.overlaps(range) }) { reject(.overlapsEvent); continue }
        let bufferedBlocks = day.blocks.map { ($0.lowerBound - day.bufferMinutes)..<($0.upperBound + day.bufferMinutes) }
        if bufferedBlocks.contains(where: { $0.overlaps(range) }) || accepted.contains(where: { $0.range.overlaps(range) }) {
            reject(.overlapsBlock); continue
        }
        if isLate(day: day.day, endMinutes: range.upperBound, limit: task.due, input: input) { reject(.afterDue); continue }
        if isLate(day: day.day, endMinutes: range.upperBound, limit: task.anchor, input: input) { reject(.afterDeadline); continue }
        accepted.append((block, range))
    }

    // Time is hard (proposal 2026-11-18, §3): the new blocks must fit into the free stretches of the day.
    accepted.sort { $0.range.lowerBound < $1.range.lowerBound }
    let freeTime = freeGaps(day, fromMinutes: day.day == input.today ? input.nowMinutes : nil).reduce(0) { $0 + $1.count }
    while let last = accepted.last, accepted.reduce(0, { $0 + $1.block.minutes }) > freeTime {
        accepted.removeLast()
        violations.append(PlanViolation(taskId: last.block.taskId, reason: .overCapacity))
    }

    // Load is soft: a block that fits in time is kept for tasks already counted on the day, P1, important
    // or due by the day after tomorrow. Other new tasks must not raise the overbooking.
    let soon = input.today.adding(days: 2, calendar: Calendar(identifier: .gregorian))
    func privileged(_ taskId: String) -> Bool {
        guard let task = tasks[taskId] else { return false }
        return day.countedTaskMinutes[taskId] != nil || task.priority == .p1 || task.important
            || task.due.map { PlanDay($0) <= soon } == true
    }
    // A block replaces the load its task already had on this day, so it is not counted twice.
    func loadAfter() -> Int {
        let replaced = accepted.reduce(0) { $0 + (day.countedTaskMinutes[$1.block.taskId] ?? 0) }
        return day.plannedMinutes - replaced + accepted.reduce(0) { $0 + $1.block.minutes }
    }
    while loadAfter() > day.availableMinutes, let index = accepted.lastIndex(where: { !privileged($0.block.taskId) }) {
        violations.append(PlanViolation(taskId: accepted[index].block.taskId, reason: .overCapacity))
        accepted.remove(at: index)
    }
    let kept = Set(accepted.map(\.block.taskId))
    // Keep the model's order for the accepted blocks.
    var emitted = Set<String>()
    let ordered = blocks.filter { kept.contains($0.taskId) && emitted.insert($0.taskId).inserted }
    return (ordered, violations, max(0, loadAfter() - day.availableMinutes))
}

/// "1 h 20", "50 min".
func durationText(_ minutes: Int) -> String {
    let hours = minutes / 60, rest = minutes % 60
    if hours == 0 { return String(localized: "\(rest) min", bundle: .module) }
    return rest == 0 ? String(localized: "\(hours) h", bundle: .module)
        : String(localized: "\(hours) h \(String(format: "%02d", rest))", bundle: .module)
}

/// `estimates` are the model's own estimates; they count for tasks without effort, because they are
/// stored when the suggestion is accepted.
private func validateAssignments(_ assignments: [PlanAssignment], input: PlanInput, tasks: [String: PlanInputTask],
                                 estimates: [String: Int]) -> ([PlanAssignment], [PlanViolation]) {
    let days = Dictionary(input.days.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
    var violations: [PlanViolation] = []
    var seen = Set<String>()
    var load = days.mapValues(\.plannedMinutes)
    var accepted: [PlanAssignment] = []

    for assignment in assignments {
        func reject(_ reason: PlanViolation.Reason) {
            violations.append(PlanViolation(taskId: assignment.taskId, reason: reason))
        }
        guard !seen.contains(assignment.taskId) else { reject(.duplicate); continue }
        guard let task = tasks[assignment.taskId] else { reject(.unknownTask); continue }
        seen.insert(assignment.taskId)
        guard let planDay = planDay(from: assignment.day) else { reject(.invalidDay); continue }
        guard let day = days[planDay] else { reject(.outsidePeriod); continue }
        if planDay < input.today { reject(.inThePast); continue }
        guard let hours = day.hours, hours.minutes > 0 else { reject(.dayOff); continue }
        if task.plannedDay != nil { reject(.alreadyAssigned); continue }
        if isLate(day: planDay, endMinutes: nil, limit: task.due, input: input) { reject(.afterDue); continue }
        if isLate(day: planDay, endMinutes: nil, limit: task.anchor, input: input) { reject(.afterDeadline); continue }
        let minutes = task.minutes ?? estimates[task.id] ?? input.defaultTaskMinutes
        // A task already counted on that day (due today) adds only the difference.
        let added = minutes - (day.countedTaskMinutes[task.id] ?? 0)
        if (load[planDay] ?? 0) + added > day.availableMinutes { reject(.overCapacity); continue }
        load[planDay, default: 0] += added
        accepted.append(assignment)
    }
    return (accepted, violations)
}

/// True when planning on `day` (ending at `endMinutes`, if known) is later than `limit`.
/// A limit that already lies before now, or before the earliest work day (today after work end), cannot be met
/// any more and is not enforced: such work may still be planned at the earliest possible time.
private func isLate(day: PlanDay, endMinutes: Int?, limit: DueDate?, input: PlanInput) -> Bool {
    guard let limit else { return false }
    let limitDay = PlanDay(limit)
    let limitMinutes = limit.hour.map { $0 * 60 + (limit.minute ?? 0) }
    if limitDay < max(input.today, input.earliestWorkDay) { return false }
    if limitDay == input.today, let limitMinutes, limitMinutes <= input.nowMinutes { return false }
    if day > limitDay { return true }
    if day == limitDay, let limitMinutes, let endMinutes { return endMinutes > limitMinutes }
    return false
}

private func knownUnscheduled(_ entries: [PlanUnscheduled], _ tasks: [String: PlanInputTask]) -> [PlanUnscheduled] {
    entries.filter { tasks[$0.taskId] != nil }
}

private func knownEstimates(_ estimates: [PlanEstimate], _ tasks: [String: PlanInputTask]) -> [PlanEstimate] {
    var seen = Set<String>()
    return estimates.filter { tasks[$0.taskId] != nil && $0.minutes > 0 && seen.insert($0.taskId).inserted }
}

// MARK: - Formats

private func minutes(fromTime text: String) -> Int? {
    let parts = text.split(separator: ":")
    guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
          (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
    return hour * 60 + minute
}

private func timeString(_ minutes: Int) -> String {
    String(format: "%02d:%02d", minutes / 60, minutes % 60)
}

private func planDay(from text: String) -> PlanDay? {
    let parts = text.split(separator: "-")
    guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
          (1...12).contains(month), (1...31).contains(day) else { return nil }
    return PlanDay(year: year, month: month, day: day)
}

private func dayString(_ day: PlanDay) -> String {
    String(format: "%04d-%02d-%02d", day.year, day.month, day.day)
}

private func dueString(_ due: DueDate) -> String {
    let day = dayString(PlanDay(due))
    guard let hour = due.hour else { return day }
    return day + "T" + timeString(hour * 60 + (due.minute ?? 0))
}

// MARK: - Model JSON

extension PlanInput {
    /// The input as compact JSON for the model (proposal 2026-11-18, §2): only what the model needs; free
    /// stretches are computed here so the model does not have to.
    public func modelJSON() throws -> Data {
        struct Span: Encodable { let start: String; let end: String }
        struct Event: Encodable { let title: String; let start: String; let end: String }
        struct Day: Encodable {
            let day: String; let dayOff: Bool; let workStart: String?; let workEnd: String?
            let freeSlots: [Span]?; let freeMinutes: Int; let overbookedBy: Int?
            let busyEvents: [Event]?; let deadlines: [String]?
        }
        struct Task: Encodable {
            let id: String; let source: String; let title: String; let due: String?; let priority: String?
            let minutes: Int?; let remainingMinutes: Int?; let sessionMinutes: Int?; let latestStart: String?
            let expectedMinutes: Int?
            let important: Bool; let plannedDay: String?; let deadline: String?
        }
        struct Limits: Encodable {
            let earliestStart: String; let latestEnd: String; let normalMaximumHours: Int; let emergencyMaximumHours: Int
        }
        struct Body: Encodable {
            let scope: String; let now: String; let timeZone: String; let defaultTaskMinutes: Int
            let days: [Day]; let laterDays: [Day]; let workdayLimits: Limits; let tasks: [Task]; let omittedCount: Int
        }
        let isDayPlan = scope == .day
        func free(_ day: PlanInputDay) -> Int { max(0, day.availableMinutes - day.plannedMinutes) }
        func deadlines(_ day: PlanInputDay) -> [String]? {
            let titles = day.events.filter(\.deadline).map(\.title)
            return titles.isEmpty ? nil : titles
        }
        /// The day being planned: hours, free stretches from now, busy events, overbooking.
        func planningDay(_ day: PlanInputDay) -> Day {
            let gaps = freeGaps(day, fromMinutes: day.day == today ? nowMinutes : nil)
            let busy = day.events.filter { $0.busy }.compactMap { event -> Event? in
                guard let start = event.start, let end = event.end else { return nil }
                return Event(title: event.title, start: timeString(start), end: timeString(end))
            }
            return Day(day: dayString(day.day), dayOff: day.hours == nil,
                       workStart: day.hours.map { timeString($0.startMinutes) }, workEnd: day.hours.map { timeString($0.endMinutes) },
                       freeSlots: gaps.map { Span(start: timeString($0.lowerBound), end: timeString($0.upperBound)) },
                       freeMinutes: gaps.reduce(0) { $0 + $1.count },
                       overbookedBy: day.plannedMinutes > day.availableMinutes ? day.plannedMinutes - day.availableMinutes : nil,
                       busyEvents: busy.isEmpty ? nil : busy, deadlines: deadlines(day))
        }
        /// Days of a week or month, and move targets: free time only.
        func summaryDay(_ day: PlanInputDay, withDeadlines: Bool) -> Day {
            Day(day: dayString(day.day), dayOff: day.hours == nil, workStart: nil, workEnd: nil, freeSlots: nil,
                freeMinutes: day.hours == nil ? 0 : free(day),
                overbookedBy: day.plannedMinutes > day.availableMinutes && day.hours != nil ? day.plannedMinutes - day.availableMinutes : nil,
                busyEvents: nil, deadlines: withDeadlines ? deadlines(day) : nil)
        }
        let body = Body(
            scope: scope.rawValue,
            now: dayString(today) + "T" + timeString(nowMinutes),
            timeZone: timeZoneID,
            defaultTaskMinutes: defaultTaskMinutes,
            days: days.map { isDayPlan ? planningDay($0) : summaryDay($0, withDeadlines: true) },
            laterDays: laterDays.map { summaryDay($0, withDeadlines: false) },
            workdayLimits: Limits(earliestStart: timeString(WorkdayLimits.earliest), latestEnd: timeString(WorkdayLimits.latest),
                                  normalMaximumHours: WorkdayLimits.normalMaximum / 60,
                                  emergencyMaximumHours: WorkdayLimits.emergencyMaximum / 60),
            tasks: tasks.map { task in
                Task(id: task.id, source: task.source.rawValue, title: task.title, due: task.due.map(dueString),
                     priority: task.priority?.label, minutes: task.minutes, remainingMinutes: task.remainingMinutes,
                     sessionMinutes: task.sessionMinutes, latestStart: task.latestStart.map(dayString),
                     // Only when it differs from the estimate; then the model plans with it.
                     expectedMinutes: task.expectedMinutes == task.minutes ? nil : task.expectedMinutes,
                     important: task.important, plannedDay: task.plannedDay.map(dayString), deadline: task.anchor.map(dueString))
            },
            omittedCount: omittedCount
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(body)
    }
}

// MARK: - Schemas

/// Strict JSON schemas for `text.format` (every property required, no extra properties).
public enum AIPlanSchemas {
    private static func object(_ properties: [String: Any]) -> [String: Any] {
        ["type": "object", "additionalProperties": false, "required": properties.keys.sorted(), "properties": properties]
    }

    private static func array(_ items: [String: Any]) -> [String: Any] { ["type": "array", "items": items] }

    private static var string: [String: Any] { ["type": "string"] }
    private static var integer: [String: Any] { ["type": "integer"] }

    private static func common() -> [String: Any] {
        [
            "unscheduled": array(object(["taskId": string, "reason": string])),
            "risks": array(string),
            "estimates": array(object(["taskId": string, "minutes": integer])),
            "summary": ["type": "string", "description": "One or two sentences on the period"],
            "moves": array(object([
                "taskId": string, "day": ["type": "string", "description": "YYYY-MM-DD"], "reason": string,
            ])),
            "dayChanges": array(object([
                "day": ["type": "string", "description": "YYYY-MM-DD"],
                "start": ["type": "string", "description": "HH:mm"],
                "end": ["type": "string", "description": "HH:mm"],
                "reason": string,
            ])),
        ]
    }

    private static func data(_ schema: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])) ?? Data()
    }

    public static var dayPlanSchema: Data {
        var properties = common()
        properties["blocks"] = array(object([
            "taskId": string,
            "start": ["type": "string", "description": "HH:mm"],
            "minutes": integer,
            "reason": string,
        ]))
        return data(object(properties))
    }

    public static var periodPlanSchema: Data {
        var properties = common()
        properties["assignments"] = array(object([
            "taskId": string,
            "day": ["type": "string", "description": "YYYY-MM-DD"],
            "reason": string,
        ]))
        return data(object(properties))
    }
}

// MARK: - Block duration

/// Free stretches of the day in minutes: working hours minus busy events (with buffer), travel time (without
/// buffer), lunch and existing blocks; with `fromMinutes` (today) only from then on. Events, lunch and travel
/// are blocked as in `capacity(_:)`; the gaps keep the buffer distance to existing time blocks as well.
public func freeGaps(_ day: PlanInputDay, fromMinutes: Int?) -> [Range<Int>] {
    guard let hours = day.hours, hours.minutes > 0 else { return [] }
    let start = max(hours.startMinutes, fromMinutes ?? hours.startMinutes)
    guard start < hours.endMinutes else { return [] }
    // The buffer keeps distance to busy events and to existing time blocks alike (setting "Puffer").
    var taken = bufferedEventIntervals(day.eventBusy, lunch: day.lunch, travel: day.travel, buffer: day.bufferMinutes)
    taken += day.blocks.map { ($0.lowerBound - day.bufferMinutes)..<($0.upperBound + day.bufferMinutes) }
    taken += day.travel
    if let lunch = day.lunch { taken.append(lunch) }
    var gaps: [Range<Int>] = []
    var cursor = start
    for range in taken.sorted(by: { $0.lowerBound < $1.lowerBound }) {
        if range.lowerBound > cursor { gaps.append(cursor..<min(range.lowerBound, hours.endMinutes)) }
        cursor = max(cursor, range.upperBound)
        if cursor >= hours.endMinutes { break }
    }
    if cursor < hours.endMinutes { gaps.append(cursor..<hours.endMinutes) }
    return gaps.filter { !$0.isEmpty }
}

/// Longest free stretch of the day in minutes (see `freeGaps`).
public func largestFreeSlot(_ day: PlanInputDay, fromMinutes: Int?) -> Int {
    freeGaps(day, fromMinutes: fromMinutes).map(\.count).max() ?? 0
}

/// Where a copy of a block goes ("Duplizieren"): the first free stretch from `after` on that holds
/// `minutes`; otherwise the largest one from then on, shortened (at least 15 minutes). `nil` if none.
public func nextFreeSlot(_ day: PlanInputDay, after: Int, minutes: Int, fromMinutes: Int?) -> Range<Int>? {
    let gaps = freeGaps(day, fromMinutes: max(after, fromMinutes ?? after))
    if let fitting = gaps.first(where: { $0.count >= minutes }) {
        return fitting.lowerBound..<(fitting.lowerBound + minutes)
    }
    guard let largest = gaps.max(by: { $0.count < $1.count }), largest.count >= 15 else { return nil }
    return largest
}

/// Duration of a new block for a task (user rule 2026-11-18): without estimate the default duration;
/// with estimate the time still open (estimate minus existing blocks). If that is longer than six hours
/// or than the largest free slot of the day, the largest free slot (at most six hours) is used.
public func blockMinutes(estimate: Int?, alreadyBlocked: Int, defaultMinutes: Int, largestFreeSlot: Int) -> Int {
    let maxSession = 6 * 60
    guard let estimate else { return defaultMinutes }
    let remaining = estimate - alreadyBlocked
    guard remaining >= 15 else { return defaultMinutes }
    guard remaining > maxSession || remaining > largestFreeSlot else { return remaining }
    let slot = min(largestFreeSlot, maxSession)
    return slot >= 15 ? slot : min(remaining, maxSession)
}

/// First day whose blocks count as work on the current occurrence of a recurring task (user rule
/// 2026-11-18): daily only today, every n days the last n days, weekly the last six days and today,
/// monthly (also the n-th weekday) since the same day of the previous month, yearly since the same date of the
/// previous year. `nil` for rules Tagwerk cannot read.
public func sessionWindowStart(for rule: RecurrenceRule, today: PlanDay, calendar: Calendar) -> PlanDay? {
    switch rule {
    case .daily(let interval):
        return today.adding(days: -(max(1, interval) - 1), calendar: calendar)
    case .weekly(let interval, _):
        return today.adding(days: -(7 * max(1, interval) - 1), calendar: calendar)
    case .monthly(let interval, _), .monthlyWeekday(let interval, _, _):
        let start = today.startDate(in: calendar)
        let back = calendar.date(byAdding: .month, value: -max(1, interval), to: start) ?? start
        return PlanDay(date: back, calendar: calendar).adding(days: 1, calendar: calendar)
    case .yearly(let interval):
        let start = today.startDate(in: calendar)
        let back = calendar.date(byAdding: .year, value: -max(1, interval), to: start) ?? start
        return PlanDay(date: back, calendar: calendar).adding(days: 1, calendar: calendar)
    case .unsupported:
        return nil
    }
}
