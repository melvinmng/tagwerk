import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The reminder list chosen as shopping list is not a source of tasks (phase 5, rule R1).
@MainActor
struct ShoppingExclusionTests {
    let store: InMemoryReminderStore
    let environment: AppEnvironment

    init() throws {
        store = InMemoryReminderStore(
            lists: [ListInfo(id: "uni", title: "Uni", colorHex: nil, kind: .calDAV),
                    ListInfo(id: "shop", title: "Einkauf", colorHex: nil, kind: .calDAV)],
            records: [
                ReminderRecord(id: "task-1", title: "Seminararbeit", notes: nil, due: nil, ekPriority: 0, isCompleted: false,
                               listID: "uni", lastModified: nil),
                ReminderRecord(id: "milk", title: "Milch", notes: nil, due: nil, ekPriority: 0, isCompleted: false,
                               listID: "shop", lastModified: nil),
            ])
        environment = try AppEnvironment(modelContainer: ModelContainerFactory.make(inMemory: true),
                                         notificationCenter: FakeNotificationCenter(), health: FakeHealthStore(),
                                         reminderStore: store)
        environment.settings.setupCompleted = true
    }

    @Test func settings_newFieldsHaveSpecDefaults() throws {
        let settings = AppSettings()
        #expect(settings.shoppingListID == nil && !settings.shoppingSuggestionDismissed
                && !settings.shoppingCategoriesSeeded && !settings.shoppingSortConsent)
    }

    @Test func setShoppingList_removesItsRemindersFromTaskList() async throws {
        await environment.taskList.reload()
        #expect(environment.taskList.items.map(\.title).sorted() == ["Milch", "Seminararbeit"])
        await environment.setShoppingList("shop")
        #expect(environment.settings.shoppingListID == "shop")
        #expect(environment.taskList.items.map(\.title) == ["Seminararbeit"])
        await environment.setShoppingList(nil)
        #expect(environment.taskList.items.count == 2)
    }

    @Test func taskReminderListIDs_excludeShoppingList_forWeekReview() async throws {
        #expect(environment.taskReminderListIDs() == nil)
        await environment.setShoppingList("shop")
        #expect(environment.taskReminderListIDs() == ["uni"])
        environment.settings.selectedReminderListIDs = ["shop"]
        #expect(environment.taskReminderListIDs() == Set<String>())
    }

    @Test func newTaskContainers_omitShoppingList() async throws {
        await environment.setShoppingList("shop")
        let provider = try #require(environment.taskList.provider(for: .reminders))
        #expect(try await provider.containers().map(\.id) == ["uni"])
    }
}
