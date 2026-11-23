import Foundation

/// How the pending local notifications iOS allows per app are shared between features (plan P4).
public enum NotificationBudget {
    /// iOS keeps this many pending notifications per app and drops the rest.
    public static let system = 64
    /// Task and deadline reminders, planned on a rolling basis ("tagwerk.task.", "tagwerk.event.").
    public static let tasksAndDeadlines = 44
    /// Routine reminders ("tagwerk.routine."): the evening points for the next three days (four points a day), the
    /// repeating morning start and the weekly planning, and Bible Study for the next three days (BS7).
    public static let routines = 17
    /// The focus timer ("tagwerk.focus.").
    public static let focusTimer = 1
    /// Left over for future features.
    public static let reserve = 2

    /// Everything that is assigned, reserve included.
    public static var allocated: Int { tasksAndDeadlines + routines + focusTimer + reserve }
}
