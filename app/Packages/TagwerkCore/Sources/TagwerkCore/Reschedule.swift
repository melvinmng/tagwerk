import Foundation

/// Targets offered when moving a task.
public enum RescheduleOption: Sendable, Hashable {
    case tomorrow
    /// The next Monday strictly after today (on a Monday: one week later).
    case nextMonday
    case date(DueDate)
}

/// New due date for `due` moved by `option`. A time of day is kept; a task without due date
/// gets a date without time.
public func rescheduled(_ due: DueDate?, option: RescheduleOption, now: Date, calendar: Calendar) -> DueDate {
    let startOfToday = calendar.startOfDay(for: now)
    let target: DueDate
    switch option {
    case .tomorrow:
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        target = DueDate(date: tomorrow, includeTime: false, calendar: calendar)
    case .nextMonday:
        let monday = calendar.nextDate(
            after: startOfToday, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime
        ) ?? startOfToday
        target = DueDate(date: monday, includeTime: false, calendar: calendar)
    case .date(let day):
        target = DueDate(year: day.year, month: day.month, day: day.day)
    }
    return due?.movedTo(day: target) ?? target
}
