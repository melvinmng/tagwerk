import AIKit
import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// Editing and following up on the translation of a recipe note (plan ki-vorschlaege-anpassen, task D3).
@MainActor
struct RecipeTranslationFollowUpTests {
    let container: ModelContainer
    let store: NoteStore
    let responder = FakePlanResponder()
    let recipesFolder: NoteFolderRecord
    final class Flags { var consent = true; var models = 0 }
    let flags = Flags()

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
        store = NoteStore(context: container.mainContext)
        recipesFolder = store.ensureSystemFolder(.recipes, name: "Rezepte")
    }

    private func translator() -> RecipeTranslator {
        let flags = self.flags
        return RecipeTranslator(responder: responder, model: { flags.models += 1; return "gpt-test" }, hasConsent: { flags.consent }, timeout: .seconds(30))
    }

    private func model(for note: NoteRecord) -> RecipeTranslationModel {
        RecipeTranslationModel(noteID: note.id, store: store, translator: translator(), recipeLanguage: .german)
    }

    private func answer(_ text: String, replacing table: [String: String] = [:]) -> String {
        let lines = RecipeTranslationPlan(markdown: text).request.map {
            ["i": $0.index, "text": table[$0.text] ?? translations[$0.text] ?? $0.text] as [String: Any]
        }
        return String(decoding: try! JSONSerialization.data(withJSONObject: ["lines": lines]), as: UTF8.self)
    }

    /// A model in the preview phase with the German translation.
    private func previewed() async throws -> (RecipeTranslationModel, NoteRecord) {
        let note = try #require(store.create(text: english, folderID: recipesFolder.id))
        responder.enqueue(answer(english))
        let model = model(for: note)
        model.target = .german
        await model.translate()
        guard case .preview = model.phase else { Issue.record("expected a preview"); return (model, note) }
        return (model, note)
    }

    // MARK: Editing

    @Test func preview_editable_replaceUsesEditedText() async throws {
        let (model, note) = try await previewed()
        model.editedText = model.editedText.replacingOccurrences(of: "Zwiebeln würfeln.", with: "Die Zwiebeln fein würfeln.")
        model.textEdited()

        #expect(model.replace())

        #expect(store.note(id: note.id)?.text.contains("Die Zwiebeln fein würfeln.") == true)
    }

    @Test func saveCopy_usesEditedText() async throws {
        let (model, note) = try await previewed()
        model.editedText = model.editedText.replacingOccurrences(of: "Zwiebeln würfeln.", with: "Zwiebeln hacken.")
        let copy = try #require(model.saveCopy())
        #expect(copy.text.contains("Zwiebeln hacken.") && store.note(id: note.id)?.text == english)
    }

    @Test func editedText_brokenStructure_blocksReplaceWithMessage() async throws {
        let (model, note) = try await previewed()
        model.editedText = model.editedText.replacingOccurrences(of: "250 g rote Linsen", with: "300 g rote Linsen")
        model.textEdited()

        #expect(!model.replace())

        #expect(model.editProblem == RecipeTranslator.editedMessage(for: .amountsChanged))
        #expect(store.note(id: note.id)?.text == english)
        // A lost heading breaks the structure: no copy either.
        model.editedText = model.editedText.replacingOccurrences(of: "300 g rote Linsen", with: "250 g rote Linsen").replacingOccurrences(of: "## Zutaten", with: "Zutaten")
        #expect(model.saveCopy() == nil && model.editProblem == RecipeTranslator.editedMessage(for: .structureChanged))
        // Typing the problem away makes it writable again.
        model.editedText = model.editedText.replacingOccurrences(of: "\nZutaten", with: "\n## Zutaten")
        #expect(model.replace())
    }

    // MARK: Follow-up

    @Test func revise_requiresRecipeConsent() async throws {
        let (model, _) = try await previewed()
        flags.consent = false
        let before = responder.calls.count
        await model.revise("Du statt Sie")
        #expect(responder.calls.count == before)
        guard case .failed = model.followUpState else { Issue.record("expected a failure"); return }
    }

    @Test func revise_sendsLinesCurrentTranslationAndMessage_inTheFormatOfTheFirstRequest() async throws {
        let (model, _) = try await previewed()
        model.editedText = model.editedText.replacingOccurrences(of: "Zwiebeln würfeln.", with: "Zwiebeln hacken.")
        responder.enqueue(answer(english, replacing: ["Chop the onions.": "Zwiebeln hacken.", "Tip: tastes better the next day.": "Tipp: am nächsten Tag besser."]))

        await model.revise("Kürzer")

        let text = responder.calls[1].input.compactMap { item -> String? in if case .user(let text) = item { text } else { nil } }.joined()
        let object = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(object["message"] as? String == "Kürzer" && object["target"] as? String == "Deutsch")
        let current = try #require(object["current"] as? [[String: Any]]).compactMap { $0["text"] as? String }
        #expect(current.contains("Zwiebeln hacken.") && current.contains("250 g rote Linsen"))
        #expect(responder.calls[1].schema == "recipe_translation" && responder.schemas[1] == RecipeTranslator.schema)
        #expect(model.editedText.contains("Tipp: am nächsten Tag besser.") && model.followUpState == .ready)
    }

    @Test func revise_keepsIndicesAndQuantities() async throws {
        let (model, _) = try await previewed()
        let before = model.editedText
        // The amounts changed: the answer is refused as a whole and nothing changes.
        responder.enqueue(answer(english, replacing: ["250 g red lentils": "300 g rote Linsen"]))
        await model.revise("Mehr")
        guard case .failed = model.followUpState else { Issue.record("expected a failure"); return }
        #expect(model.editedText == before && model.previousText == nil)
        // A missing index is refused as well.
        responder.enqueue(#"{"lines":[{"i":0,"text":"Rotes Linsencurry"}]}"#)
        await model.revise("Mehr")
        #expect(model.editedText == before)
    }

    @Test func revise_onlyWhereOffered() async throws {
        let (model, note) = try await previewed()
        // The note moved out of the folder "Rezepte" meanwhile: no follow-up.
        let other = try store.createFolder(name: "Ideen")
        store.move(noteIDs: [note.id], to: other.id)
        let before = responder.calls.count
        await model.revise("Kürzer")
        #expect(responder.calls.count == before)
        guard case .failed = model.followUpState else { Issue.record("expected a failure"); return }
    }

    @Test func revise_noteChangedMeanwhile_reportsIt() async throws {
        let (model, note) = try await previewed()
        store.updateText(note.id, text: english + "\n\nNeu.")
        let before = responder.calls.count
        await model.revise("Kürzer")
        #expect(responder.calls.count == before && model.followUpState == .failed("Die Notiz wurde inzwischen geändert."))
    }

    @Test func undo_restoresPreviousTranslation() async throws {
        let (model, _) = try await previewed()
        let before = model.editedText
        responder.enqueue(answer(english, replacing: ["Chop the onions.": "Zwiebeln hacken."]))
        await model.revise("Anders")
        #expect(model.editedText != before && model.previousText == before)

        model.undoRevision()

        #expect(model.editedText == before && model.previousText == nil && model.followUpReply.isEmpty)
    }

    @Test func undo_isDroppedByTyping() async throws {
        let (model, _) = try await previewed()
        responder.enqueue(answer(english, replacing: ["Chop the onions.": "Zwiebeln hacken."]))
        await model.revise("Anders")
        model.editedText += " "
        model.textEdited()
        #expect(model.previousText == nil)
    }

    @Test func noteText_inNoLogAndNoFailureMessage() async throws {
        let (model, _) = try await previewed()
        responder.enqueueFailure(.network)
        await model.revise("Kürzer")
        guard case .failed(let message) = model.followUpState else { Issue.record("expected a failure"); return }
        #expect(!message.contains("Linsen") && !message.contains("Curry"))
    }

    @Test func cancel_dropsALateAnswer() async throws {
        let note = try #require(store.create(text: english, folderID: recipesFolder.id))
        let gate = Gate()
        let gated = GateAfterFirst(inner: responder, gate: gate)
        let flags = self.flags
        let slow = RecipeTranslator(responder: gated, model: { flags.models += 1; return "gpt-test" }, hasConsent: { true }, timeout: .seconds(30))
        let model = RecipeTranslationModel(noteID: note.id, store: store, translator: slow, recipeLanguage: .german)
        model.target = .german
        responder.enqueue(answer(english))
        await model.translate()
        let before = model.editedText
        responder.enqueue(answer(english, replacing: ["Chop the onions.": "Zwiebeln hacken."]))

        let revising = Task { await model.revise("Anders") }
        while model.followUpState != .sending { await Task.yield() }
        model.cancel()
        gate.open()
        await revising.value

        #expect(model.editedText == before && model.followUpState == .ready && model.previousText == nil)
    }
}

/// Forwards the first request at once and holds every later one until the gate opens.
private final class GateAfterFirst: ResponseStreaming, @unchecked Sendable {
    let inner: FakePlanResponder
    let gate: Gate
    private let lock = NSLock()
    private var count = 0
    init(inner: FakePlanResponder, gate: Gate) { self.inner = inner; self.gate = gate }
    func respond(model: String, instructions: String, input: [InputItem], tools: [ToolDefinition],
                 jsonSchema: (name: String, schema: Data)?) -> AsyncThrowingStream<StreamEvent, Error> {
        let number = lock.withLock { () -> Int in count += 1; return count }
        let stream = inner.respond(model: model, instructions: instructions, input: input, tools: tools, jsonSchema: jsonSchema)
        guard number > 1 else { return stream }
        return AsyncThrowingStream { continuation in
            Task {
                await gate.wait()
                do { for try await event in stream { continuation.yield(event) }; continuation.finish() } catch { continuation.finish(throwing: error) }
            }
        }
    }
}
