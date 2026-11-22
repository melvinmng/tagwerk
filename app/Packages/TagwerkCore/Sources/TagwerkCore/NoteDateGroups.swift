import Foundation

/// The date groups of a sorted note list (design NO7b): "Angeheftet", "Heute", "Letzte 7 Tage", then one group per month.
public enum NoteDateGroups {
    public enum Group: Sendable, Hashable {
        case pinned
        case today
        /// Yesterday back to seven days ago.
        case lastSevenDays
        case month(year: Int, month: Int)
    }

    /// The group of a note by the date its list is sorted by. A pinned note belongs to the first group, whatever its date.
    /// A date in the future counts as today. Days are counted between calendar days, so a day with a time change
    /// still has one day to the next.
    public static func group(of date: Date, isPinned: Bool, now: Date, calendar: Calendar) -> Group {
        if isPinned { return .pinned }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days <= 0 { return .today }
        if days <= 7 { return .lastSevenDays }
        let parts = calendar.dateComponents([.year, .month], from: date)
        return .month(year: parts.year ?? 0, month: parts.month ?? 0)
    }

    /// The items cut into groups in the order of their first appearance, so the list direction decides the order of
    /// the groups; the items keep the order they came in inside a group.
    public static func grouped<ID>(_ items: [(id: ID, date: Date, isPinned: Bool)], now: Date,
                                   calendar: Calendar) -> [(group: Group, ids: [ID])] {
        var result: [(group: Group, ids: [ID])] = []
        var positions: [Group: Int] = [:]
        for item in items {
            let group = group(of: item.date, isPinned: item.isPinned, now: now, calendar: calendar)
            if let position = positions[group] {
                result[position].ids.append(item.id)
            } else {
                positions[group] = result.count
                result.append((group, [item.id]))
            }
        }
        return result
    }
}
