import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct LocalTaskProviderTests {
    let container: ModelContainer
    let provider: LocalTaskProvider

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        provider = LocalTaskProvider(context: container.mainContext)
    }

    private func titleEdit(_ title: String) -> TaskEdit {
        var edit = TaskEdit()
        edit.title = .set(title)
        return edit
    }

    @Test func create_thenOpenTasks_containsItem() async throws {
        let created = try await provider.create(TaskDraft(title: "Fahrrad reparieren", priority: .p3))
        let items = try await provider.openTasks()
        #expect(items == [created])
        #expect(created.id.source == .local)
        #expect(created.container == TaskContainer(id: "local", name: "Lokal", colorHex: nil))
        #expect(created.editableFields == [.title, .notes, .due, .priority, .estimate, .recurrence])
        #expect(created.priority == .p3)
    }

    @Test func openTasks_excludesCompleted() async throws {
        let done = try await provider.create(TaskDraft(title: "Erledigt"))
        _ = try await provider.create(TaskDraft(title: "Offen"))
        var edit = TaskEdit()
        edit.isCompleted = .set(true)
        _ = try await provider.apply(edit, to: done.id, expectedVersion: done.version)

        #expect(try await provider.openTasks().map(\.title) == ["Offen"])
    }

    @Test func apply_incrementsRevision() async throws {
        let created = try await provider.create(TaskDraft(title: "Alt"))
        let updated = try await provider.apply(titleEdit("Neu"), to: created.id, expectedVersion: created.version)
        #expect(updated.title == "Neu")
        #expect(Int(updated.version) == Int(created.version)! + 1)
    }

    @Test func apply_staleVersion_throwsConflict() async throws {
        let created = try await provider.create(TaskDraft(title: "Alt"))
        _ = try await provider.apply(titleEdit("Zwischendurch"), to: created.id, expectedVersion: created.version)

        do {
            _ = try await provider.apply(titleEdit("Neu"), to: created.id, expectedVersion: created.version)
            Issue.record("expected a conflict")
        } catch TaskWriteError.conflict(let current) {
            #expect(current.title == "Zwischendurch")
        }
        #expect(try await provider.task(id: created.id)?.title == "Zwischendurch")
    }

    @Test func apply_nilVersion_forces() async throws {
        let created = try await provider.create(TaskDraft(title: "Alt"))
        _ = try await provider.apply(titleEdit("Zwischendurch"), to: created.id, expectedVersion: created.version)
        let forced = try await provider.apply(titleEdit("Neu"), to: created.id, expectedVersion: nil)
        #expect(forced.title == "Neu")
    }

    @Test func apply_dueWithoutTime_roundTripsAsDateOnly() async throws {
        let created = try await provider.create(TaskDraft(title: "Abgabe"))
        var edit = TaskEdit()
        edit.due = .set(DueDate(year: 2026, month: 11, day: 20))
        _ = try await provider.apply(edit, to: created.id, expectedVersion: created.version)

        let reloaded = try #require(try await provider.task(id: created.id))
        #expect(reloaded.due == DueDate(year: 2026, month: 11, day: 20))
        #expect(reloaded.due?.hasTime == false)
    }

    @Test func apply_allFields_roundTrip() async throws {
        let created = try await provider.create(TaskDraft(title: "A", notes: "n", priority: .p1, estimateMinutes: 30))
        var edit = TaskEdit()
        edit.notes = .set(nil)
        edit.due = .set(DueDate(year: 2026, month: 11, day: 20, hour: 9, minute: 45))
        edit.priority = .set(nil)
        edit.estimateMinutes = .set(90)
        let updated = try await provider.apply(edit, to: created.id, expectedVersion: created.version)
        #expect(updated.notes == nil)
        #expect(updated.due == DueDate(year: 2026, month: 11, day: 20, hour: 9, minute: 45))
        #expect(updated.priority == nil)
        #expect(updated.estimateMinutes == 90)
        #expect(updated.title == "A")
    }

    @Test func delete_removesTask() async throws {
        let created = try await provider.create(TaskDraft(title: "Weg damit"))
        try await provider.delete(created.id, expectedVersion: created.version)
        #expect(try await provider.task(id: created.id) == nil)
    }

    @Test func delete_staleVersion_throwsConflict() async throws {
        let created = try await provider.create(TaskDraft(title: "Alt"))
        _ = try await provider.apply(titleEdit("Neu"), to: created.id, expectedVersion: created.version)
        await #expect(throws: TaskWriteError.self) { try await provider.delete(created.id, expectedVersion: created.version) }
        #expect(try await provider.task(id: created.id) != nil)
    }

    @Test func apply_unknownID_throwsNotFound() async {
        await #expect(throws: TaskWriteError.notFound) {
            try await provider.apply(titleEdit("x"), to: TaskID(source: .local, rawValue: UUID().uuidString), expectedVersion: nil)
        }
    }
}

