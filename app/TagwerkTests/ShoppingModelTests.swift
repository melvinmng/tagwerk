import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct ShoppingModelTests {
    let container: ModelContainer
    let settings: AppSettings
    let store: InMemoryReminderStore
    let categories: ShoppingCategoryStore
    let model: ShoppingModel
    let now = testNow()

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        settings.shoppingListID = "shop"
        let now = self.now
        func day(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
        func item(_ id: String, _ title: String, list: String = "shop", notes: String? = nil, created: Date? = nil,
                  completed: Date? = nil) -> ReminderRecord {
            ReminderRecord(id: id, title: title, notes: notes, due: nil, ekPriority: 0, isCompleted: completed != nil,
                           listID: list, lastModified: nil, createdAt: created, completedAt: completed)
        }
        store = InMemoryReminderStore(
            lists: [ListInfo(id: "uni", title: "Uni", colorHex: nil, kind: .calDAV),
                    ListInfo(id: "shop", title: "Einkauf", colorHex: nil, kind: .calDAV)],
            records: [
                item("milk", "Milch", notes: "1", created: day(3)),
                item("bananas", "Bananen", created: day(2)),
                item("essay", "Seminararbeit", list: "uni"),
                item("eggs-new", "Eier", completed: day(1)),
                item("eggs-old", "Eier", completed: day(3)),
                item("rice", "Reis", completed: day(8)),
                item("foreign-done", "Abgabe", list: "uni", completed: day(1)),
            ],
            now: { now })
        categories = ShoppingCategoryStore(context: container.mainContext, settings: settings, now: { now })
        categories.seedIfNeeded()
        model = ShoppingModel(store: store, settings: settings, categories: categories, now: { now })
    }

    private func category(_ builtin: ShoppingBuiltinCategory) throws -> UUID {
        try #require(categories.categories().first { $0.builtinKey == builtin.rawValue }).id
    }

    @Test func reload_readsOpenAndRecentlyCompletedOfShoppingListOnly() async {
        await model.reload()
        #expect(model.state == .ready)
        #expect(model.listTitle == "Einkauf")
        #expect(model.openItems.map(\.name) == ["Bananen", "Milch"])
        #expect(model.openItems.last?.quantity == "1")
        #expect(model.completedItems.map(\.id) == ["eggs-new", "eggs-old"])
        #expect(model.sections.count == 2)
    }

    @Test func add_newItem_createsPlainReminderInShoppingList() async throws {
        let report = await model.add([ParsedItem(name: "Kaffee", quantity: "2 Packungen")])
        let record = try #require(store.records.values.first { $0.title == "Kaffee" })
        #expect(report.added == ["Kaffee"])
        #expect(record.listID == "shop" && record.notes == "2 Packungen" && record.due == nil && record.ekPriority == 0
                && record.recurrence == nil)
        #expect(model.openItems.contains { $0.name == "Kaffee" && $0.quantity == "2 Packungen" })
    }

    @Test func categoryNamesByItemID_nameTheSectionOfEachOpenItem_andSkipOther() async {
        store.records["screws"] = ReminderRecord(id: "screws", title: "Schrauben", notes: nil, due: nil, ekPriority: 0,
                                                 isCompleted: false, listID: "shop", lastModified: nil)
        await model.reload()
        let names = model.categoryNamesByItemID()
        #expect(names["milk"] == "Kühlregal")
        #expect(names["screws"] == nil)   // "Sonstiges" has no category name
        for item in model.openItems { #expect(names[item.id] == model.categoryName(of: item)) }
    }

    @Test func add_afterAFreshLoad_skipsTheLeadingReload() async {
        await model.reload()
        let calls = store.openReminderCalls
        let report = await model.add([ParsedItem(name: "Kaffee", quantity: nil)], reloadFirst: false)
        #expect(report.added == ["Kaffee"])
        #expect(store.openReminderCalls == calls + 1)   // only the reload after writing
        let defaultCalls = store.openReminderCalls
        _ = await model.add([ParsedItem(name: "Tee", quantity: nil)])
        #expect(store.openReminderCalls == defaultCalls + 2)
    }

    @Test func checkOffSeveral_savesAllAndReloadsOnce() async {
        await model.reload()
        let calls = store.openReminderCalls
        let report = await model.checkOff(ids: ["milk", "essay", "bananas", "nope"])
        #expect(report.checkedOff == ["Milch", "Bananen"])
        #expect(report.notFound == ["essay", "nope"])
        #expect(store.records["milk"]?.isCompleted == true && store.records["bananas"]?.isCompleted == true)
        #expect(store.records["essay"]?.isCompleted == false)
        #expect(store.openReminderCalls == calls + 1)
        #expect(model.openItems.isEmpty)
    }

    @Test func add_openDuplicate_createsNothing_replacesQuantity() async {
        let report = await model.add([ParsedItem(name: "milch", quantity: "2")])
        #expect(store.createCount == 0)
        #expect(store.records["milk"]?.notes == "2")
        #expect(report == ShoppingModel.AddReport(alreadyOnList: ["Milch"]))
        _ = await model.add([ParsedItem(name: "Milch", quantity: nil)])
        #expect(store.records["milk"]?.notes == "2")
        #expect(store.createCount == 0)
    }

    @Test func add_openItemWithLongNotes_keepsNotes() async {
        store.records["milk"]?.notes = "1\nnur Bio"
        let report = await model.add([ParsedItem(name: "Milch", quantity: "3")])
        #expect(store.records["milk"]?.notes == "1\nnur Bio")
        #expect(report.alreadyOnList == ["Milch"])
    }

    @Test func add_recentlyCompleted_reopensNewest() async {
        let report = await model.add([ParsedItem(name: "eier", quantity: "10")])
        #expect(store.records["eggs-new"]?.isCompleted == false)
        #expect(store.records["eggs-new"]?.notes == "10")
        #expect(store.records["eggs-old"]?.isCompleted == true)
        #expect(store.createCount == 0)
        #expect(report.reopened == ["Eier"])
        #expect(model.openItems.contains { $0.id == "eggs-new" })
    }

    @Test func add_completedOlderThanSevenDays_createsNew() async {
        let report = await model.add([ParsedItem(name: "Reis", quantity: nil)])
        #expect(report.added == ["Reis"])
        #expect(store.records["rice"]?.isCompleted == true)
        #expect(store.createCount == 1)
    }

    @Test func add_duplicateWithinOneInput_createsOne() async {
        let report = await model.add([ParsedItem(name: "Hefe", quantity: nil), ParsedItem(name: "hefe", quantity: nil),
                                      ParsedItem(name: "Hefe", quantity: "2")])
        #expect(store.records.values.filter { ShoppingName.key($0.title) == "hefe" }.count == 1)
        #expect(report.added == ["Hefe"] && report.alreadyOnList.count == 2)
        #expect(store.records.values.first { $0.title == "Hefe" }?.notes == "2")
    }

    @Test func add_listMissing_writesNothing() async {
        store.listInfos.removeAll { $0.id == "shop" }
        await model.reload()
        let report = await model.add([ParsedItem(name: "Kaffee", quantity: nil)])
        #expect(model.state == .listMissing && store.createCount == 0 && report.failed == ["Kaffee"])
        #expect(report.errorMessage != nil)
        #expect(model.openItems.isEmpty && model.completedItems.isEmpty)
    }

    @Test func noList_stateNoList() async {
        settings.shoppingListID = nil
        await model.reload()
        #expect(model.state == .noList && model.openItems.isEmpty)
    }

    @Test func checkOff_completesWithoutDeleting_reopenRestores() async throws {
        await model.reload()
        try await model.checkOff(id: "milk")
        #expect(store.records["milk"]?.isCompleted == true)
        #expect(model.completedItems.first?.id == "milk")
        #expect(!model.openItems.contains { $0.id == "milk" })
        try await model.reopen(id: "milk")
        #expect(store.records["milk"]?.isCompleted == false)
        #expect(model.openItems.contains { $0.id == "milk" })
    }

    @Test func checkOff_reminderOutsideShoppingList_throwsNotFound() async {
        await model.reload()
        await #expect(throws: TaskWriteError.notFound) { try await model.checkOff(id: "essay") }
        #expect(store.records["essay"]?.isCompleted == false)
        await #expect(throws: TaskWriteError.notFound) { try await model.delete(id: "essay") }
        #expect(store.records["essay"] != nil)
    }

    @Test func update_changesNameAndQuantity_butNotLongNotes() async throws {
        await model.reload()
        try await model.update(id: "milk", name: " Hafermilch ", quantity: "2 Packungen")
        #expect(store.records["milk"]?.title == "Hafermilch" && store.records["milk"]?.notes == "2 Packungen")
        try await model.update(id: "milk", name: "Hafermilch", quantity: " ")
        #expect(store.records["milk"]?.notes == nil)
        store.records["bananas"]?.notes = "6\nreif"
        try await model.update(id: "bananas", name: "Bio-Bananen", quantity: "3")
        #expect(store.records["bananas"]?.title == "Bio-Bananen" && store.records["bananas"]?.notes == "6\nreif")
    }

    @Test func delete_removesTheReminder() async throws {
        await model.reload()
        try await model.delete(id: "milk")
        #expect(store.records["milk"] == nil)
        #expect(!model.openItems.contains { $0.id == "milk" })
    }

    @Test func removeCompleted_deletesOnlyLastSevenDays() async {
        await model.reload()
        #expect(await model.removeCompleted() == 2)
        #expect(store.records.values.contains { $0.title == "Reis" })
        #expect(store.records["foreign-done"] != nil)
        #expect(model.completedItems.isEmpty)
    }

    @Test func setCategory_appliesToEveryItemOfThatName() async throws {
        await model.reload()
        let household = try category(.household)
        model.setCategory(household, forItemID: "milk")
        #expect(model.sections.first { $0.categoryID == household }?.items.map(\.name) == ["Milch"])
        #expect(model.categoryID(of: try #require(model.openItems.first { $0.id == "milk" })) == household)
        try await model.delete(id: "milk")
        _ = await model.add([ParsedItem(name: "MILCH", quantity: nil)])
        #expect(model.sections.first { $0.categoryID == household }?.items.map(\.name) == ["MILCH"])
    }

    @Test func refreshSections_followsDeletedCategory() async throws {
        await model.reload()
        categories.delete(try category(.chilled))
        model.refreshSections()
        #expect(model.sections.last?.categoryID == nil)
        #expect(model.sections.last?.items.map(\.name) == ["Milch"])
    }

    @Test func noAccess_stateAccessDenied() async {
        store.accessState = .denied
        await model.reload()
        #expect(model.state == .accessDenied && model.openItems.isEmpty)
        let report = await model.add([ParsedItem(name: "Kaffee", quantity: nil)])
        #expect(report.failed == ["Kaffee"] && store.createCount == 0)
    }

    @Test func environment_setShoppingList_loadsTheModel() async throws {
        let environment = try AppEnvironment(modelContainer: ModelContainerFactory.make(inMemory: true),
                                             notificationCenter: FakeNotificationCenter(), health: FakeHealthStore(),
                                             reminderStore: store)
        #expect(environment.shopping.state == .noList)
        await environment.setShoppingList("shop")
        #expect(environment.shopping.state == .ready)
        #expect(environment.shopping.openItems.count == 2)
    }
}
