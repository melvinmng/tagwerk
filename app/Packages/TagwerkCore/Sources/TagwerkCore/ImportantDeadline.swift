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
    /// `markedEvent`: an event from any calendar the user marked as a deadline in Tagwerk (plan deadline-marking).
    case priorityOne, epic, deadlineCalendar, markedEvent
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
    /// Calendar of an event deadline (for its name in the deadline card).
    public var calendarID: String? = nil

    /// The key preparation events are linked under (DV1): "event:<event ID>", "task:<task key>" for P1 tasks and
    /// "epic:<issue ID>" for epics, the same whether the epic is assigned or only the parent of an assigned issue.
    public var preparationKey: String {
        if let eventID { return "event:\(eventID)" }
        if kind == .epic {
            return "epic:" + (taskID?.rawValue ?? String(id.dropFirst(id.hasPrefix("epic:") ? 5 : 0)))
        }
        return id
    }

    /// An event deadline (deadline calendar or marked).
    public var isEvent: Bool { eventID != nil }
}

/// P1 tasks with a due date, epics with a due date (assigned or as parent of an assigned issue,
/// counted once), events from deadline calendars and events marked as deadlines (`markedEventIDs`, occurrence IDs),
/// within `range`, ordered by day and time. An event in a deadline calendar that is also marked appears once.
public func importantDeadlines(tasks: [TaskItem], events: [CalendarEvent], deadlineCalendarIDs: Set<String>,
                               markedEventIDs: Set<String> = [],
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
    var seenEvents = Set<String>()
    for event in events where seenEvents.insert(event.id).inserted {
        let kind: DeadlineKind
        if deadlineCalendarIDs.contains(event.calendarID) {
            kind = .deadlineCalendar
        } else if markedEventIDs.contains(event.id) {
            kind = .markedEvent
        } else {
            continue
        }
        result.append(ImportantDeadline(id: "event:\(event.id)", title: event.title,
                                        day: PlanDay(date: event.start, calendar: calendar),
                                        time: event.isAllDay ? nil : event.start,
                                        kind: kind, taskID: nil, eventID: event.id, calendarID: event.calendarID))
    }
    return result
        .filter { range.contains($0.day) }
        .sorted { lhs, rhs in
            if lhs.day != rhs.day { return lhs.day < rhs.day }
            return (lhs.time ?? .distantPast) < (rhs.time ?? .distantPast)
        }
}