@MainActor
struct AppSettingsTests {
    @Test func settings_current_createsSingleInstanceOnce() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let first = try AppSettings.current(in: container.mainContext)
        let second = try AppSettings.current(in: container.mainContext)
        #expect(first === second)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<AppSettings>()) == 1)
    }

    @Test func settings_defaults_matchPlan() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let settings = try AppSettings.current(in: container.mainContext)
        #expect(settings.workdayStartMinutes == 540)
        #expect(settings.workdayEndMinutes == 1080)
        #expect(settings.lunchStartMinutes == 720)
        #expect(settings.lunchDurationMinutes == 60)
        #expect(settings.bufferMinutes == 10)
        #expect(settings.leadTimeMinutes == 120)
        #expect(settings.selectedCalendarIDs == nil)
        #expect(settings.selectedReminderListIDs == nil)
        #expect(settings.setupCompleted == false)
    }
}

@MainActor
struct LocalTaskCompletionTests {
    let container: ModelContainer
    let provider: LocalTaskProvider

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        provider = LocalTaskProvider(context: container.mainContext)
    }

    @Test func localTask_complete_setsCompletedAt_reopenClears() async throws {
        let created = try await provider.create(TaskDraft(title: "Abgabe vorbereiten"))
        var complete = TaskEdit()
        complete.isCompleted = .set(true)
        let done = try await provider.apply(complete, to: created.id, expectedVersion: nil)
        let week = DateInterval(start: .now.addingTimeInterval(-3600), duration: 7200)
        #expect(provider.completionDates(in: week).count == 1)
        var reopen = TaskEdit()
        reopen.isCompleted = .set(false)
        _ = try await provider.apply(reopen, to: done.id, expectedVersion: nil)
        #expect(provider.completionDates(in: week).isEmpty)
    }
}

