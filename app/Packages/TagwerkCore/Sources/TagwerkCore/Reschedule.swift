import Foundation

/// Targets offered when moving a task.
public enum RescheduleOption: Sendable, Hashable {
    case tomorrow
    /// The next Monday strictly after today (on a Monday: one week later).
    case nextMonday
    /// The next Saturday strictly after today (on a Saturday: one week later).
    case weekend
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
        target = nextWeekday(2, after: startOfToday, calendar: calendar)
    case .weekend:
        target = nextWeekday(7, after: startOfToday, calendar: calendar)
    case .date(let day):
        target = DueDate(year: day.year, month: day.month, day: day.day)
    }
    return due?.movedTo(day: target) ?? target
}

/// The next date with `weekday` (1 = Sunday … 7 = Saturday) strictly after `day`, without time.
private func nextWeekday(_ weekday: Int, after day: Date, calendar: Calendar) -> DueDate {
    let date = calendar.nextDate(after: day, matching: DateComponents(weekday: weekday), matchingPolicy: .nextTime) ?? day
    return DueDate(date: date, includeTime: false, calendar: calendar)
}
