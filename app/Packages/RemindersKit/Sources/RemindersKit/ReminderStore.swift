import TagwerkCore

/// Access to reminders. `EventKitGateway` is the real implementation; tests use a fake.
@MainActor
public protocol ReminderStore: AnyObject {
    var accessState: AccessState { get }
    func requestAccess() async throws -> AccessState
    func lists() -> [ListInfo]
    /// Incomplete reminders in the given lists; `nil` means all lists.
    func openReminders(in listIDs: Set<String>?) async -> [ReminderRecord]
    /// Fresh state of one reminder (refreshed from the store), or `nil` if it no longer exists.
    func reminder(id: String) -> ReminderRecord?
    func save(_ record: ReminderRecord) throws -> ReminderRecord
    func create(title: String, notes: String?, due: DueDate?, ekPriority: Int, listID: String?) throws -> ReminderRecord
}
