import AIKit
import Foundation
import SwiftData
import Testing
import TagwerkCore
import UIKit
@testable import Tagwerk

/// A responder that answers only when the test lets it.
private final class GatedResponder: ResponseStreaming, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation?
    private var requested = false
    var wasRequested: Bool { lock.withLock { requested } }

    func respond(model: String, instructions: String, input: [InputItem], tools: [ToolDefinition],
                 jsonSchema: (name: String, schema: Data)?) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            lock.withLock {
                self.continuation = continuation
                requested = true
            }
        }
    }

    func answer(_ json: String) {
        let continuation = lock.withLock { self.continuation }
        continuation?.yield(.textDelta(json))
        continuation?.yield(.completed(usage: nil))
        continuation?.finish()
    }
}

@MainActor
struct RecipeTranslationModelTests {
    let container: ModelContainer
    let directory: URL
    let attachments: NoteAttachmentStore
    let store: NoteStore
    let responder = FakePlanResponder()
    let recipesFolder: NoteFolderRecord

    private let english = """
    # Red Lentil Curry

    Servings: 4

    ## Ingredients
    - 250 g red lentils
    - 2 tbsp curry paste

    ## Instructions
    1. Chop the onions.

    Tip: tastes better the next day.
    """

    private let translations = [
        "Red Lentil Curry": "Rotes Linsencurry", "250 g red lentils": "250 g rote Linsen", "2 tbsp curry paste": "2 EL Currypaste",
        "Chop the onions.": "Zwiebeln würfeln.", "Tip: tastes better the next day.": "Tipp: schmeckt am nächsten Tag besser."
    ]

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        directory = FileManager.default.temporaryDirectory.appending(path: "translate-" + UUID().uuidString, directoryHint: .isDirectory)
        attachments = NoteAttachmentStore(context: container.mainContext, directory: directory)
        store = NoteStore(context: container.mainContext, attachments: attachments)
        recipesFolder = store.ensureSystemFolder(.recipes, name: "Rezepte")
    }

    private func translator(_ responder: (any ResponseStreaming)? = nil, consent: Bool = true) -> RecipeTranslator {
        RecipeTranslator(responder: responder ?? self.responder, model: { "gpt-test" }, hasConsent: { consent }, timeout: .seconds(30))
    }

    private func model(for note: NoteRecord, recipeLanguage: VoiceLanguage = .german, responder: (any ResponseStreaming)? = nil) -> RecipeTranslationModel {
        RecipeTranslationModel(noteID: note.id, store: store, translator: translator(responder), recipeLanguage: recipeLanguage)
    }

    private func recipeNote(_ text: String? = nil) throws -> NoteRecord {
        try #require(store.create(text: text ?? english, folderID: recipesFolder.id))
    }

    /// The JSON answer of a model that translates every line of `text` with `translations`.
    private func answer(for text: String) -> String {
        let lines = RecipeTranslationPlan(markdown: text).request.map { ["i": $0.index, "text": translations[$0.text] ?? $0.text] as [String: Any] }
        return String(decoding: try! JSONSerialization.data(withJSONObject: ["lines": lines]), as: UTF8.self)
    }

    private func makeImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
    }

    // MARK: Offer

    @Test func isOffered_onlyStructuredNotesInRecipesFolder() throws {
        let recipe = try recipeNote()
        #expect(RecipeTranslationModel.isOffered(recipe, store: store))
        // No structure: no section "Zutaten".
        let unstructured = try recipeNote("Oma-Kuchen: Mehl, Eier, Zucker.")
        #expect(!RecipeTranslationModel.isOffered(unstructured, store: store))
        // A structured recipe outside the folder "Rezepte", in a normal folder and in "Notizen".
        let folder = try store.createFolder(name: "Ideen")
        #expect(!RecipeTranslationModel.isOffered(try #require(store.create(text: english, folderID: folder.id)), store: store))
        #expect(!RecipeTranslationModel.isOffered(try #require(store.create(text: english)), store: store))
        // A private folder and a journal entry never.
        let journal = store.ensureJournalFolder()
        #expect(!RecipeTranslationModel.isOffered(try #require(store.create(text: english, folderID: journal.id)), store: store))
        let entry = try #require(store.create(text: english, kind: .journal, dayKey: "2026-11-20"))
        #expect(!RecipeTranslationModel.isOffered(entry, store: store))
        // A trashed recipe.
        let trashed = try recipeNote()
        store.trash(trashed.id)
        #expect(!RecipeTranslationModel.isOffered(trashed, store: store))
    }

    // MARK: Preselection

    @Test func preselection_englishRecipe_offersGerman() throws {
        let note = try recipeNote()
        #expect(model(for: note, recipeLanguage: .english).target == .german)
        let german = try recipeNote("# Curry\n\n## Zutaten\n- Reis\n")
        #expect(model(for: german, recipeLanguage: .german).target == .english)
    }

    @Test func preselection_unknown_usesRecipeLanguageSetting() throws {
        let note = try recipeNote("# Curry\n\n## Ingredienti\n- riso\n")
        #expect(RecipeNote.headingLanguage(note.text) == nil)
        #expect(RecipeTranslationModel.preselected(for: note.text, recipeLanguage: .english) == .english)
        #expect(RecipeTranslationModel.preselected(for: note.text, recipeLanguage: .german) == .german)
    }

    // MARK: Translating

    @Test func translate_showsPreviewAndChangesNothing() async throws {
        let note = try recipeNote()
        let updated = note.updatedAt
        responder.enqueue(answer(for: english))
        let model = model(for: note)
        #expect(model.phase == .choosing)
        await model.translate()
        guard case .preview(let original, let translated) = model.phase else {
            Issue.record("Expected a preview, got \(model.phase)")
            return
        }
        #expect(original == english && translated.hasPrefix("# Rotes Linsencurry") && translated.contains("## Zutaten"))
        #expect(note.text == english && note.updatedAt == updated && store.count == 1)
    }

    @Test func translate_failure_endsInFailedPhaseWithoutNoteText() async throws {
        let note = try recipeNote()
        responder.enqueue(#"{"lines":[]}"#)
        let model = model(for: note)
        await model.translate()
        guard case .failed(let message) = model.phase else {
            Issue.record("Expected a failure, got \(model.phase)")
            return
        }
        #expect(message == RecipeTranslator.Failure.mismatch.message && !message.contains("Linsen"))
        #expect(note.text == english)
        model.backToChoosing()
        #expect(model.phase == .choosing)
    }

    @Test func translate_noteThatIsNotOffered_neverCallsTheResponder() async throws {
        let note = try #require(store.create(text: english))
        let model = model(for: note)
        await model.translate()
        #expect(model.phase == .failed(RecipeTranslator.Failure.notARecipe.message))
        #expect(responder.calls.isEmpty)
    }

    @Test func cancel_dropsLateAnswer() async throws {
        let note = try recipeNote()
        let gated = GatedResponder()
        let model = model(for: note, responder: gated)
        let running = Task { await model.translate() }
        for _ in 0..<500 where !gated.wasRequested { try await Task.sleep(for: .milliseconds(10)) }
        #expect(gated.wasRequested && model.phase == .translating)
        model.cancel()
        #expect(model.phase == .choosing)
        gated.answer(answer(for: english))
        await running.value
        #expect(model.phase == .choosing)
        #expect(note.text == english)
    }

    // MARK: Applying

    @Test func replace_writesTranslatedText() async throws {
        let note = try recipeNote()
        responder.enqueue(answer(for: english))
        let model = model(for: note)
        await model.translate()
        guard case .preview(_, let translated) = model.phase else { Issue.record("No preview"); return }
        #expect(model.replace())
        #expect(note.text == translated && store.count == 1)
        // The result is still a recipe in the folder, so the menu keeps its entries.
        #expect(RecipeNote.parse(note.text) != nil && note.folderID == recipesFolder.id)
    }

    @Test func replace_afterNoteChanged_fails() async throws {
        let note = try recipeNote()
        responder.enqueue(answer(for: english))
        let model = model(for: note)
        await model.translate()
        store.updateText(note.id, text: english + "\n- 100 g rice")
        #expect(!model.replace())
        #expect(note.text == english + "\n- 100 g rice")
        #expect(model.phase == .failed("Die Notiz wurde inzwischen geändert."))
    }

    @Test func saveCopy_keepsOriginalAndCopiesAttachments() async throws {
        let note = try recipeNote()
        let image = try attachments.addImage(makeImage(), to: note.id)
        let text = english + "\n" + MarkdownText.reference(for: image.id, name: "Foto", isImage: true) + "\n"
        store.updateText(note.id, text: text)
        responder.enqueue(answer(for: text))
        let model = model(for: note)
        await model.translate()
        let copy = try #require(model.saveCopy())
        #expect(note.text == text && copy.id != note.id && copy.folderID == recipesFolder.id)
        #expect(copy.text.hasPrefix("# Rotes Linsencurry"))
        let copiedIDs = MarkdownText.attachmentIDs(in: copy.text)
        #expect(copiedIDs.count == 1 && copiedIDs.isDisjoint(with: [image.id]))
        #expect(attachments.attachments(of: copy.id).map(\.id).sorted { $0.uuidString < $1.uuidString } == Array(copiedIDs))
        #expect(attachments.url(for: image.id) != nil)
        // Nothing to save before there is a preview.
        #expect(self.model(for: note).saveCopy() == nil)
    }

    // MARK: Shopping list

    @Test func translatedNote_stillOffersIngredientsForShopping() async throws {
        let note = try recipeNote()
        responder.enqueue(answer(for: english))
        let model = model(for: note)
        await model.translate()
        model.replace()
        let importer = RecipeImporter(responder: FakePlanResponder(), model: { "gpt-test" }, hasConsent: { false })
        let before = try await importer.read(.note(note.id, text: english), language: .english, categoryNames: [], openItemKeys: [])
        let after = try await importer.read(.note(note.id, text: note.text), language: .german, categoryNames: [], openItemKeys: [])
        #expect(before.readLocally && after.readLocally)
        #expect(after.candidates.count == before.candidates.count && after.candidates.count == 2)
        #expect(after.servings == 4 && after.steps.count == before.steps.count)
        #expect(after.candidates.map(\.name) == ["rote Linsen", "Currypaste"])
    }
}
