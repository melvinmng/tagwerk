import Foundation
import RemindersKit
import TagwerkCore

/// Reminder store that only models access requests and calendars, for onboarding tests.
@MainActor
final class FakeAccessStore: ReminderStore {
    var accessState: AccessState = .notDetermined
    var calendarAccessState: AccessState = .notDetermined
    var reminderAnswer: AccessState = .fullAccess
    var calendarAnswer: AccessState = .fullAccess
    var calendarInfos: [ListInfo] = []
    var openRecords: [ReminderRecord] = []
    private(set) var reminderRequests = 0
    private(set) var calendarRequests = 0

    func requestAccess() async throws -> AccessState {
        reminderRequests += 1
        accessState = reminderAnswer
        return accessState
    }

    func requestCalendarAccess() async throws -> AccessState {
        calendarRequests += 1
        calendarAccessState = calendarAnswer
        return calendarAccessState
    }

    func lists() -> [ListInfo] { [] }
    func calendars() -> [ListInfo] { calendarInfos }
    func openReminders(in listIDs: Set<String>?) async -> [ReminderRecord] { openRecords }
    func reminder(id: String) -> ReminderRecord? { nil }
    func save(_ record: ReminderRecord, recurrence: FieldChange<Recurrence?>) throws -> ReminderRecord { record }
    func delete(id: String) throws {}
    func create(title: String, notes: String?, due: DueDate?, ekPriority: Int, listID: String?,
                recurrence: Recurrence?) throws -> ReminderRecord {
        throw TaskWriteError.failed("not supported")
    }
}
