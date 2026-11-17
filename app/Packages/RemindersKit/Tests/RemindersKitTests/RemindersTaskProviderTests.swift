import Foundation
import Testing
import TagwerkCore
@testable import RemindersKit

@MainActor
struct RemindersTaskProviderTests {
    let store = FakeReminderStore()

    init() {
        store.listInfos = [
            ListInfo(id: "studium", title: "Studium", colorHex: nil, kind: .calDAV),
            ListInfo(id: "privat", title: "Privat", colorHex: nil, kind: .local),
        ]
        store.records = [
            "a": ReminderRecord(id: "a", title: "Kapitel 2 gliedern", notes: "Notiz", due: nil, ekPriority: 2,
                                isCompleted: false, listID: "studium", lastModified: Date(timeIntervalSince1970: 1)),
            "b": ReminderRecord(id: "b", title: "Einkaufen", notes: nil, due: nil, ekPriority: 0,
                                isCompleted: false, listID: "privat", lastModified: Date(timeIntervalSince1970: 1)),
            "c": ReminderRecord(id: "c", title: "Erledigt", notes: nil, due: nil, ekPriority: 0,
                                isCompleted: true, listID: "privat", lastModified: Date(timeIntervalSince1970: 1)),
        ]
    }

    private func provider(selected: Set<String>? = nil) -> RemindersTaskProvider {
        RemindersTaskProvider(store: store, selectedListIDs: { selected })
    }

    private func titleEdit(_ title: String) -> TaskEdit {
        var edit = TaskEdit()
        edit.title = .set(title)
        return edit
    }

    @Test func openTasks_allLists_excludesCompleted() async throws {
        let titles = try await provider().openTasks().map(\.title)
        #expect(Set(titles) == ["Kapitel 2 gliedern", "Einkaufen"])
    }

    @Test func openTasks_respectsSelectedLists() async throws {
        let items = try await provider(selected: ["studium"]).openTasks()
        #expect(items.map(\.title) == ["Kapitel 2 gliedern"])
        #expect(items.first?.container.name == "Studium")
    }

    @Test func apply_matchingVersion_saves() async throws {
        let sut = provider()
        let item = try #require(try await sut.task(id: TaskID(source: .reminders, rawValue: "a")))
        let saved = try await sut.apply(titleEdit("Neu"), to: item.id, expectedVersion: item.version)
        #expect(saved.title == "Neu")
        #expect(store.records["a"]?.title == "Neu")
        #expect(saved.version != item.version)
    }

    @Test func apply_staleVersion_throwsConflictWithCurrent() async throws {
        let sut = provider()
        let item = try #require(try await sut.task(id: TaskID(source: .reminders, rawValue: "a")))
        store.modifyExternally("a") { $0.title = "Extern geändert" }

        await #expect(throws: TaskWriteError.self) {
            try await sut.apply(titleEdit("Neu"), to: item.id, expectedVersion: item.version)
        }
        do {
            _ = try await sut.apply(titleEdit("Neu"), to: item.id, expectedVersion: item.version)
        } catch TaskWriteError.conflict(let current) {
            #expect(current.title == "Extern geändert")
        }
        #expect(store.saveCount == 0)
        #expect(store.records["a"]?.title == "Extern geändert")
    }

    @Test func apply_nilVersion_forcesSaveOfOwnFieldsOnly() async throws {
        let sut = provider()
        let item = try #require(try await sut.task(id: TaskID(source: .reminders, rawValue: "a")))
        store.modifyExternally("a") { $0.notes = "Externe Notiz" }

        let saved = try await sut.apply(titleEdit("Neu"), to: item.id, expectedVersion: nil)

        #expect(saved.title == "Neu")
        #expect(saved.notes == "Externe Notiz")
        #expect(store.records["a"]?.ekPriority == 2)
    }

    @Test func apply_missingReminder_throwsNotFound() async {
        await #expect(throws: TaskWriteError.notFound) {
            try await provider().apply(titleEdit("x"), to: TaskID(source: .reminders, rawValue: "gone"), expectedVersion: nil)
        }
    }

    @Test func apply_withoutAccess_throwsAccessDenied() async {
        store.accessState = .writeOnly
        await #expect(throws: TaskWriteError.accessDenied) {
            try await provider().apply(titleEdit("x"), to: TaskID(source: .reminders, rawValue: "a"), expectedVersion: nil)
        }
    }

    @Test func openTasks_withoutAccess_throwsAccessDenied() async {
        store.accessState = .denied
        await #expect(throws: TaskWriteError.accessDenied) {
            try await provider().openTasks()
        }
    }

    @Test func create_usesListOrDefault() async throws {
        let sut = provider()
        let inList = try await sut.create(TaskDraft(title: "In Liste", priority: .p1, containerID: "studium"))
        let inDefault = try await sut.create(TaskDraft(title: "Standard"))
        #expect(inList.container.id == "studium")
        #expect(store.records[inList.id.rawValue]?.ekPriority == 1)
        #expect(inDefault.container.id == store.defaultListID)
    }

    @Test func containers_listAllReminderLists() async throws {
        #expect(try await provider().containers().map(\.id) == ["studium", "privat"])
    }
}
