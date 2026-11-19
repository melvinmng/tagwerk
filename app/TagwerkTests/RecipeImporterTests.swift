import AIKit
import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// Records the addresses it was asked for and answers with a fixed page, or fails.
private final class FakeFetcher: PageFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var requested: [URL] = []
    var page: Result<String, URLError> = .success("")
    var urls: [URL] { lock.withLock { requested } }

    func fetch(_ url: URL) async throws -> Data {
        lock.withLock { requested.append(url) }
        return Data(try page.get().utf8)
    }
}

/// A responder that never answers within the test's timeout.
private final class StallingResponder: ResponseStreaming, @unchecked Sendable {
    func respond(model: String, instructions: String, input: [InputItem], tools: [ToolDefinition],
                 jsonSchema: (name: String, schema: Data)?) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                try? await Task.sleep(for: .seconds(5))
                continuation.yield(.textDelta(#"{"items":[]}"#))
                continuation.yield(.completed(usage: nil))
                continuation.finish()
            }
        }
    }
}

@MainActor
struct RecipeImporterTests {
    let responder = FakePlanResponder()
    private let fetcher = FakeFetcher()
    final class Counter { var models = 0 }
    let modelCalls = Counter()
    let categories = ["Obst & Gemüse", "Kühlregal", "Vorrat & Konserven"]

    private func importer(_ responder: (any ResponseStreaming)? = nil, consent: Bool = true,
                          timeout: Duration = .seconds(30)) -> RecipeImporter {
        let calls = modelCalls
        return RecipeImporter(responder: responder ?? self.responder, model: { calls.models += 1; return "gpt-test" },
                              hasConsent: { consent }, fetcher: fetcher, timeout: timeout)
    }

