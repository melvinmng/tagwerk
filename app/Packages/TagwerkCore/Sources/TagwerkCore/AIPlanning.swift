import Foundation

// AI planning rules (design §8.2, §11.7, §11.10): what goes to the model and how its answer is
// checked locally before anything is shown. Pure functions, no AI and no I/O.

public enum PlanScope: String, Sendable, Codable {
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
    /// From a deadline calendar.
    public var deadline: Bool
    /// Linked to a task: it counts as that task's planned load.
    public var linkedToTask: Bool
}

/// One day of the planning period with everything the checks need.
public struct PlanInputDay: Sendable, Hashable {
    public var day: PlanDay
    /// `nil` on a day off.
    public var hours: WorkHours?
    /// Lunch of this day in minutes since midnight.
    public var lunch: Range<Int>?
    /// Occupied minutes from busy, unlinked events (without buffer).
    public var busy: [Range<Int>]
    /// Existing time blocks and other task-linked events.
    public var blocks: [Range<Int>]
    public var bufferMinutes: Int
    public var recurringMinutes: Int
    /// Load already on the day: assigned tasks and blocks.
    public var plannedMinutes: Int
    /// Working time left for tasks after events with buffer, lunch and recurring effort.
    public var availableMinutes: Int
    public var events: [PlanInputEvent]

    /// Builds a day from calendar events; occupied time and capacity come from `busyIntervals` and `capacity`.
    public init(day: PlanDay, hours: WorkHours?, lunch: Range<Int>?, events: [CalendarEvent], linkedEventIDs: Set<String>,
                deadlineCalendarIDs: Set<String>, blocks: [Range<Int>], recurringMinutes: Int, plannedMinutes: Int,
                bufferMinutes: Int, calendar: Calendar) {
        self.day = day
        self.hours = hours
        self.lunch = lunch
        self.blocks = blocks
        self.bufferMinutes = bufferMinutes
        self.recurringMinutes = recurringMinutes
        self.plannedMinutes = plannedMinutes
        let busy = busyIntervals(events: events, on: day, calendar: calendar, excluding: linkedEventIDs)
        self.busy = busy
        let capacityInput = CapacityInput(hours: hours, lunchStartMinutes: lunch?.lowerBound ?? 0,
                                          lunchMinutes: lunch?.count ?? 0, bufferMinutes: bufferMinutes,
                                          busyIntervals: busy, recurringMinutes: recurringMinutes,
                                          plannedMinutes: plannedMinutes, estimatedCount: 0)
        self.availableMinutes = capacity(capacityInput).availableMinutes

        let dayStart = day.startDate(in: calendar)
        let dayEnd = day.adding(days: 1, calendar: calendar).startDate(in: calendar)
        let dayLength = Int(dayEnd.timeIntervalSince(dayStart) / 60)
        self.events = events
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
                    deadline: deadlineCalendarIDs.contains(event.calendarID),
                    linkedToTask: linked
                )
            }
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

    public init(scope: PlanScope, days: [PlanInputDay], tasks: [PlanInputTask], today: PlanDay, nowMinutes: Int,
                timeZoneID: String, defaultTaskMinutes: Int) {
        self.scope = scope
        self.days = days
        self.tasks = tasks
        self.today = today
        self.nowMinutes = nowMinutes
        self.timeZoneID = timeZoneID
        self.defaultTaskMinutes = defaultTaskMinutes
    }
}

/// At most this many tasks go to the model per call (§11.10).
public let maxPlanTasks = 60

