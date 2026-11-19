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

    @Test func completedTasks_useSelectedListsWithoutShoppingList() async {
        store.listInfos.append(ListInfo(id: "shop", title: "Einkauf", colorHex: nil, kind: .local))
        let day = Date(timeIntervalSince1970: 50_000)
        store.records["c"]?.completedAt = day
        store.records["d"] = ReminderRecord(id: "d", title: "Milch", notes: nil, due: nil, ekPriority: 0, isCompleted: true,
                                            listID: "shop", lastModified: day, completedAt: day)
        store.records["e"] = ReminderRecord(id: "e", title: "Abgabe", notes: nil, due: nil, ekPriority: 0, isCompleted: true,
                                            listID: "studium", lastModified: day, completedAt: day)
        let sut = RemindersTaskProvider(store: store, selectedListIDs: { nil }, excludedListID: { "shop" })
        let interval = DateInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 100_000))
        let completed = await sut.completedTasks(in: interval)
        #expect(Set(completed.map(\.item.title)) == ["Erledigt", "Abgabe"])
        #expect(completed.allSatisfy { $0.item.isCompleted && $0.completedAt == day })
        #expect(completed.first { $0.item.title == "Abgabe" }?.item.container.name == "Studium")

        let selected = RemindersTaskProvider(store: store, selectedListIDs: { ["studium"] }, excludedListID: { "shop" })
        #expect(await selected.completedTasks(in: interval).map(\.item.title) == ["Abgabe"])
    }

    @Test func completedTasks_areEmptyWithoutFullAccess() async {
        store.records["c"]?.completedAt = Date(timeIntervalSince1970: 50_000)
        store.accessState = .denied
        let interval = DateInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 100_000))
        #expect(await provider().completedTasks(in: interval).isEmpty)
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
        #expect(inDefault.container.id == store.defaultList)
    }

    // MARK: Shopping list exclusion

    private func shoppingProvider(selected: Set<String>? = nil) -> RemindersTaskProvider {
        store.listInfos.append(ListInfo(id: "einkauf", title: "Einkauf", colorHex: nil, kind: .calDAV))
        store.records["milk"] = ReminderRecord(id: "milk", title: "Milch", notes: nil, due: nil, ekPriority: 0,
                                               isCompleted: false, listID: "einkauf", lastModified: nil)
        return RemindersTaskProvider(store: store, selectedListIDs: { selected }, excludedListID: { "einkauf" })
    }

    @Test func openTasks_excludesShoppingList() async throws {
        let all = try await shoppingProvider().openTasks()
        #expect(Set(all.map(\.title)) == ["Kapitel 2 gliedern", "Einkaufen"])
        let selected = try await shoppingProvider(selected: ["privat", "einkauf"]).openTasks()
        #expect(selected.map(\.title) == ["Einkaufen"])
    }

    @Test func containers_omitShoppingList() async throws {
        #expect(try await shoppingProvider().containers().map(\.id) == ["studium", "privat"])
    }

    @Test func create_defaultListIsShopping_usesFirstOtherList() async throws {
        let sut = shoppingProvider()
        store.defaultList = "einkauf"
        let created = try await sut.create(TaskDraft(title: "Standard"))
        #expect(created.container.id == "privat")
    }

    @Test func create_withoutExcludedList_behavesAsBefore() async throws {
        store.defaultList = "privat"
        let created = try await provider().create(TaskDraft(title: "Standard"))
        #expect(created.container.id == "privat")
    }

    @Test func containers_listAllReminderLists() async throws {
        #expect(try await provider().containers().map(\.id) == ["studium", "privat"])
    }

    @Test func delete_matchingVersion_removesReminder() async throws {
        let sut = provider()
        let item = try #require(try await sut.task(id: TaskID(source: .reminders, rawValue: "a")))
        try await sut.delete(item.id, expectedVersion: item.version)
        #expect(store.records["a"] == nil)
    }

    @Test func delete_staleVersion_throwsConflictAndKeepsReminder() async throws {
        let sut = provider()
        let item = try #require(try await sut.task(id: TaskID(source: .reminders, rawValue: "a")))
        store.modifyExternally("a") { $0.title = "Extern" }
        await #expect(throws: TaskWriteError.self) { try await sut.delete(item.id, expectedVersion: item.version) }
        #expect(store.records["a"] != nil)
    }

    @Test func delete_missing_throwsNotFound() async {
        await #expect(throws: TaskWriteError.notFound) {
            try await provider().delete(TaskID(source: .reminders, rawValue: "gone"), expectedVersion: nil)
        }
    }

    @Test func estimate_storedLocallyNotInEventKit() async throws {
        let estimates = MemoryEstimateStore()
        let sut = RemindersTaskProvider(store: store, estimates: estimates, selectedListIDs: { nil })
        let item = try #require(try await sut.task(id: TaskID(source: .reminders, rawValue: "a")))
        #expect(item.editableFields.contains(.estimate))
        var edit = TaskEdit()
        edit.estimateMinutes = .set(90)
        let saved = try await sut.apply(edit, to: item.id, expectedVersion: item.version)
        #expect(saved.estimateMinutes == 90)
        #expect(estimates.minutes(for: "a") == 90)
        #expect(store.saveCount == 0)
    }
}

