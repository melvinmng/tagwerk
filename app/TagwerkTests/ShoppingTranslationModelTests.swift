import AIKit
import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// Holds the answer back until the test lets it go, so a request can be cancelled while it runs.
private final class GatedResponder: ResponseStreaming, @unchecked Sendable {
    private let answer: String
    private let gate = AsyncStream<Void>.makeStream()
    init(answer: String) { self.answer = answer }
    func release() {
        gate.continuation.yield()
        gate.continuation.finish()
    }
    func respond(model: String, instructions: String, input: [InputItem], tools: [ToolDefinition],
                 jsonSchema: (name: String, schema: Data)?) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for await _ in self.gate.stream { break }
                continuation.yield(.textDelta(self.answer))
                continuation.yield(.completed(usage: nil))
                continuation.finish()
            }
        }
    }
}

@MainActor
struct ShoppingTranslationModelTests {
    let container: ModelContainer
    let settings: AppSettings
    let store: InMemoryReminderStore
    let shopping: ShoppingModel
    let responder = FakePlanResponder()
    let now = testNow()

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        settings.shoppingListID = "shop"
        let now = self.now
        func item(_ id: String, _ title: String, notes: String? = nil) -> ReminderRecord {
            ReminderRecord(id: id, title: title, notes: notes, due: nil, ekPriority: 0, isCompleted: false, listID: "shop",
                           lastModified: nil, createdAt: now, completedAt: nil)
        }
        store = InMemoryReminderStore(lists: [ListInfo(id: "shop", title: "Einkauf", colorHex: nil, kind: .calDAV)],
                                      records: [item("a", "Äpfel", notes: "6 Stück"), item("b", "Karotten"), item("c", "Milch")], now: { now })
        let categories = ShoppingCategoryStore(context: container.mainContext, settings: settings, now: { now })
        categories.seedIfNeeded()
        shopping = ShoppingModel(store: store, settings: settings, categories: categories, now: { now })
    }

    /// A model for a list that was settled in German and is English now.
    private func model(_ responder: (any ResponseStreaming)? = nil, consent: Bool = true, settled: String? = "de-DE",
                       shoppingLanguage: String = "en-US") async -> ShoppingTranslationModel {
        settings.shoppingItemsLanguage = settled
        settings.shoppingLanguage = shoppingLanguage
        await shopping.reload()
        let translator = ShoppingTranslator(responder: responder ?? self.responder, model: { "gpt-test" }, hasConsent: { consent })
        return ShoppingTranslationModel(shopping: shopping, settings: settings, translator: translator)
    }

    /// The answer of ChatGPT for the open items as the model sends them: the order of the request follows the sections of the
    /// list, so the translations are given by name and put into that order here. A name without a translation comes back as it is.
    private func answer(_ translations: [String: String]) -> String {
        let plan = ShoppingTranslationPlan(openItems: shopping.openItems)
        let object: [String: Any] = ["items": plan.entries.map { ["i": $0.index, "text": translations[$0.name] ?? $0.name] }]
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private let english = ["Äpfel": "Apples", "Karotten": "Carrots", "Milch": "Milk"]

    // MARK: Offer

    @Test func refreshOffer_firstRun_adoptsWithoutCard() async {
        let model = await model(settled: nil)
        model.refreshOffer()
        #expect(model.offer == nil)
        #expect(settings.shoppingItemsLanguage == "en-US")
    }

    @Test func refreshOffer_afterSwitch_showsCardWithOpenCount() async {
        let model = await model()
        model.refreshOffer()
        #expect(model.offer == ShoppingTranslationModel.Offer(language: .english, openCount: 3, message: nil))
        #expect(settings.shoppingItemsLanguage == "de-DE", "showing the card writes nothing")
    }

    @Test func refreshOffer_switchedBack_hidesCardWithoutWriting() async {
        let model = await model()
        model.refreshOffer()
        settings.shoppingLanguage = "de-DE"
        model.refreshOffer()
        #expect(model.offer == nil && settings.shoppingItemsLanguage == "de-DE")
    }

    @Test func refreshOffer_emptyList_adopts() async {
        store.records.removeAll()
        let model = await model()
        model.refreshOffer()
        #expect(model.offer == nil && settings.shoppingItemsLanguage == "en-US")
    }

    @Test func refreshOffer_listNotLoaded_neverAdopts() {
        settings.shoppingItemsLanguage = "de-DE"
        settings.shoppingLanguage = "en-US"
        let translator = ShoppingTranslator(responder: responder, model: { "gpt-test" }, hasConsent: { true })
        let model = ShoppingTranslationModel(shopping: shopping, settings: settings, translator: translator)
        model.refreshOffer()
        #expect(model.offer == nil && settings.shoppingItemsLanguage == "de-DE", "a list that is not loaded is not an empty one")
    }

    @Test func refreshOffer_afterARestore_showsNoCard() async {
        // `shoppingItemsLanguage` is not part of a backup: it is empty after a restore, and the list adopts its language.
        let model = await model(settled: nil)
        model.refreshOffer()
        #expect(model.offer == nil)
    }

    @Test func keepAsIs_settlesTheLanguage_andHidesTheCard() async {
        let model = await model()
        model.refreshOffer()
        model.keepAsIs()
        #expect(model.offer == nil && settings.shoppingItemsLanguage == "en-US")
        model.refreshOffer()
        #expect(model.offer == nil)
    }

    @Test func keepAsIs_cardReturnsOnlyAfterTheNextSwitch() async {
        let model = await model()
        model.keepAsIs()
        settings.shoppingLanguage = "de-DE"
        model.refreshOffer()
        #expect(model.offer == ShoppingTranslationModel.Offer(language: .german, openCount: 3, message: nil))
    }

    // MARK: Request

    @Test func translate_showsPreview() async throws {
        let model = await model()
        responder.enqueue(answer(english))
        await model.translate()
        let preview = try #require(model.preview)
        #expect(Set(preview.changes.map(\.newName)) == ["Apples", "Carrots", "Milk"] && preview.leftOut == 0)
        #expect(!model.isTranslating)
        #expect(store.saveCount == 0, "nothing is written before \"Übernehmen\"")
    }

    @Test func translate_nothingToChange_settlesAndShowsNoPreview() async {
        let model = await model()
        model.refreshOffer()
        responder.enqueue(answer([:]))
        await model.translate()
        #expect(model.preview == nil && model.offer == nil && settings.shoppingItemsLanguage == "en-US")
        #expect(model.notice == "Alle Artikel sind schon auf Englisch.")
    }

    @Test func translate_failure_keepsCardWithMessage() async {
        let model = await model()
        model.refreshOffer()
        responder.enqueueFailure(.network)
        await model.translate()
        #expect(model.preview == nil && settings.shoppingItemsLanguage == "de-DE")
        #expect(model.offer?.message == ShoppingTranslator.Failure.network.message)
        // The message survives a refresh while the language stays the same, and goes with the next try.
        model.refreshOffer()
        #expect(model.offer?.message == ShoppingTranslator.Failure.network.message)
    }

    @Test func translate_withoutConsent_failsBeforeAnythingIsSent() async {
        let model = await model(consent: false)
        model.refreshOffer()
        await model.translate()
        #expect(responder.calls.isEmpty && model.preview == nil)
        #expect(model.offer?.message == ShoppingTranslator.Failure.consentMissing.message)
    }

    @Test func translate_cancelled_ignoresALateAnswer() async {
        await shopping.reload()
        let gated = GatedResponder(answer: answer(english))
        let model = await model(gated)
        model.refreshOffer()
        let running = Task { await model.translate() }
        for _ in 0..<20 { await Task.yield() }
        #expect(model.isTranslating)
        model.cancel()
        gated.release()
        await running.value
        #expect(model.preview == nil && !model.isTranslating && model.notice == nil)
        #expect(model.offer?.message == nil, "a cancelled request leaves no message")
    }

    @Test func translate_onlyBlockedChanges_showsPreviewWithoutSelectableRows() async throws {
        store.records["d"] = ReminderRecord(id: "d", title: "Milk", notes: nil, due: nil, ekPriority: 0, isCompleted: false, listID: "shop",
                                            lastModified: nil, createdAt: now, completedAt: nil)
        store.records["a"] = nil
        store.records["b"] = nil
        let model = await model()
        responder.enqueue(answer(["Milch": "Milk"]))
        await model.translate()
        let preview = try #require(model.preview)
        #expect(preview.changes.map(\.blocked) == [.alreadyOnList])
        #expect(ShoppingTranslationModel.selection(preview.changes, deselected: []).isEmpty)
    }

    // MARK: Preview

    @Test func selection_dropsDeselectedAndBlockedChanges() {
        let changes = [ShoppingTranslationPlan.Change(itemID: "a", oldName: "Äpfel", newName: "Apples"),
                       ShoppingTranslationPlan.Change(itemID: "b", oldName: "Karotten", newName: "Carrots"),
                       ShoppingTranslationPlan.Change(itemID: "c", oldName: "Milch", newName: "Milk", blocked: .alreadyOnList)]
        #expect(ShoppingTranslationModel.selection(changes, deselected: ["b"]).map(\.itemID) == ["a"])
        #expect(ShoppingTranslationModel.selection(changes, deselected: []).map(\.itemID) == ["a", "b"])
    }

    @Test func discard_keepsTheCard() async {
        let model = await model()
        model.refreshOffer()
        responder.enqueue(answer(english))
        await model.translate()
        model.discard()
        #expect(model.preview == nil && model.offer != nil && settings.shoppingItemsLanguage == "de-DE" && store.saveCount == 0)
    }

    @Test func apply_renamesSettlesAndOffersUndo() async throws {
        let model = await model()
        model.refreshOffer()
        responder.enqueue(answer(english))
        await model.translate()
        let selected = try #require(model.preview).changes
        let line = await model.apply(selected)
        #expect(line == nil)
        #expect(store.records["a"]?.title == "Apples" && store.records["c"]?.title == "Milk")
        #expect(store.records["a"]?.notes == "6 Stück")
        #expect(settings.shoppingItemsLanguage == "en-US" && model.offer == nil && model.preview == nil)
        #expect(Set(model.undo.map(\.newName)) == ["Apples", "Carrots", "Milk"])
    }

    @Test func apply_partial_returnsNoticeWithBothCounts() async throws {
        let model = await model()
        model.refreshOffer()
        responder.enqueue(answer(english))
        await model.translate()
        let selected = try #require(model.preview).changes
        // One item changes between the preview and "Übernehmen".
        try await shopping.update(id: "b", name: "Möhren", quantity: nil)
        let line = await model.apply(selected)
        #expect(line == "2 von 3 Artikeln übersetzt. 1 Artikel wurde inzwischen geändert und bleibt.")
        #expect(settings.shoppingItemsLanguage == "en-US", "the language is settled after a partial success too")
        #expect(model.undo.count == 2)
    }

    @Test func apply_nothingWritten_doesNotSettleTheLanguage() async throws {
        let model = await model()
        model.refreshOffer()
        responder.enqueue(answer(english))
        await model.translate()
        let selected = try #require(model.preview).changes
        // Everything that was previewed is gone by now; one other item keeps the list from being empty (an empty list adopts its language).
        store.records.removeAll()
        store.records["z"] = ReminderRecord(id: "z", title: "Brot", notes: nil, due: nil, ekPriority: 0, isCompleted: false, listID: "shop",
                                            lastModified: nil, createdAt: now, completedAt: nil)
        let line = await model.apply(selected)
        #expect(line != nil && model.undo.isEmpty && settings.shoppingItemsLanguage == "de-DE")
    }

    // MARK: Undo

    @Test func undoLast_restoresNamesAndShowsTheCardAgain() async throws {
        let model = await model()
        model.refreshOffer()
        responder.enqueue(answer(english))
        await model.translate()
        _ = await model.apply(try #require(model.preview).changes)
        await model.undoLast()
        #expect(store.records["a"]?.title == "Äpfel" && store.records["b"]?.title == "Karotten" && store.records["c"]?.title == "Milch")
        #expect(model.undo.isEmpty && settings.shoppingItemsLanguage == "de-DE")
        #expect(model.offer?.language == .english, "the card is back")
    }

    @Test func capsuleExpired_dropsTheUndoState() async throws {
        let model = await model()
        model.refreshOffer()
        responder.enqueue(answer(english))
        await model.translate()
        _ = await model.apply(try #require(model.preview).changes)
        model.capsuleExpired()
        #expect(model.undo.isEmpty)
        await model.undoLast()
        #expect(store.records["a"]?.title == "Apples", "after the capsule the rename stays")
    }

    @Test func reportLine_namesFailuresAndSkips() {
        var report = ShoppingModel.RenameReport(renamed: [], skipped: 0, failed: 0)
        #expect(ShoppingTranslationModel.reportLine(report, total: 3) == nil)
        report.skipped = 2
        #expect(ShoppingTranslationModel.reportLine(report, total: 3) == "0 von 3 Artikeln übersetzt. 2 Artikel wurden inzwischen geändert und bleiben.")
        report.failed = 1
        report.errorMessage = "Kein Zugriff."
        #expect(ShoppingTranslationModel.reportLine(report, total: 3)?.hasSuffix("Kein Zugriff.") == true)
    }
}