    private func answer(_ items: [(String, String?, String)]) -> String {
        let object: [String: Any] = ["items": items.map { ["name": $0.0, "quantity": $0.1 as Any? ?? NSNull(), "category": $0.2] }]
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private func validate(_ items: [(String, String?, String)], open: Set<String> = []) throws -> [RecipeImporter.Candidate] {
        try RecipeImporter.validate(Data(answer(items).utf8), categoryNames: categories + ["Sonstiges"], openItemKeys: open)
    }

    private func sentText(_ index: Int = 0) -> String {
        responder.calls[index].input.map { item -> String in
            switch item {
            case .user(let text): text
            case .userImage(let text, _): text
            default: ""
            }
        }.joined(separator: "\n")
    }

    // MARK: Consent

    @Test func noConsent_sendsNothing() async {
        await #expect(throws: RecipeImporter.Failure.consentMissing) {
            try await importer(consent: false).read(.text("500 g Mehl"), categoryNames: categories, openItemKeys: [])
        }
        await #expect(throws: RecipeImporter.Failure.consentMissing) {
            try await importer(consent: false).read(.photo(jpeg: Data([1, 2, 3])), categoryNames: categories, openItemKeys: [])
        }
        #expect(responder.calls.isEmpty && modelCalls.models == 0)
    }

    @Test func noConsent_doesNotFetchLink() async {
        await #expect(throws: RecipeImporter.Failure.consentMissing) {
            try await importer(consent: false).read(.link(URL(string: "https://example.com/rezept")!), categoryNames: categories, openItemKeys: [])
        }
        #expect(fetcher.urls.isEmpty && responder.calls.isEmpty)
    }

    // MARK: Requests

    @Test func text_sendsTheRecipeAndTheCategoryNames_butNothingElse() async throws {
        responder.enqueue(answer([("Mehl", "500 g", "Vorrat & Konserven")]))
        let result = try await importer().read(.text("  500 g Mehl, 2 Eier  "), categoryNames: categories, openItemKeys: ["milch"])
        #expect(result.map(\.name) == ["Mehl"])
        #expect(responder.calls.count == 1 && responder.calls[0].schema == "recipe_ingredients")
        let text = sentText()
        #expect(text.contains("500 g Mehl, 2 Eier") && text.contains("Kühlregal") && text.contains("Sonstiges"))
        // The open items of the list are not part of the request.
        #expect(!text.contains("milch"))
    }

    @Test func text_isCutAtTheLimit_andEmptyTextSendsNothing() async throws {
        responder.enqueue(answer([("Mehl", nil, "Sonstiges")]))
        _ = try await importer().read(.text(String(repeating: "Zutat ", count: 5000)), categoryNames: categories, openItemKeys: [])
        #expect(sentText().count < RecipeText.maximumLength + 400)
        await #expect(throws: RecipeImporter.Failure.nothingFound) {
            try await importer().read(.text("  \n "), categoryNames: categories, openItemKeys: [])
        }
        #expect(responder.calls.count == 1)
    }

    @Test func photo_sendsTheImageWithTheCategoryNames() async throws {
        responder.enqueue(answer([("Butter", nil, "Kühlregal")]))
        _ = try await importer().read(.photo(jpeg: Data([9, 8, 7])), categoryNames: categories, openItemKeys: [])
        guard case .userImage(let text, let jpeg) = responder.calls[0].input[0] else { Issue.record("no image sent"); return }
        #expect(jpeg == Data([9, 8, 7]) && text.contains("Kühlregal") && text.contains("photo"))
    }

    // MARK: Links

    @Test func link_onlyHttp() async {
        for address in ["file:///etc/passwd", "ftp://example.com/x", "javascript:alert(1)", "data:text/html,x", "tagwerk://task/1", "https://"] {
            await #expect(throws: RecipeImporter.Failure.linkUnreadable, "\(address)") {
                try await importer().read(.link(URL(string: address)!), categoryNames: categories, openItemKeys: [])
            }
        }
        #expect(fetcher.urls.isEmpty && responder.calls.isEmpty)
        #expect(RecipeImporter.isWebLink(URL(string: "http://example.com")!) && RecipeImporter.isWebLink(URL(string: "HTTPS://example.com/a")!))
    }

    @Test func link_sendsExtractedIngredientsNotUrl() async throws {
        fetcher.page = .success("""
        <html><script type="application/ld+json">{"@type":"Recipe","recipeIngredient":["200 g Linsen","1 Zwiebel"]}</script>
        <body><p>Viel Text drumherum, der nicht gesendet wird.</p></body></html>
        """)
        responder.enqueue(answer([("Linsen", "200 g", "Vorrat & Konserven")]))
        let url = URL(string: "https://geheim.example.com/rezepte/linsensuppe?utm=abc")!
        _ = try await importer().read(.link(url), categoryNames: categories, openItemKeys: [])
        #expect(fetcher.urls == [url])
        let text = sentText()
        #expect(text.contains("200 g Linsen\n1 Zwiebel"))
        #expect(!text.contains("Viel Text") && !text.contains("geheim.example.com") && !text.contains("utm") && !text.contains("https://"))
    }

    @Test func link_withoutStructuredData_sendsThePageText() async throws {
        fetcher.page = .success("<html><nav>Menü</nav><main><h1>Pfannkuchen</h1><li>250 g Mehl</li></main><script>x()</script></html>")
        responder.enqueue(answer([("Mehl", "250 g", "Vorrat & Konserven")]))
        _ = try await importer().read(.link(URL(string: "https://example.com/p")!), categoryNames: categories, openItemKeys: [])
        let text = sentText()
        #expect(text.contains("Pfannkuchen\n250 g Mehl") && !text.contains("Menü") && !text.contains("x()"))
    }

    @Test func link_failuresMapToLinkUnreadable() async {
        fetcher.page = .failure(URLError(.notConnectedToInternet))
        await #expect(throws: RecipeImporter.Failure.linkUnreadable) {
            try await importer().read(.link(URL(string: "https://example.com/p")!), categoryNames: categories, openItemKeys: [])
        }
        fetcher.page = .success("<html><script>only()</script></html>")
        await #expect(throws: RecipeImporter.Failure.linkUnreadable) {
            try await importer().read(.link(URL(string: "https://example.com/p")!), categoryNames: categories, openItemKeys: [])
        }
        #expect(responder.calls.isEmpty)
    }

    // MARK: Failures

    @Test func timeout_mapsToFailed() async {
        await #expect(throws: RecipeImporter.Failure.failed) {
            try await importer(StallingResponder(), timeout: .milliseconds(50)).read(.text("Mehl"), categoryNames: categories, openItemKeys: [])
        }
    }

    @Test func chatGPTErrors_mapToFailures() async {
        for (error, expected) in [(ChatGPTError.network, RecipeImporter.Failure.network), (.notSignedIn, .signedOut),
                                  (.usageLimit, .usageLimit), (.incomplete, .failed)] {
            responder.enqueueFailure(error)
            await #expect(throws: expected) {
                try await importer().read(.text("Mehl"), categoryNames: categories, openItemKeys: [])
            }
        }
        responder.enqueue("kein JSON")
        await #expect(throws: RecipeImporter.Failure.failed) {
            try await importer().read(.text("Mehl"), categoryNames: categories, openItemKeys: [])
        }
        responder.enqueue(#"{"items": []}"#)
        await #expect(throws: RecipeImporter.Failure.nothingFound) {
            try await importer().read(.text("Mehl"), categoryNames: categories, openItemKeys: [])
        }
    }

    // MARK: Validation

    @Test func validate_unknownCategoryBecomesOther() throws {
        let result = try validate([("Milch", "1 L", "kühlregal"), ("Schrauben", nil, "Baumarkt"), ("Brot", nil, "  Sonstiges ")])
        #expect(result.map(\.category) == ["Kühlregal", "Sonstiges", "Sonstiges"])
        // No category is created: the names are always from the list.
        #expect(Set(result.map(\.category)).isSubset(of: Set(categories + ["Sonstiges"])))
    }

    @Test func validate_dropsEmptyAndMergesDuplicates() throws {
        let result = try validate([("  ", "1", "Kühlregal"), ("Zwiebel", nil, "Obst & Gemüse"), ("ZWIEBEL", "2", "Kühlregal"),
                                   ("Zwiebel", "3", "Kühlregal"), ("Eier", " ", "Kühlregal")])
        #expect(result.map(\.name) == ["Zwiebel", "Eier"])
        // The first entry decides the category; a later quantity fills the gap, the first quantity stays.
        #expect(result[0].category == "Obst & Gemüse" && result[0].quantity == "2")
        #expect(result[1].quantity == nil)
    }

    @Test func validate_marksItemsAlreadyOnList() throws {
        let result = try validate([("Milch", nil, "Kühlregal"), ("Eier", nil, "Kühlregal")], open: [ShoppingName.key("milch")])
        #expect(result.map(\.alreadyOnList) == [true, false])
    }

    @Test func validate_capsAt40() throws {
        let many = (1...55).map { ("Zutat \($0)", Optional("1"), "Sonstiges") }
        let result = try validate(many)
        #expect(result.count == 40 && result.first?.name == "Zutat 1" && result.last?.name == "Zutat 40")
    }

    @Test func validate_trimsNamesAndQuantities() throws {
        let result = try validate([("  Tomaten  ", "  2 Dosen ", "Vorrat & Konserven"),
                                   (String(repeating: "x", count: 200), String(repeating: "9", count: 100), "Sonstiges")])
        #expect(result[0].name == "Tomaten" && result[0].quantity == "2 Dosen")
        #expect(result[1].name.count == ShoppingInputParser.maxNameLength && result[1].quantity?.count == RecipeImporter.maxQuantityLength)
    }

    @Test func validate_garbageIsAFailure() {
        #expect(throws: RecipeImporter.Failure.failed) { try RecipeImporter.validate(Data("{}".utf8), categoryNames: ["Sonstiges"], openItemKeys: []) }
        #expect(throws: RecipeImporter.Failure.nothingFound) { try validate([("", nil, "Sonstiges")]) }
    }

    // MARK: Applying

    @Test func apply_addsItemsAndAutoAssignsCategories() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let settings = try AppSettings.current(in: container.mainContext)
        settings.shoppingListID = "shop"
        let now = testNow()
        let store = InMemoryReminderStore(lists: [ListInfo(id: "shop", title: "Einkauf", colorHex: nil, kind: .calDAV)],
                                          records: [ReminderRecord(id: "milk", title: "Milch", notes: nil, due: nil, ekPriority: 0, isCompleted: false,
                                                                   listID: "shop", lastModified: nil, createdAt: now, completedAt: nil)],
                                          now: { now })
        let categoryStore = ShoppingCategoryStore(context: container.mainContext, settings: settings, now: { now })
        categoryStore.seedIfNeeded()
        let model = ShoppingModel(store: store, settings: settings, categories: categoryStore, now: { now })
        let fridge = try #require(categoryStore.categories().first { $0.builtinKey == ShoppingBuiltinCategory.chilled.rawValue })
        let household = try #require(categoryStore.categories().first { $0.builtinKey == ShoppingBuiltinCategory.household.rawValue })
        // The user put "Kerzen" into a category by hand earlier; the recipe must not override it.
        categoryStore.assign(nameKey: ShoppingName.key("Kerzen"), to: household.id, manual: true)

        let selected = [RecipeImporter.Candidate(name: "Joghurt", quantity: "2 Becher", category: fridge.name, alreadyOnList: false),
                        RecipeImporter.Candidate(name: "Kerzen", quantity: nil, category: fridge.name, alreadyOnList: false),
                        RecipeImporter.Candidate(name: "Zimt", quantity: "1 TL", category: "Sonstiges", alreadyOnList: false)]
        let report = await RecipeImporter.apply(selected, model: model, categories: categoryStore)
        #expect(Set(report.added) == ["Joghurt", "Kerzen", "Zimt"] && report.failed.isEmpty)
        #expect(store.records.values.first { $0.title == "Joghurt" }?.notes == "2 Becher")
        let assignments = categoryStore.assignments()
        #expect(assignments[ShoppingName.key("Joghurt")] == ShoppingAssignmentInfo(categoryID: fridge.id, isManual: false))
        #expect(assignments[ShoppingName.key("Zimt")] == ShoppingAssignmentInfo(categoryID: nil, isManual: false))
        #expect(assignments[ShoppingName.key("Kerzen")] == ShoppingAssignmentInfo(categoryID: household.id, isManual: true))
        // A later choice by hand takes precedence over the automatic one.
        model.setCategory(household.id, forItemID: try #require(model.openItems.first { $0.name == "Joghurt" }).id)
        #expect(categoryStore.assignments()[ShoppingName.key("Joghurt")]?.isManual == true)
        #expect(model.sections.first { $0.categoryID == household.id }?.items.map(\.name).contains("Joghurt") == true)
    }
}