@MainActor
struct RemindersTaskProviderRecurrenceTests {
    let store = FakeReminderStore()
    let due = DueDate(year: 2026, month: 11, day: 19)
    var weekly: Recurrence { Recurrence(rule: .weekly(interval: 1, weekdays: [5]), start: PlanDay(due), end: nil, count: nil) }
    var everySecondDay: Recurrence { Recurrence(rule: .daily(interval: 2), start: PlanDay(due), end: nil, count: 5) }
    let itemID = TaskID(source: .reminders, rawValue: "s")

    init() {
        store.listInfos = [ListInfo(id: "privat", title: "Privat", colorHex: nil, kind: .local)]
        store.records = [
            "s": ReminderRecord(id: "s", title: "Serie", notes: nil, due: due, ekPriority: 0, isCompleted: false,
                                listID: "privat", lastModified: Date(timeIntervalSince1970: 1), recurrence: weekly),
            "plain": ReminderRecord(id: "plain", title: "Ohne Datum", notes: nil, due: nil, ekPriority: 0, isCompleted: false,
                                    listID: "privat", lastModified: Date(timeIntervalSince1970: 1)),
        ]
    }

    private var provider: RemindersTaskProvider { RemindersTaskProvider(store: store, selectedListIDs: { nil }) }

    private func edit(_ change: (inout TaskEdit) -> Void) -> TaskEdit {
        var edit = TaskEdit()
        change(&edit)
        return edit
    }

    @Test func apply_titleOnly_passesUnchangedRecurrence() async throws {
        _ = try await provider.apply(edit { $0.title = .set("Neu") }, to: itemID, expectedVersion: nil)
        #expect(store.recurrenceChanges == [.unchanged])
        #expect(store.records["s"]?.recurrence == weekly)
    }

    @Test func apply_recurrence_replacesRule() async throws {
        let saved = try await provider.apply(edit { $0.recurrence = .set(everySecondDay) }, to: itemID, expectedVersion: nil)
        #expect(store.recurrenceChanges == [.set(everySecondDay)])
        #expect(saved.recurrence == everySecondDay)
    }

    @Test func apply_removingRecurrence_setsNil() async throws {
        let saved = try await provider.apply(edit { $0.recurrence = .set(nil) }, to: itemID, expectedVersion: nil)
        #expect(store.recurrenceChanges == [.set(nil)])
        #expect(saved.recurrence == nil)
    }

    @Test func apply_recurrenceWithoutDue_fails() async {
        let plain = TaskID(source: .reminders, rawValue: "plain")
        await #expect(throws: TaskWriteError.self) {
            try await provider.apply(edit { $0.recurrence = .set(everySecondDay) }, to: plain, expectedVersion: nil)
        }
        await #expect(throws: TaskWriteError.self) {
            try await provider.apply(edit {
                $0.recurrence = .set(everySecondDay)
                $0.due = .set(nil)
            }, to: itemID, expectedVersion: nil)
        }
        #expect(store.saveCount == 0)
    }

    @Test func apply_invalidRecurrence_fails() async {
        let invalid = Recurrence(rule: .daily(interval: 0), start: PlanDay(due), end: nil, count: nil)
        await #expect(throws: TaskWriteError.self) {
            try await provider.apply(edit { $0.recurrence = .set(invalid) }, to: itemID, expectedVersion: nil)
        }
        #expect(store.saveCount == 0)
    }

    @Test func apply_clearingDue_clearsRecurrence() async throws {
        let saved = try await provider.apply(edit { $0.due = .set(nil) }, to: itemID, expectedVersion: nil)
        #expect(store.recurrenceChanges == [.set(nil)])
        #expect(saved.recurrence == nil)
    }

    /// Plan §6 rule 1: a rule Tagwerk cannot express survives a due-date change untouched.
    @Test func apply_unsupportedRule_dueChangeOnly_passesUnchanged() async throws {
        store.records["s"]?.recurrence = Recurrence(rule: .unsupported, start: PlanDay(due), end: nil, count: nil)
        _ = try await provider.apply(edit { $0.due = .set(DueDate(year: 2026, month: 11, day: 26)) }, to: itemID, expectedVersion: nil)
        #expect(store.recurrenceChanges == [.unchanged])
        #expect(store.records["s"]?.recurrence?.rule == .unsupported)
    }

    /// `.unsupported` is never written: setting it leaves the reminder's rules alone.
    @Test func apply_setUnsupported_leavesRulesUntouched() async throws {
        let unsupported = Recurrence(rule: .unsupported, start: PlanDay(due), end: nil, count: nil)
        _ = try await provider.apply(edit {
            $0.recurrence = .set(unsupported)
            $0.title = .set("Neu")
        }, to: itemID, expectedVersion: nil)
        #expect(store.recurrenceChanges == [.unchanged])
        #expect(store.records["s"]?.recurrence == weekly)
    }

    @Test func create_withRecurrence() async throws {
        let created = try await provider.create(TaskDraft(title: "Neu", due: due, recurrence: weekly))
        #expect(store.createdRecurrences == [weekly])
        #expect(created.recurrence == weekly)
    }

    @Test func create_recurrenceWithoutDue_fails() async {
        await #expect(throws: TaskWriteError.self) {
            try await provider.create(TaskDraft(title: "Neu", recurrence: weekly))
        }
        #expect(store.createdRecurrences.isEmpty)
    }
}

@MainActor
final class MemoryEstimateStore: EstimateStore {
    private var values: [String: Int] = [:]
    func minutes(for reminderID: String) -> Int? { values[reminderID] }
    func setMinutes(_ minutes: Int?, for reminderID: String) { values[reminderID] = minutes }
}