/// Repeating local tasks (plan 2026-11-18, stage 2): the rule is stored in Tagwerk, ticking off moves the due date.
@MainActor
struct LocalTaskRecurrenceTests {
    let container: ModelContainer
    let provider: LocalTaskProvider
    let due = DueDate(year: 2026, month: 11, day: 18, hour: 9, minute: 30)

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        provider = LocalTaskProvider(context: container.mainContext, calendar: testCalendar(), now: testNow)
    }

    private func daily(count: Int? = nil) -> Recurrence {
        Recurrence(rule: .daily(interval: 1), start: PlanDay(year: 2026, month: 11, day: 18), end: nil, count: count)
    }

    private func repeating(count: Int? = 3) async throws -> TaskItem {
        try await provider.create(TaskDraft(title: "Karteikarten", due: due, recurrence: daily(count: count)))
    }

    private func complete(_ item: TaskItem) async throws -> TaskItem {
        var edit = TaskEdit()
        edit.isCompleted = .set(true)
        return try await provider.apply(edit, to: item.id, expectedVersion: item.version)
    }

    private func reopen(_ item: TaskItem, version: String?) async throws -> TaskItem {
        var edit = TaskEdit()
        edit.isCompleted = .set(false)
        return try await provider.apply(edit, to: item.id, expectedVersion: version)
    }

    private var week: DateInterval { DateInterval(start: testNow().addingTimeInterval(-86_400), duration: 7 * 86_400) }

    @Test func create_withRecurrence_roundTrips() async throws {
        let created = try await repeating()
        let reloaded = try #require(try await provider.task(id: created.id))
        #expect(reloaded.recurrence == daily(count: 3))
        #expect(reloaded.editableFields.contains(.recurrence))
    }

    @Test func create_recurrenceWithoutDue_fails() async {
        await #expect(throws: TaskWriteError.self) {
            try await provider.create(TaskDraft(title: "Ohne Datum", recurrence: daily()))
        }
    }

    /// The start of the series follows the due date, like for reminders.
    @Test func movingDue_movesStartOfSeries() async throws {
        let created = try await repeating()
        var edit = TaskEdit()
        edit.due = .set(DueDate(year: 2026, month: 11, day: 25))
        let moved = try await provider.apply(edit, to: created.id, expectedVersion: created.version)
        #expect(moved.recurrence?.start == PlanDay(year: 2026, month: 11, day: 25))
        #expect(moved.recurrence?.rule == .daily(interval: 1))
    }

    @Test func apply_setsAndRemovesRecurrence() async throws {
        let created = try await provider.create(TaskDraft(title: "Lesen", due: due))
        var set = TaskEdit()
        set.recurrence = .set(daily())
        let repeating = try await provider.apply(set, to: created.id, expectedVersion: created.version)
        #expect(repeating.recurrence == daily())
        var clear = TaskEdit()
        clear.recurrence = .set(nil)
        let single = try await provider.apply(clear, to: created.id, expectedVersion: repeating.version)
        #expect(single.recurrence == nil)
    }

    @Test func apply_recurrenceWithoutDue_fails() async throws {
        let created = try await provider.create(TaskDraft(title: "Lesen"))
        var edit = TaskEdit()
        edit.recurrence = .set(daily())
        await #expect(throws: TaskWriteError.self) {
            try await provider.apply(edit, to: created.id, expectedVersion: created.version)
        }
    }

    @Test func apply_clearingDue_removesRecurrence() async throws {
        let created = try await repeating()
        var edit = TaskEdit()
        edit.due = .set(nil)
        let updated = try await provider.apply(edit, to: created.id, expectedVersion: created.version)
        #expect(updated.recurrence == nil)
        #expect(try await provider.task(id: created.id)?.recurrence == nil)
    }

    @Test func apply_titleOnly_keepsRecurrence() async throws {
        let created = try await repeating()
        var edit = TaskEdit()
        edit.title = .set("Vokabeln")
        let updated = try await provider.apply(edit, to: created.id, expectedVersion: created.version)
        #expect(updated.recurrence == daily(count: 3))
    }

    @Test func complete_movesToNextOccurrence_keepsTimeAndStaysOpen() async throws {
        let done = try await complete(try await repeating(count: 3))
        #expect(done.isCompleted == false)
        #expect(done.due == DueDate(year: 2026, month: 11, day: 19, hour: 9, minute: 30))
        #expect(done.recurrence?.count == 2)
        #expect(try await provider.openTasks().map(\.id) == [done.id])
    }

    @Test func complete_lastOccurrence_completesTask() async throws {
        let done = try await complete(try await repeating(count: 1))
        #expect(done.isCompleted)
        #expect(done.due == due)
        #expect(try await provider.openTasks().isEmpty)
    }

    @Test func undo_restoresDueAndCountExactly() async throws {
        let done = try await complete(try await repeating(count: 3))
        let undone = try await reopen(done, version: done.version)
        #expect(undone.isCompleted == false)
        #expect(undone.due == due)
        #expect(undone.recurrence == daily(count: 3))
        #expect(provider.completionDates(in: week).isEmpty)
    }

    @Test func undo_ofLastOccurrence_reopensWithSameDue() async throws {
        let done = try await complete(try await repeating(count: 1))
        let undone = try await reopen(done, version: done.version)
        #expect(undone.isCompleted == false)
        #expect(undone.due == due)
        #expect(undone.recurrence?.count == 1)
        #expect(provider.completionDates(in: week).isEmpty)
    }

    /// Reopening after a later change keeps that change: only the state written by the completion is undone.
    @Test func reopen_afterLaterEdit_keepsCurrentDue() async throws {
        let done = try await complete(try await repeating(count: 3))
        var edit = TaskEdit()
        edit.title = .set("Vokabeln")
        let edited = try await provider.apply(edit, to: done.id, expectedVersion: done.version)
        let reopened = try await reopen(edited, version: nil)
        #expect(reopened.due == done.due)
        #expect(reopened.recurrence?.count == 2)
        #expect(provider.completionDates(in: week).count == 1)
    }

    /// The weekly review counts every completed occurrence once.
    @Test func completionDates_countEveryOccurrence() async throws {
        let first = try await complete(try await repeating(count: 2))
        let last = try await complete(first)
        #expect(last.isCompleted)
        #expect(provider.completionDates(in: week).count == 2)
    }
}
