import Foundation

/// The parent issue of a GitHub sub-issue.
public struct EpicInfo: Sendable, Hashable, Codable {
    public let id: String
    public let number: Int
    public let title: String
    public let due: DueDate?
    /// True when the parent carries the label `epic`.
    public let isEpic: Bool

    public init(id: String, number: Int, title: String, due: DueDate?, isEpic: Bool) {
        self.id = id
        self.number = number
        self.title = title
        self.due = due
        self.isEpic = isEpic
    }
}

public enum DeadlineKind: Sendable, Hashable {
    case priorityOne, epic, deadlineCalendar
}

/// A deadline that stands out in day, week and month (design §6.2).
public struct ImportantDeadline: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let day: PlanDay
    /// Exact time when known; `nil` for date-only deadlines and all-day events.
    public let time: Date?
    public let kind: DeadlineKind
    public let taskID: TaskID?
    public let eventID: String?
}

/// P1 tasks with a due date, epics with a due date (assigned or as parent of an assigned issue,
/// counted once) and events from deadline calendars, within `range`, ordered by day and time.
public func importantDeadlines(tasks: [TaskItem], events: [CalendarEvent], deadlineCalendarIDs: Set<String>,
                               in range: ClosedRange<PlanDay>, calendar: Calendar) -> [ImportantDeadline] {
    var result: [ImportantDeadline] = []
    var seenEpics = Set<String>()

    for task in tasks where !task.isCompleted {
        guard let due = task.due else { continue }
        let time = due.hasTime ? due.startDate(in: calendar) : nil
        if task.isEpic {
            seenEpics.insert(task.id.rawValue)
            result.append(ImportantDeadline(id: "task:\(task.id.key)", title: task.title, day: PlanDay(due), time: time,
                                            kind: .epic, taskID: task.id, eventID: nil))
        } else if task.priority == .p1 {
            result.append(ImportantDeadline(id: "task:\(task.id.key)", title: task.title, day: PlanDay(due), time: time,
                                            kind: .priorityOne, taskID: task.id, eventID: nil))
        }
    }
    for task in tasks {
        guard let epic = task.epic, epic.isEpic, let due = epic.due, !seenEpics.contains(epic.id) else { continue }
        seenEpics.insert(epic.id)
        result.append(ImportantDeadline(id: "epic:\(epic.id)", title: epic.title, day: PlanDay(due),
                                        time: due.hasTime ? due.startDate(in: calendar) : nil,
                                        kind: .epic, taskID: nil, eventID: nil))
    }
    for event in events where deadlineCalendarIDs.contains(event.calendarID) {
        result.append(ImportantDeadline(id: "event:\(event.id)", title: event.title,
                                        day: PlanDay(date: event.start, calendar: calendar),
                                        time: event.isAllDay ? nil : event.start,
                                        kind: .deadlineCalendar, taskID: nil, eventID: event.id))
    }
    return result
        .filter { range.contains($0.day) }
        .sorted { lhs, rhs in
            if lhs.day != rhs.day { return lhs.day < rhs.day }
            return (lhs.time ?? .distantPast) < (rhs.time ?? .distantPast)
        }
}
