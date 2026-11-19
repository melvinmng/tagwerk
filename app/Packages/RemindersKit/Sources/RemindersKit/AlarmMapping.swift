import Foundation
import TagwerkCore

/// Pure conversion between EventKit alarms and `ReminderOffset` (plan P4, Task 5). An `EKAlarm` stores either a
/// distance from the start of the event or due date (`relativeOffset`, negative is before) or a fixed moment.
public enum AlarmMapping {
    private static let minutesPerDay = 24 * 60

    /// The reminder for an alarm at `relativeOffset` seconds from the anchor; `nil` when Tagwerk cannot show it (after
    /// the start of a timed entry, or more than a day after the start of an all-day entry).
    ///
    /// For entries with a time the distance becomes whole weeks, days, hours or minutes before. All-day entries have
    /// their start of day as anchor: whole days stay "N days before", anything else becomes a time of day
    /// ("evening before at 18:00" = -6 h, "+9 h" = the same day at 09:00).
    public static func offset(relativeOffset: TimeInterval, isAllDay: Bool) -> ReminderOffset? {
        let minutesBefore = Int((-relativeOffset / 60).rounded())
        guard isAllDay else {
            return minutesBefore >= 0 ? ReminderOffset.largestUnit(minutes: minutesBefore) : nil
        }
        if minutesBefore >= 0, minutesBefore % minutesPerDay == 0 {
            guard case .before(let amount, let unit) = ReminderOffset.largestUnit(minutes: minutesBefore) else { return nil }
            // A distance of zero is "at the start of the day"; the unit of the picker for all-day entries is days.
            return .before(amount: amount, unit: unit.needsTimeOfDay ? .days : unit)
        }
        let daysBefore = max(0, (minutesBefore + minutesPerDay - 1) / minutesPerDay)
        let minuteOfDay = daysBefore * minutesPerDay - minutesBefore
        guard (0..<minutesPerDay).contains(minuteOfDay) else { return nil }
        return .at(daysBefore: daysBefore, hour: minuteOfDay / 60, minute: minuteOfDay % 60)
    }

    /// The `relativeOffset` of an alarm for `offset` on the entry that starts at `anchor`. Computed per occurrence, so
    /// "1 day before at 18:00" keeps its wall-clock time; a series that crosses a daylight-saving change can be an hour
    /// off for occurrences on the other side (EventKit stores one distance for the whole series). `nil` for fixed moments.
    public static func relativeOffset(for offset: ReminderOffset, anchor: Date, isAllDay: Bool, calendar: Calendar) -> TimeInterval? {
        if case .absolute = offset { return nil }
        guard let fire = offset.fireDate(anchor: anchor, isAllDay: isAllDay, calendar: calendar) else { return nil }
        let start = isAllDay ? calendar.startOfDay(for: anchor) : anchor
        return fire.timeIntervalSince(start)
    }
}
