import Foundation

/// Sections of the task list.
public enum TaskSection: CaseIterable, Sendable, Hashable {
    case overdue, today, thisWeek, later, noDate

    public var title: String {
        switch self {
        case .overdue: String(localized: "Überfällig", bundle: .module)
        case .today: String(localized: "Heute", bundle: .module)
        case .thisWeek: String(localized: "Diese Woche", bundle: .module)
        case .later: String(localized: "Später", bundle: .module)
        case .noDate: String(localized: "Ohne Datum", bundle: .module)
        }
    }
}

/// Section of `item` relative to `now`. Dates without time compare by calendar day only;
/// timed dates compare by instant. The week follows `calendar.firstWeekday`.
public func section(for item: TaskItem, now: Date, calendar: Calendar) -> TaskSection {
    guard let due = item.due else { return .noDate }
    let today = DueDate(date: now, includeTime: false, calendar: calendar)

    switch due.compareDay(with: today) {
    case .orderedAscending:
        return .overdue
    case .orderedSame:
        return due.hasTime && due.startDate(in: calendar) < now ? .overdue : .today
    case .orderedDescending:
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return .later }
        let dueDay = DueDate(year: due.year, month: due.month, day: due.day).startDate(in: calendar)
        return dueDay < week.end ? .thisWeek : .later
    }
}

/// Groups items into non-empty sections in display order. Within a section: earliest due first,
/// then priority (P1 first, none last), then source (Reminders, GitHub, local), then title.
public func groupedSections(_ items: [TaskItem], now: Date, calendar: Calendar) -> [(TaskSection, [TaskItem])] {
    let bySection = Dictionary(grouping: items) { section(for: $0, now: now, calendar: calendar) }
    return TaskSection.allCases.compactMap { section in
        guard let members = bySection[section], !members.isEmpty else { return nil }
        return (section, members.sorted { isOrderedBefore($0, $1, calendar: calendar) })
    }
}

/// The app-wide task order: earliest due first (none last), then priority (P1 first, none last), then source
/// (Reminders, GitHub, local), then title. Used by every list of tasks.
public func sortedTasks(_ items: [TaskItem], calendar: Calendar) -> [TaskItem] {
    items.sorted { isOrderedBefore($0, $1, calendar: calendar) }
}

public func isOrderedBefore(_ lhs: TaskItem, _ rhs: TaskItem, calendar: Calendar) -> Bool {
    let lhsDue = lhs.due?.startDate(in: calendar) ?? .distantFuture
    let rhsDue = rhs.due?.startDate(in: calendar) ?? .distantFuture
    if lhsDue != rhsDue { return lhsDue < rhsDue }
    let lhsPriority = lhs.priority?.rawValue ?? Int.max
    let rhsPriority = rhs.priority?.rawValue ?? Int.max
    if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
    let lhsSource = TaskSource.allCases.firstIndex(of: lhs.id.source) ?? 0
    let rhsSource = TaskSource.allCases.firstIndex(of: rhs.id.source) ?? 0
    if lhsSource != rhsSource { return lhsSource < rhsSource }
    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
}
