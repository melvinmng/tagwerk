import Foundation
import Testing
import TagwerkCore
@testable import RemindersKit

struct ShoppingListFilterTests {
    let lists = [
        ListInfo(id: "s", title: "Einkauf", colorHex: nil, kind: .calDAV),
        ListInfo(id: "z", title: "Zuhause", colorHex: nil, kind: .calDAV),
        ListInfo(id: "u", title: "Uni", colorHex: nil, kind: .calDAV),
    ]

    private func list(_ id: String, _ title: String, writable: Bool = true) -> ListInfo {
        ListInfo(id: id, title: title, colorHex: nil, kind: .calDAV, isWritable: writable)
    }

    @Test func taskListIDs_noShopping_isUnchanged() {
        #expect(ShoppingListFilter.taskListIDs(selected: nil, all: ["a", "s"], shopping: nil) == nil)
        #expect(ShoppingListFilter.taskListIDs(selected: ["a"], all: ["a", "s"], shopping: nil) == ["a"])
    }

    @Test func taskListIDs_allLists_dropsShopping() {
        #expect(ShoppingListFilter.taskListIDs(selected: nil, all: ["a", "b", "s"], shopping: "s") == ["a", "b"])
    }

    @Test func taskListIDs_selection_dropsShopping() {
        #expect(ShoppingListFilter.taskListIDs(selected: ["a", "s"], all: ["a", "b", "s"], shopping: "s") == ["a"])
    }

    @Test func taskListIDs_onlyShoppingSelected_isEmptySetNotNil() {
        #expect(ShoppingListFilter.taskListIDs(selected: ["s"], all: ["a", "s"], shopping: "s") == Set<String>())
        #expect(ShoppingListFilter.taskListIDs(selected: nil, all: ["s"], shopping: "s") == Set<String>())
    }

    @Test func taskListIDs_unknownShoppingID_keepsSelection() {
        #expect(ShoppingListFilter.taskListIDs(selected: nil, all: ["a", "b"], shopping: "gone") == nil)
        #expect(ShoppingListFilter.taskListIDs(selected: ["a"], all: ["a", "b"], shopping: "gone") == ["a"])
    }

    @Test func listForNewReminder_defaultIsShopping_picksFirstOtherSelectedByTitle() throws {
        #expect(try ShoppingListFilter.listForNewReminder(requested: nil, defaultListID: "s", shopping: "s",
                                                          selected: nil, lists: lists) == "u")
        #expect(try ShoppingListFilter.listForNewReminder(requested: nil, defaultListID: "s", shopping: "s",
                                                          selected: ["z", "s"], lists: lists) == "z")
    }

    @Test func listForNewReminder_noOtherList_throws() {
        #expect(throws: TaskWriteError.self) {
            try ShoppingListFilter.listForNewReminder(requested: nil, defaultListID: "s", shopping: "s",
                                                      selected: ["s"], lists: lists)
        }
    }

    @Test func listForNewReminder_requestedShoppingList_isTreatedAsNoRequest() throws {
        #expect(try ShoppingListFilter.listForNewReminder(requested: "s", defaultListID: "u", shopping: "s",
                                                          selected: nil, lists: lists) == nil)
        #expect(try ShoppingListFilter.listForNewReminder(requested: "s", defaultListID: "s", shopping: "s",
                                                          selected: nil, lists: lists) == "u")
    }

    @Test func listForNewReminder_otherDefaultOrRequest_passesThrough() throws {
        #expect(try ShoppingListFilter.listForNewReminder(requested: nil, defaultListID: "u", shopping: "s",
                                                          selected: nil, lists: lists) == nil)
        #expect(try ShoppingListFilter.listForNewReminder(requested: "z", defaultListID: "s", shopping: "s",
                                                          selected: nil, lists: lists) == "z")
        #expect(try ShoppingListFilter.listForNewReminder(requested: nil, defaultListID: nil, shopping: "s",
                                                          selected: nil, lists: lists) == nil)
        #expect(try ShoppingListFilter.listForNewReminder(requested: nil, defaultListID: "s", shopping: nil,
                                                          selected: nil, lists: lists) == nil)
    }

    @Test func suggestedList_exactlyOneWritableMatch() {
        #expect(ShoppingListFilter.suggestedList(in: [list("a", "Einkauf"), list("b", "Uni")])?.id == "a")
        #expect(ShoppingListFilter.suggestedList(in: [list("a", "  Groceries "), list("b", "Uni")])?.id == "a")
        #expect(ShoppingListFilter.suggestedList(in: [list("a", "Einkäufe")])?.id == "a")
        #expect(ShoppingListFilter.suggestedList(in: [list("a", "Lebensmittel Woche")])?.id == "a")
        #expect(ShoppingListFilter.suggestedList(in: [list("a", "Einkauf"), list("b", "Shopping")]) == nil)
        #expect(ShoppingListFilter.suggestedList(in: [list("a", "Einkauf", writable: false)]) == nil)
        #expect(ShoppingListFilter.suggestedList(in: [list("a", "Wocheneinkauf")]) == nil)
        #expect(ShoppingListFilter.suggestedList(in: []) == nil)
    }
}
