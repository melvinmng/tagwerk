import Foundation
@testable import TagwerkCore

/// Gregorian calendar with Monday as first weekday in the given time zone.
func makeCalendar(_ identifier: String = "Europe/Berlin") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 2
    calendar.timeZone = TimeZone(identifier: identifier)!
    return calendar
}

/// Absolute instant for a wall-clock time in the given calendar.
func instant(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0,
             in calendar: Calendar = makeCalendar()) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

func makeItem(_ title: String, due: DueDate? = nil, priority: Priority? = nil,
              source: TaskSource = .local) -> TaskItem {
    TaskItem(
        id: TaskID(source: source, rawValue: title),
        title: title,
        notes: nil,
        due: due,
        priority: priority,
        estimateMinutes: nil,
        isCompleted: false,
        container: TaskContainer(id: "local", name: "Lokal", colorHex: nil),
        url: nil,
        version: "1",
        editableFields: [.title, .notes, .due, .priority, .estimate]
    )
}
