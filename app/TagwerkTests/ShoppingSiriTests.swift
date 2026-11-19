import AppIntents
import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The names Siri can speak for the shopping shortcut, their resolution and the intent behind them.
@MainActor
struct ShoppingSiriTests {
    let store: InMemoryReminderStore
    let environment: AppEnvironment
    let services: IntentServices

    private static func day(_ days: Double) -> Date { Date.now.addingTimeInterval(-days * 86_400) }

    private static func item(_ id: String, _ title: String, list: String = "shop", created: Date? = nil,
                             completed: Date? = nil) -> ReminderRecord {
        ReminderRecord(id: id, title: title, notes: nil, due: nil, ekPriority: 0, isCompleted: completed != nil,
                       listID: list, lastModified: nil, createdAt: created, completedAt: completed)
    }

    init(records: [ReminderRecord] = []) throws {
        store = InMemoryReminderStore(lists: [ListInfo(id: "shop", title: "Einkauf", colorHex: nil, kind: .calDAV),
                                              ListInfo(id: "uni", title: "Uni", colorHex: nil, kind: .calDAV)],
                                      records: records)
        environment = try AppEnvironment(modelContainer: ModelContainerFactory.make(inMemory: true),
                                         notificationCenter: FakeNotificationCenter(), health: FakeHealthStore(),
                                         reminderStore: store)
        environment.settings.setupCompleted = true
        environment.settings.shoppingListID = "shop"
        services = IntentServices(environment: environment)
    }

    private static let history = [
        item("a", "Hafermilch", created: day(2)),
        item("b", "Eier", created: day(20), completed: day(10)),
        item("c", "Brot", completed: day(40)),
        item("d", "Quark", completed: day(400)),
        item("e", "Seminararbeit", list: "uni", created: day(1)),
    ]

    // MARK: Suggested names

    @Test func names_ownHistoryFirst_openAndCompleted_thenCommonTerms() async throws {
        let test = try ShoppingSiriTests(records: Self.history)
        let names = await test.services.shoppingArticleNames(preferEnglish: false)
        #expect(Array(names.prefix(3)) == ["Hafermilch", "Eier", "Brot"])
        #expect(names.contains("Milch") && names.contains("Käse"))
        // Older than the history window, and items of other lists, are not own names (Quark is still a common term).
        #expect(!names.contains("Seminararbeit"))
        #expect(names.firstIndex(of: "Quark") ?? 0 > 2)
    }

    @Test func names_dedupeOwnAgainstCommonTerms_ignoringCaseAndDiacritics() async throws {
        let test = try ShoppingSiriTests(records: [Self.item("a", "KASE", created: Self.day(1)), Self.item("b", "milch", created: Self.day(2))])
        let names = await test.services.shoppingArticleNames(preferEnglish: false)
        #expect(names.prefix(2) == ["KASE", "milch"])
        #expect(!names.contains("Käse") && !names.contains("Milch"))
    }

    @Test func names_areCappedAt150() async throws {
        let many = (0..<200).map { Self.item("r\($0)", "Artikel \($0)", created: Self.day(Double($0) / 10)) }
        let test = try ShoppingSiriTests(records: many)
        let names = await test.services.shoppingArticleNames(preferEnglish: false)
        #expect(names.count == 150)
        #expect(names.first == "Artikel 0")
    }

    @Test func names_withoutListOrAccess_stillOfferCommonTerms() async throws {
        let test = try ShoppingSiriTests(records: Self.history)
        test.environment.settings.shoppingListID = nil
        var names = await test.services.shoppingArticleNames(preferEnglish: false)
        #expect(names == ShoppingSuggestions.articles(history: [], commonTerms: ShoppingSuggestions.commonTerms(preferEnglish: false)))
        #expect(names.first == "Milch")
        test.environment.settings.shoppingListID = "shop"
        test.store.accessState = .denied
        names = await test.services.shoppingArticleNames(preferEnglish: true)
        #expect(names.first == "Milk")
    }

    // MARK: Resolution

    @Test func matching_findsSuggestionsWithoutDiacritics() async throws {
        let test = try ShoppingSiriTests(records: Self.history)
        #expect(await test.services.shoppingArticleNames(matching: "kase", preferEnglish: false).first == "Käse")
        #expect(await test.services.shoppingArticleNames(matching: "milch", preferEnglish: false).first == "Milch")
    }

    @Test func matching_unknownName_resolvesToItself_blankToNothing() async throws {
        let test = try ShoppingSiriTests()
        #expect(await test.services.shoppingArticleNames(matching: " Rhabarbersaft ", preferEnglish: false) == ["Rhabarbersaft"])
        #expect(await test.services.shoppingArticleNames(matching: "  ", preferEnglish: false).isEmpty)
        #expect(await test.services.shoppingArticleNames(matching: " , ", preferEnglish: false).isEmpty)
    }

    @Test func entity_idIsTheName_andIsRebuiltFromIt() {
        let entity = ShoppingArticleEntity(name: "Hafermilch")
        #expect(entity.id == "Hafermilch" && entity.name == "Hafermilch")
        #expect(ShoppingArticleEntity.entities(for: ["Eier", " ", "Brot "]).map(\.name) == ["Eier", "Brot"])
    }

    // MARK: Adding

    @Test func addArticle_usesTheExistingPath_createsReopensAndDedupes() async throws {
        let test = try ShoppingSiriTests(records: [Self.item("eggs", "Eier", completed: Self.day(1))])
        #expect(String(localized: await test.services.addToShopping(article: ShoppingArticleEntity(name: "Hafermilch")))
            == "1 Artikel hinzugefügt: Hafermilch.")
        #expect(String(localized: await test.services.addToShopping(article: ShoppingArticleEntity(name: "hafermilch")))
            == "Hafermilch steht schon auf der Liste.")
        #expect(String(localized: await test.services.addToShopping(article: ShoppingArticleEntity(name: "Eier")))
            == "1 Artikel hinzugefügt: Eier.")
        #expect(test.store.createCount == 1)
        #expect(test.store.records["eggs"]?.isCompleted == false)
    }

    @Test func addArticle_typedTextWithQuantity_isSplitLikeTheTextShortcut() async throws {
        let test = try ShoppingSiriTests()
        #expect(String(localized: await test.services.addToShopping(article: ShoppingArticleEntity(name: "2 Zwiebeln")))
            == "1 Artikel hinzugefügt: Zwiebeln.")
        #expect(test.store.records.values.first { $0.title == "Zwiebeln" }?.notes == "2")
    }

    @Test func intent_perform_addsThroughTheService() async throws {
        let test = try ShoppingSiriTests()
        var intent = AddShoppingArticleIntent()
        intent.services = test.services
        intent.article = ShoppingArticleEntity(name: "Hafermilch")
        _ = try await intent.perform()
        #expect(test.store.records.values.contains { $0.title == "Hafermilch" && $0.listID == "shop" })
    }

    @Test func providerChangedHook_firesWhenNamesChange_notWhenTheyStay() async throws {
        let test = try ShoppingSiriTests(records: [Self.item("a", "Brot", created: Self.day(1))])
        var calls = 0
        test.environment.shopping.onNamesChanged = { calls += 1 }
        await test.environment.shopping.reload()
        #expect(calls == 1)
        await test.environment.shopping.reload()
        #expect(calls == 1)
        _ = await test.environment.shopping.add([ParsedItem(name: "Käse", quantity: nil)])
        #expect(calls == 2)
    }
}
