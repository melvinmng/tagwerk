import Foundation
import RemindersKit
import TagwerkCore

/// In-memory reminder store with lists, writing and completed reminders, for app tests that need
/// more than `FakeAccessStore` (shopping list, exclusion from tasks).
@MainActor
final class InMemoryReminderStore: ReminderStore {
    var accessState: AccessState = .fullAccess
    var calendarAccessState: AccessState = .fullAccess
    var listInfos: [ListInfo]
    var records: [String: ReminderRecord] = [:]
    /// The list a new reminder without a list goes to.
    var defaultList: String?
    var now: () -> Date
    /// Deleting one of these fails with `TaskWriteError.failed`.
    var failingDeleteIDs: Set<String> = []
    private(set) var createCount = 0
    private(set) var saveCount = 0

    init(lists: [ListInfo] = [], records: [ReminderRecord] = [], defaultList: String? = nil,
         now: @escaping () -> Date = Date.init) {
        self.listInfos = lists
        self.records = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.defaultList = defaultList
        self.now = now
    }

    func requestAccess() async throws -> AccessState { accessState }
    func requestCalendarAccess() async throws -> AccessState { calendarAccessState }
    func lists() -> [ListInfo] { listInfos }
    func calendars() -> [ListInfo] { [] }

    func openReminders(in listIDs: Set<String>?) async -> [ReminderRecord] {
        records.values
            .filter { !$0.isCompleted && (listIDs?.contains($0.listID) ?? true) }
            .sorted { $0.id < $1.id }
    }

    func completedReminders(in interval: DateInterval, listIDs: Set<String>) async -> [ReminderRecord] {
        records.values
            .filter { record in
                guard record.isCompleted, listIDs.contains(record.listID), let date = record.completedAt else { return false }
                return interval.contains(date)
            }
            .sorted { $0.id < $1.id }
    }

    func completionDates(in interval: DateInterval, listIDs: Set<String>?) async -> [Date] {
        records.values
            .filter { $0.isCompleted && (listIDs?.contains($0.listID) ?? true) }
            .compactMap(\.completedAt)
            .filter { interval.contains($0) }
            .sorted()
    }

    func defaultListID() -> String? { defaultList }

    func reminder(id: String) -> ReminderRecord? { records[id] }

    func save(_ record: ReminderRecord, recurrence: FieldChange<Recurrence?>) throws -> ReminderRecord {
        guard let previous = records[record.id] else { throw TaskWriteError.notFound }
        saveCount += 1
        var stored = record
        stored.recurrence = previous.recurrence
        if case .set(let newRecurrence) = recurrence { stored.recurrence = newRecurrence }
        stored.lastModified = now()
        stored.createdAt = previous.createdAt
        // Like EventKit: the completion date follows the completed flag.
        if stored.isCompleted {
            stored.completedAt = previous.isCompleted ? previous.completedAt : now()
        } else {
            stored.completedAt = nil
        }
        records[record.id] = stored
        return stored
    }

    func create(title: String, notes: String?, due: DueDate?, ekPriority: Int, listID: String?,
                recurrence: Recurrence?) throws -> ReminderRecord {
        guard let list = listID ?? defaultList, listInfos.contains(where: { $0.id == list }) else {
            throw TaskWriteError.failed("Keine Erinnerungsliste gefunden")
        }
        createCount += 1
        let record = ReminderRecord(id: "new-\(createCount)", title: title, notes: notes, due: due, ekPriority: ekPriority,
                                    isCompleted: false, listID: list, lastModified: now(), recurrence: recurrence,
                                    createdAt: now())
        records[record.id] = record
        return record
    }

    func delete(id: String) throws {
        if failingDeleteIDs.contains(id) { throw TaskWriteError.failed("delete failed") }
        guard records.removeValue(forKey: id) != nil else { throw TaskWriteError.notFound }
    }
}
