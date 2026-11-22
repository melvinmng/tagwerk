import Foundation

/// The rows of the reminder selection page (plan g1, ER2b): the usual distances plus whatever is set.
public enum ReminderChoices {
    /// The usual distances: with a time 0, 15 min, 1 h, 1 day, 1 week; without a time 0 days, 1 day, 1 week.
    public static func common(isAllDay: Bool) -> [ReminderOffset] {
        if isAllDay {
            return [.before(amount: 0, unit: .days), .before(amount: 1, unit: .days), .before(amount: 1, unit: .weeks)]
        }
        return [.before(amount: 0, unit: .minutes), .before(amount: 15, unit: .minutes), .before(amount: 1, unit: .hours),
                .before(amount: 1, unit: .days), .before(amount: 1, unit: .weeks)]
    }

    /// The common distances and every reminder that is set, without duplicates (equal distances count once, the common
    /// spelling wins). The nearest reminder comes first, as in the iOS calendar; fixed moments read from the calendar
    /// come last.
    public static func rows(selected: [ReminderOffset], isAllDay: Bool) -> [ReminderOffset] {
        let all = ReminderOffset.normalized(common(isAllDay: isAllDay) + selected, isAllDay: isAllDay)
        func isAbsolute(_ offset: ReminderOffset) -> Bool {
            if case .absolute = offset { return true }
            return false
        }
        return all.filter { !isAbsolute($0) }.reversed() + all.filter(isAbsolute)
    }
}