@MainActor
struct RecipeImporterLinkTextTests {
    @Test func url_addsHttpsOnlyWhenThereIsNoScheme() {
        #expect(RecipeImporter.url(from: " example.com/rezept ")?.absoluteString == "https://example.com/rezept")
        #expect(RecipeImporter.url(from: "http://example.com/a")?.absoluteString == "http://example.com/a")
        #expect(RecipeImporter.url(from: "file:///etc/passwd")?.scheme == "file")
        #expect(RecipeImporter.url(from: "") == nil && RecipeImporter.url(from: "zwei Wörter") == nil)
    }
}

@MainActor
struct RecipeResultTests {
    private let milk = RecipeImporter.Candidate(name: "Milch", quantity: "1 L", category: "Kühlregal", alreadyOnList: true)
    private let flour = RecipeImporter.Candidate(name: "Mehl", quantity: nil, category: "Vorrat", alreadyOnList: false)

    @Test func selection_dropsDeselectedItems() {
        #expect(RecipeResultView.selection([milk, flour], deselected: [milk.id]).map(\.name) == ["Mehl"])
        #expect(RecipeResultView.selection([milk, flour], deselected: []).count == 2)
    }

    @Test func resultLine_countsAddedAndReopened_orNamesTheError() {
        #expect(RecipeResultView.resultLine(ShoppingModel.AddReport(added: ["a", "b"], reopened: ["c"])) == "3 Artikel aus dem Rezept hinzugefügt.")
        var failed = ShoppingModel.AddReport(failed: ["a"])
        failed.errorMessage = "Kein Zugriff."
        #expect(RecipeResultView.resultLine(failed) == "Kein Zugriff.")
    }
}
