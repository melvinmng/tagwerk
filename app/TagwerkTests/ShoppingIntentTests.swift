import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// "Auf die Einkaufsliste" and "Einkaufsliste zeigen" (phase 5 design §5.9).
@MainActor
struct ShoppingIntentTests {
    let store: InMemoryReminderStore
    let environment: AppEnvironment
    let services: IntentServices

    init() throws {
        store = InMemoryReminderStore(lists: [ListInfo(id: "shop", title: "Einkauf", colorHex: nil, kind: .calDAV),
                                              ListInfo(id: "uni", title: "Uni", colorHex: nil, kind: .calDAV)])
        environment = try AppEnvironment(modelContainer: ModelContainerFactory.make(inMemory: true),
                                         notificationCenter: FakeNotificationCenter(), health: FakeHealthStore(),
                                         reminderStore: store)
        environment.settings.setupCompleted = true
        services = IntentServices(environment: environment)
    }

    private func add(_ text: String) async -> String {
        String(localized: await services.addToShopping(text: text))
    }

    @Test func addToShopping_addsParsedItems_namesOnlyWhatWasSaid() async throws {
        environment.settings.shoppingListID = "shop"
        #expect(await add("Kaffee, Reis und 2 Zwiebeln") == "3 Artikel hinzugefügt: Kaffee, Reis, Zwiebeln.")
        #expect(store.records.values.first { $0.title == "Zwiebeln" }?.notes == "2")
        #expect(await add("Kaffee") == "Kaffee steht schon auf der Liste.")
        #expect(await add("kaffee, reis") == "Kaffee, Reis stehen schon auf der Liste.")
    }

    @Test func addToShopping_singleItem_usesSingular() async throws {
        environment.settings.shoppingListID = "shop"
        #expect(await add("Hefe") == "1 Artikel hinzugefügt: Hefe.")
    }

    @Test func addToShopping_mixedResult_namesEachGroup() async throws {
        environment.settings.shoppingListID = "shop"
        _ = await add("Kaffee")
        #expect(await add("Hefe und Kaffee") == "1 Artikel hinzugefügt: Hefe. Kaffee steht schon auf der Liste.")
    }

    @Test func addToShopping_reopenedCountsAsAdded() async throws {
        environment.settings.shoppingListID = "shop"
        _ = await add("Eier")
        let id = try #require(store.records.values.first { $0.title == "Eier" }?.id)
        try await environment.shopping.checkOff(id: id)
        #expect(await add("eier") == "1 Artikel hinzugefügt: Eier.")
        #expect(store.createCount == 1)
    }

    @Test func addToShopping_withoutList_asksToChooseOne() async throws {
        #expect(await add("Kaffee") == "Wähle zuerst in Tagwerk unter Einstellungen › Einkaufsliste eine Liste.")
        environment.settings.shoppingListID = "gone"
        #expect(await add("Kaffee") == "Wähle zuerst in Tagwerk unter Einstellungen › Einkaufsliste eine Liste.")
        #expect(store.createCount == 0)
    }

    @Test func addToShopping_withoutAccess_saysSo() async throws {
        environment.settings.shoppingListID = "shop"
        store.accessState = .denied
        #expect(await add("Kaffee") == "Tagwerk hat keinen Zugriff auf Erinnerungen.")
        #expect(store.createCount == 0)
    }

    @Test func addToShopping_emptyText_addsNothing() async throws {
        environment.settings.shoppingListID = "shop"
        #expect(await add(" , ") == "Ich habe keinen Artikel verstanden.")
        #expect(store.createCount == 0)
    }

    @Test func addToShopping_needsNoLoadedTaskList() async throws {
        environment.settings.shoppingListID = "shop"
        #expect(environment.taskList.items.isEmpty && !environment.taskList.allSourcesSettled)
        #expect(await add("Kaffee") == "1 Artikel hinzugefügt: Kaffee.")
        #expect(!environment.taskList.allSourcesSettled)
    }

    @Test func openShopping_withList_showsPage_withoutList_showsSettings() async throws {
        environment.openShopping()
        #expect(environment.tasksPath == [.shoppingSettings] && environment.requestedTab == 1)
        await environment.setShoppingList("shop")
        environment.tasksPath = [.notes]
        environment.openShopping()
        #expect(environment.tasksPath == [.shopping])
    }

    @Test func openShoppingIntent_requestsTheShoppingRoute() async throws {
        services.openShopping()
        #expect(environment.router.takeRequest(setupCompleted: true)?.route == .shopping)
    }
}
