import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// Renaming shopping items in Apple Reminders after a translation (L8).
@MainActor
struct ShoppingRenameTests {
    let container: ModelContainer
    let settings: AppSettings
    let store: InMemoryReminderStore
    let categories: ShoppingCategoryStore
    let model: ShoppingModel
    let now = testNow()
    private let dictionary = ShoppingDictionary(entries: [ShoppingBuiltinCategory.chilled.rawValue: ["milch", "joghurt"],
                                                          ShoppingBuiltinCategory.produce.rawValue: ["apfel", "apples"]])

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        settings.shoppingListID = "shop"
        let now = self.now
        func item(_ id: String, _ title: String, list: String = "shop", notes: String? = nil, completed: Bool = false) -> ReminderRecord {
            ReminderRecord(id: id, title: title, notes: notes, due: DueDate(year: 2026, month: 12, day: 24, hour: 10), ekPriority: 1, isCompleted: completed,
                           listID: list, lastModified: nil, createdAt: now, completedAt: completed ? now : nil)
        }
        store = InMemoryReminderStore(
            lists: [ListInfo(id: "uni", title: "Uni", colorHex: nil, kind: .calDAV), ListInfo(id: "shop", title: "Einkauf", colorHex: nil, kind: .calDAV)],
            records: [item("apples", "Äpfel", notes: "6 Stück\nvom Markt, nicht die roten"), item("carrots", "Karotten", notes: "1 kg"),
                      item("milk", "Milch"), item("done", "Brot", completed: true), item("foreign", "Hausarbeit", list: "uni")],
            now: { now })
        categories = ShoppingCategoryStore(context: container.mainContext, settings: settings, now: { now })
        categories.seedIfNeeded()
        model = ShoppingModel(store: store, settings: settings, categories: categories, dictionary: dictionary, now: { now })
    }

    private func change(_ id: String, _ old: String, _ new: String, blocked: ShoppingTranslationPlan.Blocked? = nil) -> ShoppingTranslationPlan.Change {
        ShoppingTranslationPlan.Change(itemID: id, oldName: old, newName: new, quantity: nil, blocked: blocked)
    }

    private func category(_ builtin: ShoppingBuiltinCategory) throws -> UUID {
        try #require(categories.categories().first { $0.builtinKey == builtin.rawValue }).id
    }

    // MARK: Writing

    @Test func rename_writesOnlyTheTitle_andKeepsQuantityAndNotes() async throws {
        let before = try #require(store.records["apples"])
        let report = await model.rename([change("apples", "Äpfel", "Apples")])
        #expect(report.renamed == [ShoppingModel.Renamed(id: "apples", oldName: "Äpfel", newName: "Apples")] && report.skipped == 0 && report.failed == 0)
        var after = try #require(store.records["apples"])
        #expect(after.title == "Apples")
        #expect(after.notes == "6 Stück\nvom Markt, nicht die roten", "the whole note stays, also the lines after the quantity")
        after.title = before.title
        after.lastModified = before.lastModified
        #expect(after == before, "nothing but the title was written")
        #expect(model.openItems.first { $0.id == "apples" }?.quantity == "6 Stück")
    }

    @Test func rename_ignoresBlockedChanges() async {
        let report = await model.rename([change("apples", "Äpfel", "Apples", blocked: .alreadyOnList)])
        #expect(report == ShoppingModel.RenameReport())
        #expect(store.records["apples"]?.title == "Äpfel" && store.saveCount == 0)
    }

    @Test func rename_itemCheckedOffSincePreview_isSkipped() async throws {
        try await model.checkOff(id: "carrots")
        let report = await model.rename([change("carrots", "Karotten", "Carrots")])
        #expect(report.renamed.isEmpty && report.skipped == 1)
        #expect(store.records["carrots"]?.title == "Karotten")
    }

    @Test func rename_itemRenamedSincePreview_isSkipped() async throws {
        try await model.update(id: "carrots", name: "Möhren", quantity: "1 kg")
        let report = await model.rename([change("carrots", "Karotten", "Carrots")])
        #expect(report.renamed.isEmpty && report.skipped == 1 && store.records["carrots"]?.title == "Möhren")
    }

    @Test func rename_itemDeletedSincePreview_isSkipped() async throws {
        try await model.delete(id: "carrots")
        let report = await model.rename([change("carrots", "Karotten", "Carrots")])
        #expect(report.renamed.isEmpty && report.skipped == 1 && report.failed == 0)
    }

    @Test func rename_newNameOnListByNow_isSkipped() async {
        _ = await model.add([ParsedItem(name: "Carrots", quantity: nil)])
        let report = await model.rename([change("carrots", "Karotten", "Carrots")])
        #expect(report.renamed.isEmpty && report.skipped == 1)
        #expect(store.records["carrots"]?.title == "Karotten", "nothing is merged or deleted")
        #expect(store.records.values.filter { $0.title == "Carrots" }.count == 1)
    }

    @Test func rename_twoRemindersOfTheSameName_renameTogether() async {
        _ = await model.add([ParsedItem(name: "Karotten", quantity: nil)])
        store.records["carrots-2"] = ReminderRecord(id: "carrots-2", title: "karotten", notes: nil, due: nil, ekPriority: 0, isCompleted: false,
                                                    listID: "shop", lastModified: nil, createdAt: now, completedAt: nil)
        let report = await model.rename([change("carrots", "Karotten", "Carrots"), change("carrots-2", "karotten", "Carrots")])
        #expect(report.renamed.count == 2 && report.skipped == 0)
    }

    @Test func rename_reminderOfAnotherList_isNeverWritten() async {
        let report = await model.rename([change("foreign", "Hausarbeit", "Housework")])
        #expect(report.renamed.isEmpty && report.skipped == 1)
        #expect(store.records["foreign"]?.title == "Hausarbeit")
    }

    @Test func rename_writeError_countsFailedAndContinues() async {
        store.failingSaveIDs = ["apples"]
        let report = await model.rename([change("apples", "Äpfel", "Apples"), change("carrots", "Karotten", "Carrots")])
        #expect(report.failed == 1 && report.renamed.map(\.id) == ["carrots"])
        #expect(report.errorMessage != nil)
        #expect(store.records["apples"]?.title == "Äpfel" && store.records["carrots"]?.title == "Carrots")
    }

    @Test func rename_withoutAccess_reportsFailed() async {
        store.accessState = .denied
        let report = await model.rename([change("apples", "Äpfel", "Apples")])
        #expect(report.failed == 1 && report.errorMessage != nil && report.renamed.isEmpty)
    }

    @Test func rename_notifiesNamesChanged() async {
        await model.reload()
        var notified = 0
        model.onNamesChanged = { notified += 1 }
        _ = await model.rename([change("carrots", "Karotten", "Carrots")])
        #expect(notified == 1)
    }

    // MARK: Categories

    @Test func rename_keepsTheSection_whenTheDictionaryWouldMoveTheItem() async throws {
        // "Äpfel" is known as produce, "Apples" ("apples" is not a term of this dictionary's German side) would be filed elsewhere.
        let customDictionary = ShoppingDictionary(entries: [ShoppingBuiltinCategory.produce.rawValue: ["apfel"]])
        let model = ShoppingModel(store: store, settings: settings, categories: categories, dictionary: customDictionary, now: { now })
        await model.reload()
        let produce = try category(.produce)
        #expect(model.categoryID(of: try #require(model.openItems.first { $0.id == "apples" })) == produce)
        _ = await model.rename([change("apples", "Äpfel", "Apples")])
        #expect(model.categoryID(of: try #require(model.openItems.first { $0.id == "apples" })) == produce, "the item stays in its section")
        #expect(categories.assignments()[ShoppingName.key("Apples")]?.categoryID == produce)
    }

    @Test func rename_carriesAManualAssignmentAsManual() async throws {
        let household = try category(.household)
        categories.assign(nameKey: ShoppingName.key("Karotten"), to: household, manual: true)
        _ = await model.rename([change("carrots", "Karotten", "Carrots")])
        #expect(categories.assignments()[ShoppingName.key("Carrots")] == ShoppingAssignmentInfo(categoryID: household, isManual: true))
        #expect(categories.assignments()[ShoppingName.key("Karotten")]?.isManual == true, "the assignment of the old name stays")
    }

    @Test func rename_existingAssignmentOfTheNewNameWins() async throws {
        let household = try category(.household)
        let produce = try category(.produce)
        categories.assign(nameKey: ShoppingName.key("Apples"), to: household, manual: false)
        categories.assign(nameKey: ShoppingName.key("Äpfel"), to: produce, manual: true)
        _ = await model.rename([change("apples", "Äpfel", "Apples")])
        #expect(categories.assignments()[ShoppingName.key("Apples")] == ShoppingAssignmentInfo(categoryID: household, isManual: false))
    }

    @Test func rename_sameCategoryByDictionary_addsNoAssignment() async throws {
        // "Apples" and "Äpfel" are both produce in this dictionary.
        _ = await model.rename([change("apples", "Äpfel", "Apples")])
        #expect(categories.assignments()[ShoppingName.key("Apples")] == nil)
    }

    // MARK: Undo

    @Test func undoRename_restoresTheOldTitles() async {
        let report = await model.rename([change("apples", "Äpfel", "Apples"), change("carrots", "Karotten", "Carrots")])
        let restored = await model.undoRename(report.renamed)
        #expect(restored == 2 && store.records["apples"]?.title == "Äpfel" && store.records["carrots"]?.title == "Karotten")
        #expect(store.records["apples"]?.notes == "6 Stück\nvom Markt, nicht die roten")
    }

    @Test func undoRename_itemChangedAgain_isLeftAlone() async throws {
        let report = await model.rename([change("carrots", "Karotten", "Carrots")])
        try await model.update(id: "carrots", name: "Baby carrots", quantity: "1 kg")
        #expect(await model.undoRename(report.renamed) == 0)
        #expect(store.records["carrots"]?.title == "Baby carrots")
    }

    @Test func undoRename_checkedOffItem_isLeftAlone() async throws {
        let report = await model.rename([change("carrots", "Karotten", "Carrots")])
        try await model.checkOff(id: "carrots")
        #expect(await model.undoRename(report.renamed) == 0)
        #expect(store.records["carrots"]?.title == "Carrots")
    }
}
