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
}

extension ReminderStore {
    /// Stores without completed reminders (fakes) report none.
    public func completionDates(in interval: DateInterval, listIDs: Set<String>?) async -> [Date] { [] }
}
