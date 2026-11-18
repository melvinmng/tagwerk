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
        #expect(created.editableFields == [.title, .notes, .due, .priority, .estimate])
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
