import Foundation
import TagwerkCore
@testable import RemindersKit

/// In-memory reminder store. Tests can change `records` between loading and writing
/// to simulate an edit made in the Reminders app.
@MainActor
final class FakeReminderStore: ReminderStore {
    var accessState: AccessState = .fullAccess
    var calendarAccessState: AccessState = .fullAccess
    var calendarInfos: [ListInfo] = []
    var listInfos: [ListInfo] = []
    var records: [String: ReminderRecord] = [:]
    var defaultListID = "inbox"
    private(set) var saveCount = 0
    /// The recurrence change passed with every save, in order.
    private(set) var recurrenceChanges: [FieldChange<Recurrence?>] = []
    /// The recurrence passed with every create, in order.
    private(set) var createdRecurrences: [Recurrence?] = []
    private var clock = Date(timeIntervalSince1970: 1_000)

    func requestAccess() async throws -> AccessState { accessState }

    func requestCalendarAccess() async throws -> AccessState { calendarAccessState }

    func lists() -> [ListInfo] { listInfos }

    func calendars() -> [ListInfo] { calendarInfos }

    func openReminders(in listIDs: Set<String>?) async -> [ReminderRecord] {
        records.values
            .filter { !$0.isCompleted && (listIDs?.contains($0.listID) ?? true) }
            .sorted { $0.id < $1.id }
    }

    func reminder(id: String) -> ReminderRecord? { records[id] }

    /// Like the gateway: the rule changes only through `recurrence`, never through `record.recurrence`.
    func save(_ record: ReminderRecord, recurrence: FieldChange<Recurrence?>) throws -> ReminderRecord {
        saveCount += 1
        recurrenceChanges.append(recurrence)
        var stored = record
        stored.recurrence = records[record.id]?.recurrence
        if case .set(let newRecurrence) = recurrence { stored.recurrence = newRecurrence }
        if let due = stored.due { stored.recurrence?.start = PlanDay(due) } else { stored.recurrence = nil }
        stored.lastModified = tick()
        records[record.id] = stored
        return stored
    }

    func create(title: String, notes: String?, due: DueDate?, ekPriority: Int, listID: String?,
                recurrence: Recurrence?) throws -> ReminderRecord {
        createdRecurrences.append(recurrence)
        let record = ReminderRecord(
            id: "new-\(records.count + 1)", title: title, notes: notes, due: due, ekPriority: ekPriority,
            isCompleted: false, listID: listID ?? defaultListID, lastModified: tick(), recurrence: recurrence
        )
        records[record.id] = record
        return record
    }

    func delete(id: String) throws {
        guard records.removeValue(forKey: id) != nil else { throw TaskWriteError.notFound }
    }

    /// Simulates a change from outside the app.
    func modifyExternally(_ id: String, _ change: (inout ReminderRecord) -> Void) {
        guard var record = records[id] else { return }
        change(&record)
        record.lastModified = tick()
        records[id] = record
    }

    private func tick() -> Date {
        clock = clock.addingTimeInterval(1)
        return clock
    }
}