/// Selects and orders the tasks for a planning call (§11.10).
/// - Day: tasks assigned to the day, due on or before it, and important ones.
/// - Week/month: open tasks without an assigned day; existing assignments stay untouched.
/// - `focusTask`: "Mit KI planen" for a single task.
/// - `excluding`: tasks whose time is reserved elsewhere, such as recurring reminders (§11.9:
///   their effort is already in `recurringMinutes`, a block would count it twice).
/// Sorted by due date, then priority, then source; at most 60.
public func makePlanInput(scope: PlanScope, days: [PlanInputDay], tasks: [TaskItem], assignments: [TaskID: PlanDay],
                          anchors: [TaskID: DueDate], today: PlanDay, nowMinutes: Int, timeZoneID: String,
                          defaultTaskMinutes: Int, focusTask: TaskID? = nil, excluding: Set<TaskID> = []) -> PlanInput {
    func anchor(of task: TaskItem) -> DueDate? {
        anchors[task.id] ?? (task.epic?.isEpic == true ? task.epic?.due : nil)
    }
    func isImportant(_ task: TaskItem) -> Bool {
        (task.priority == .p1 && task.due != nil) || (task.isEpic && task.due != nil) || anchor(of: task) != nil
    }

    let open = tasks.filter { !$0.isCompleted && !excluding.contains($0.id) }
    let selected: [TaskItem]
    if let focusTask {
        selected = open.filter { $0.id == focusTask }
    } else {
        switch scope {
        case .day:
            let day = days.first?.day ?? today
            selected = open.filter { task in
                assignments[task.id] == day || task.due.map { PlanDay($0) <= day } == true || isImportant(task)
            }
        case .week, .month:
            selected = open.filter { assignments[$0.id] == nil }
        }
    }

    let sourceOrder: [TaskSource: Int] = [.github: 0, .reminders: 1, .local: 2]
    let sorted = selected.sorted { lhs, rhs in
        let lhsDue = lhs.due.map { ($0.year, $0.month, $0.day, $0.hour ?? 24, $0.minute ?? 0) } ?? (Int.max, 0, 0, 0, 0)
        let rhsDue = rhs.due.map { ($0.year, $0.month, $0.day, $0.hour ?? 24, $0.minute ?? 0) } ?? (Int.max, 0, 0, 0, 0)
        if lhsDue != rhsDue { return lhsDue < rhsDue }
        let lhsPriority = lhs.priority?.rawValue ?? 9, rhsPriority = rhs.priority?.rawValue ?? 9
        if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
        let lhsSource = sourceOrder[lhs.id.source] ?? 9, rhsSource = sourceOrder[rhs.id.source] ?? 9
        if lhsSource != rhsSource { return lhsSource < rhsSource }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    return PlanInput(
        scope: scope,
        days: days,
        tasks: sorted.prefix(maxPlanTasks).map { task in
            PlanInputTask(id: task.id.key, source: task.id.source, title: task.title, due: task.due, priority: task.priority,
                          minutes: task.estimateMinutes, important: isImportant(task), plannedDay: assignments[task.id],
                          anchor: anchor(of: task))
        },
        today: today,
        nowMinutes: nowMinutes,
        timeZoneID: timeZoneID,
        defaultTaskMinutes: defaultTaskMinutes
    )
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

public struct DayPlanOutput: Sendable, Hashable, Codable {
    public var blocks: [PlanBlock]
    public var unscheduled: [PlanUnscheduled]
    public var risks: [String]
    public var estimates: [PlanEstimate]

    public init(blocks: [PlanBlock], unscheduled: [PlanUnscheduled], risks: [String], estimates: [PlanEstimate]) {
        self.blocks = blocks
        self.unscheduled = unscheduled
        self.risks = risks
        self.estimates = estimates
    }
}

public struct PeriodPlanOutput: Sendable, Hashable, Codable {
    public var assignments: [PlanAssignment]
    public var unscheduled: [PlanUnscheduled]
    public var risks: [String]
    public var estimates: [PlanEstimate]

    public init(assignments: [PlanAssignment], unscheduled: [PlanUnscheduled], risks: [String], estimates: [PlanEstimate]) {
        self.assignments = assignments
        self.unscheduled = unscheduled
        self.risks = risks
        self.estimates = estimates
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
    public enum Reason: String, Sendable, Hashable {
        case unknownTask = "Diese Aufgabe gibt es nicht."
        case duplicate = "Die Aufgabe wurde doppelt vorgeschlagen."
        case invalidMinutes = "Die Dauer ist ungültig."
        case invalidTime = "Die Uhrzeit ist ungültig."
        case invalidDay = "Das Datum ist ungültig."
        case outsidePeriod = "Der Tag liegt außerhalb des Zeitraums."
        case inThePast = "Der Vorschlag liegt in der Vergangenheit."
        case dayOff = "Der Tag ist frei."
        case outsideWorkHours = "Der Block liegt außerhalb der Arbeitszeit."
        case overlapsLunch = "Der Block liegt in der Mittagspause."
        case overlapsEvent = "Der Block überschneidet sich mit einem Termin oder dessen Puffer."
        case overlapsBlock = "Der Block überschneidet sich mit einem anderen Block."
        case afterDue = "Der Vorschlag liegt nach der Fälligkeit."
        case afterDeadline = "Der Vorschlag liegt nach der zugehörigen Deadline."
        case alreadyAssigned = "Die Aufgabe ist schon einem Tag zugeordnet."
        case overCapacity = "Die Kapazität des Tages ist überschritten."
        case wrongScope = "Die Antwort passt nicht zum Zeitraum."
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
        let (blocks, violations) = validateBlocks(plan.blocks, input: input, tasks: tasks)
        return (.day(DayPlanOutput(blocks: blocks, unscheduled: knownUnscheduled(plan.unscheduled, tasks),
                                   risks: plan.risks, estimates: knownEstimates(plan.estimates, tasks))), violations)
    case (.period(let plan), .week), (.period(let plan), .month):
        let estimates = knownEstimates(plan.estimates, tasks)
        let (assignments, violations) = validateAssignments(
            plan.assignments, input: input, tasks: tasks,
            estimates: Dictionary(estimates.map { ($0.taskId, $0.minutes) }, uniquingKeysWith: { first, _ in first }))
        return (.period(PeriodPlanOutput(assignments: assignments, unscheduled: knownUnscheduled(plan.unscheduled, tasks),
                                         risks: plan.risks, estimates: estimates)), violations)
    case (.day(let plan), _):
        return (.period(PeriodPlanOutput(assignments: [], unscheduled: [], risks: [], estimates: [])),
                plan.blocks.map { PlanViolation(taskId: $0.taskId, reason: .wrongScope) })
    case (.period(let plan), _):
        return (.day(DayPlanOutput(blocks: [], unscheduled: [], risks: [], estimates: [])),
                plan.assignments.map { PlanViolation(taskId: $0.taskId, reason: .wrongScope) })
    }
}

private func validateBlocks(_ blocks: [PlanBlock], input: PlanInput,
                            tasks: [String: PlanInputTask]) -> ([PlanBlock], [PlanViolation]) {
    var violations: [PlanViolation] = []
    guard let day = input.days.first else {
        return ([], blocks.map { PlanViolation(taskId: $0.taskId, reason: .outsidePeriod) })
    }
    let busy = day.busy.map { ($0.lowerBound - day.bufferMinutes)..<($0.upperBound + day.bufferMinutes) }
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
        if day.blocks.contains(where: { $0.overlaps(range) }) || accepted.contains(where: { $0.range.overlaps(range) }) {
            reject(.overlapsBlock); continue
        }
        if isLate(day: day.day, endMinutes: range.upperBound, limit: task.due, input: input) { reject(.afterDue); continue }
        if isLate(day: day.day, endMinutes: range.upperBound, limit: task.anchor, input: input) { reject(.afterDeadline); continue }
        accepted.append((block, range))
    }

    // A block replaces the load its task already had on this day, so it is not counted twice.
    let replaced = accepted.reduce(0) { sum, entry in
        guard let task = tasks[entry.block.taskId], task.plannedDay == day.day else { return sum }
        return sum + (task.minutes ?? input.defaultTaskMinutes)
    }
    let base = day.plannedMinutes - replaced
    accepted.sort { $0.range.lowerBound < $1.range.lowerBound }
    while let last = accepted.last, base + accepted.reduce(0, { $0 + $1.block.minutes }) > day.availableMinutes {
        accepted.removeLast()
        violations.append(PlanViolation(taskId: last.block.taskId, reason: .overCapacity))
    }
    let kept = Set(accepted.map(\.block.taskId))
    // Keep the model's order for the accepted blocks.
    var emitted = Set<String>()
    let ordered = blocks.filter { kept.contains($0.taskId) && emitted.insert($0.taskId).inserted }
    return (ordered, violations)
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
        if (load[planDay] ?? 0) + minutes > day.availableMinutes { reject(.overCapacity); continue }
        load[planDay, default: 0] += minutes
        accepted.append(assignment)
    }
    return (accepted, violations)
}

/// True when planning on `day` (ending at `endMinutes`, if known) is later than `limit`.
/// A limit that already lies before now cannot be met any more and is not enforced:
/// overdue work may still be planned at the earliest possible time.
private func isLate(day: PlanDay, endMinutes: Int?, limit: DueDate?, input: PlanInput) -> Bool {
    guard let limit else { return false }
    let limitDay = PlanDay(limit)
    let limitMinutes = limit.hour.map { $0 * 60 + (limit.minute ?? 0) }
    if limitDay < input.today { return false }
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
    /// The input as compact JSON for the model, with readable dates and times.
    public func modelJSON() throws -> Data {
        struct Span: Encodable { let start: String; let end: String }
        struct Event: Encodable {
            let title: String; let start: String?; let end: String?; let allDay: Bool
            let busy: Bool; let deadline: Bool; let linkedToTask: Bool
        }
        struct Day: Encodable {
            let day: String; let dayOff: Bool; let workStart: String?; let workEnd: String?; let lunch: Span?
            let bufferMinutes: Int; let recurringMinutes: Int; let availableMinutes: Int; let plannedMinutes: Int
            let freeMinutes: Int; let events: [Event]; let existingBlocks: [Span]
        }
        struct Task: Encodable {
            let id: String; let source: String; let title: String; let due: String?; let priority: String?
            let minutes: Int?; let important: Bool; let plannedDay: String?; let deadline: String?
        }
        struct Body: Encodable {
            let scope: String; let now: String; let timeZone: String; let defaultTaskMinutes: Int
            let days: [Day]; let tasks: [Task]
        }
        let body = Body(
            scope: scope.rawValue,
            now: dayString(today) + "T" + timeString(nowMinutes),
            timeZone: timeZoneID,
            defaultTaskMinutes: defaultTaskMinutes,
            days: days.map { day in
                Day(day: dayString(day.day), dayOff: day.hours == nil,
                    workStart: day.hours.map { timeString($0.startMinutes) }, workEnd: day.hours.map { timeString($0.endMinutes) },
                    lunch: day.lunch.map { Span(start: timeString($0.lowerBound), end: timeString($0.upperBound)) },
                    bufferMinutes: day.bufferMinutes, recurringMinutes: day.recurringMinutes,
                    availableMinutes: day.availableMinutes, plannedMinutes: day.plannedMinutes,
                    freeMinutes: day.availableMinutes - day.plannedMinutes,
                    events: day.events.map { event in
                        Event(title: event.title, start: event.start.map(timeString), end: event.end.map(timeString),
                              allDay: event.allDay, busy: event.busy, deadline: event.deadline, linkedToTask: event.linkedToTask)
                    },
                    existingBlocks: day.blocks.map { Span(start: timeString($0.lowerBound), end: timeString($0.upperBound)) })
            },
            tasks: tasks.map { task in
                Task(id: task.id, source: task.source.rawValue, title: task.title, due: task.due.map(dueString),
                     priority: task.priority?.label, minutes: task.minutes, important: task.important,
                     plannedDay: task.plannedDay.map(dayString), deadline: task.anchor.map(dueString))
            }
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
