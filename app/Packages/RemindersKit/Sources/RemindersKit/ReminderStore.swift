import Foundation
import TagwerkCore

/// Access to reminders. `EventKitGateway` is the real implementation; tests use a fake.
@MainActor
public protocol ReminderStore: AnyObject {
    var accessState: AccessState { get }
    var calendarAccessState: AccessState { get }
    func requestAccess() async throws -> AccessState
    func requestCalendarAccess() async throws -> AccessState
    func lists() -> [ListInfo]
    /// Event calendars, for the calendar selection.
    func calendars() -> [ListInfo]
    /// Incomplete reminders in the given lists; `nil` means all lists.
    func openReminders(in listIDs: Set<String>?) async -> [ReminderRecord]
    /// Fresh state of one reminder (refreshed from the store), or `nil` if it no longer exists.
    func reminder(id: String) -> ReminderRecord?
    /// Writes the changed fields of `record`. The repetition is written only when `recurrence` is `.set`;
    /// `record.recurrence` is ignored, because its start follows the due date (plan §6, rule 1).
    func save(_ record: ReminderRecord, recurrence: FieldChange<Recurrence?>) throws -> ReminderRecord
    func delete(id: String) throws
    func create(title: String, notes: String?, due: DueDate?, ekPriority: Int, listID: String?,
                recurrence: Recurrence?) throws -> ReminderRecord
    /// Completion dates of reminders completed within `interval` in the given lists; `nil` means all lists.
    func completionDates(in interval: DateInterval, listIDs: Set<String>?) async -> [Date]
    /// Reminders completed within `interval` in the given lists. An empty set means no list.
    func completedReminders(in interval: DateInterval, listIDs: Set<String>) async -> [ReminderRecord]
    /// The list the store uses for a new reminder without a list, if it tells.
    func defaultListID() -> String?
    /// Makes sure the reminder has alarms at these distances from its due date; alarms that exist already are kept and
    /// nothing else is touched. Needs a due date.
    func setAlarms(_ offsets: [ReminderOffset], forReminder id: String) throws
    /// Removes the alarms at exactly these distances and keeps every other alarm, such as those made in the Reminders app.
    func removeAlarms(_ offsets: [ReminderOffset], forReminder id: String) throws
}

extension ReminderStore {
    /// Stores without completed reminders (fakes) report none.
    public func completionDates(in interval: DateInterval, listIDs: Set<String>?) async -> [Date] { [] }

    /// Stores without completed reminders (fakes) report none.
    public func completedReminders(in interval: DateInterval, listIDs: Set<String>) async -> [ReminderRecord] { [] }

    /// Stores that do not expose their default list report none; callers then keep the store's own choice.
    public func defaultListID() -> String? { nil }

    /// Stores without alarm support ignore the request.
    public func setAlarms(_ offsets: [ReminderOffset], forReminder id: String) throws {}

    /// Stores without alarm support ignore the request.
    public func removeAlarms(_ offsets: [ReminderOffset], forReminder id: String) throws {}
}
