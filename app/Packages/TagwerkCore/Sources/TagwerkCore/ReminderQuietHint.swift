import Foundation

/// Tells the reminder list when quiet hours hold a reminder back (plan g1, RH6c), so the effect is visible while setting
/// reminders up and not only in the morning.
public enum ReminderQuietHint {
    /// When a reminder is delivered instead of its own moment because it falls into the quiet hours; nil when it fires as
    /// set (also without quiet hours).
    public static func delivery(of offset: ReminderOffset, anchor: Date, isAllDay: Bool, quietHours: QuietHours?,
                                calendar: Calendar) -> Date? {
        guard let quietHours, !quietHours.isEmpty,
              let fire = offset.fireDate(anchor: anchor, isAllDay: isAllDay, calendar: calendar),
              quietHours.contains(fire, calendar: calendar) else { return nil }
        return quietHours.nextEnd(after: fire, calendar: calendar)
    }
}
