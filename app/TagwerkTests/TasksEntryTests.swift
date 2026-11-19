import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The shopping row at the head of "Aufgaben" (phase 5 design §5.3).
@MainActor
struct TasksEntryTests {
    let container: ModelContainer
    let settings: AppSettings
    let store: InMemoryReminderStore
    let model: ShoppingModel

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        settings.setupCompleted = true
        store = InMemoryReminderStore(lists: [Self.list("shop", "Einkauf"), Self.list("uni", "Uni")])
        model = ShoppingModel(store: store, settings: settings,
                              categories: ShoppingCategoryStore(context: container.mainContext, settings: settings))
    }

    private static func list(_ id: String, _ title: String) -> ListInfo {
        ListInfo(id: id, title: title, colorHex: nil, kind: .calDAV)
    }

    private func state(access: AccessState = .fullAccess, lists: [ListInfo]? = nil) -> ShoppingEntryState {
        ShoppingEntryState.make(access: access, setupCompleted: settings.setupCompleted, lists: lists ?? store.listInfos,
                                settings: settings, model: model)
    }

    @Test func entry_hiddenWithoutFullAccess() {
        #expect(state(access: .denied) == .hidden)
        #expect(state(access: .writeOnly) == .hidden)
    }

    @Test func entry_suggestsSingleMatchingList() {
        #expect(state() == .suggestion(listID: "shop", title: "Einkauf"))
    }

    @Test func entry_noSuggestionWhenDismissedOrSetupOpenOrTwoCandidates() {
        #expect(state(lists: store.listInfos + [Self.list("g", "Groceries")]) == .setup(previousListMissing: false))
        settings.setupCompleted = false
        #expect(state() == .setup(previousListMissing: false))
        settings.setupCompleted = true
        settings.shoppingSuggestionDismissed = true
        #expect(state() == .setup(previousListMissing: false))
    }

    @Test func dismissSuggestion_keepsSetupRow() {
        settings.shoppingSuggestionDismissed = true
        #expect(state() != .hidden)
    }

    @Test func entry_chosenListGone_showsSetupWithHint() {
        settings.shoppingListID = "gone"
        #expect(state() == .setup(previousListMissing: true))
    }

    @Test func entry_listWithItems_andEmpty() async {
        settings.shoppingListID = "shop"
        await model.reload()
        #expect(state() == .list(subtitle: "Nichts offen", openCount: 0))
        _ = await model.add([ParsedItem(name: "Hafermilch", quantity: nil), ParsedItem(name: "Bananen", quantity: nil)])
        // Without categories everything is "Sonstiges", ordered by creation.
        #expect(state() == .list(subtitle: "Hafermilch, Bananen", openCount: 2))
        #expect(ShoppingEntryState.subtitle(openNames: ["Hafermilch", "Bananen", "Eier", "A", "B", "C", "D"])
                == "Hafermilch, Bananen, Eier und 4 weitere")
        #expect(ShoppingEntryState.subtitle(openNames: ["Hafermilch", "Bananen", "Eier", "A"]) == "Hafermilch, Bananen, Eier und 1 weiterer")
        #expect(ShoppingEntryState.subtitle(openNames: ["Hafermilch", "Bananen"]) == "Hafermilch, Bananen")
        #expect(ShoppingEntryState.subtitle(openNames: []) == "Nichts offen")
    }

    @Test func reminderListSummary_countsWithoutShoppingList() {
        let lists = [Self.list("a", "A"), Self.list("b", "B"), Self.list("shop", "Einkauf")]
        #expect(ReminderListSummary.text(selected: nil, lists: lists, shopping: "shop") == "2 von 2")
        #expect(ReminderListSummary.text(selected: ["a", "shop"], lists: lists, shopping: "shop") == "1 von 2")
        #expect(ReminderListSummary.text(selected: nil, lists: lists, shopping: nil) == "3 von 3")
        #expect(ReminderListSummary.text(selected: nil, lists: [], shopping: nil) == "–")
    }
}
