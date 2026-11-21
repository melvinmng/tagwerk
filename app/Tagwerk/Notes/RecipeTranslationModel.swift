import Foundation
import Observation
import TagwerkCore

/// The state of the sheet "Rezept übersetzen": choose the language, wait for the answer, look at the preview, then replace the
/// note or save a copy. Nothing changes before the user taps one of the two buttons of the preview.
///
/// It translates the stored text of the note (the page saves before it opens the sheet) and keeps that text as `original`. A
/// replacement is only written while the stored text is still the original, so a change made in the meantime is not lost.
/// The note text is in no log and in no failure message.
@MainActor
@Observable
final class RecipeTranslationModel: Identifiable {
    enum Phase: Equatable {
        case choosing
        case translating
        /// The proposal: the text as it is stored now and the translation.
        case preview(original: String, translated: String)
        case failed(String)
    }

    private(set) var phase: Phase = .choosing
    /// The language to translate into; preselected, the user can change it while `choosing` or after a failure.
    var target: VoiceLanguage

    let noteID: UUID
    /// One sheet per note (`sheet(item:)`).
    nonisolated var id: UUID { noteID }
    @ObservationIgnored private let store: NoteStore
    @ObservationIgnored private let translator: RecipeTranslator
    /// Counts requests and cancellations; an answer that arrives for an older count is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var taskToken = 0

    init(noteID: UUID, store: NoteStore, translator: RecipeTranslator, recipeLanguage: VoiceLanguage) {
        self.noteID = noteID
        self.store = store
        self.translator = translator
        target = Self.preselected(for: store.note(id: noteID)?.text ?? "", recipeLanguage: recipeLanguage)
    }

    // MARK: Offer

    /// Whether "Übersetzen …" is offered for a note: a free, live note that lies directly in the folder "Rezepte" and reads as
    /// a structured recipe. Everything else (other folders, private folders, journal, Bible Study, Dream Log, notes without
    /// a section "Zutaten") is not offered; the folder "Rezepte" is the only place this feature works in.
    static func isOffered(_ note: NoteRecord, store: NoteStore) -> Bool {
        guard note.kind == .free, note.deletedAt == nil, let folderID = note.folderID,
              store.folder(id: folderID)?.role == .recipes else { return false }
        return RecipeNote.parse(note.text) != nil
    }

    /// The language the recipe is not written in; when the headings do not tell, the "Sprache für Rezepte".
    static func preselected(for text: String, recipeLanguage: VoiceLanguage) -> VoiceLanguage {
        switch RecipeNote.headingLanguage(text) {
        case .german?: .english
        case .english?: .german
        case nil: recipeLanguage
        }
    }

    // MARK: Translating

    /// Starts `translate()` and remembers the task, so `cancel()` can stop it.
    func start() {
        guard task == nil else { return }
        taskToken += 1
        let token = taskToken
        task = Task { [weak self] in
            await self?.translate()
            // A task that was cancelled and replaced must not clear the reference to its successor.
            if self?.taskToken == token { self?.task = nil }
        }
    }

    /// One request for the stored text of the note. A late answer after `cancel()` is dropped.
    func translate() async {
        if case .translating = phase { return }
        guard let note = store.note(id: noteID), Self.isOffered(note, store: store) else {
            phase = .failed(RecipeTranslator.Failure.notARecipe.message)
            return
        }
        let original = note.text
        generation += 1
        let mine = generation
        phase = .translating
        do {
            let translated = try await translator.translate(original, to: target)
            guard mine == generation else { return }
            phase = .preview(original: original, translated: translated)
        } catch is CancellationError {
            if mine == generation { phase = .choosing }
        } catch let failure as RecipeTranslator.Failure {
            guard mine == generation else { return }
            phase = .failed(failure.message)
        } catch {
            guard mine == generation else { return }
            phase = .failed(RecipeTranslator.Failure.failed.message)
        }
    }

    /// Stops a running request; its answer is dropped. Also called when the sheet closes.
    func cancel() {
        generation += 1
        taskToken += 1
        task?.cancel()
        task = nil
        if case .translating = phase { phase = .choosing }
    }

    /// Back to the language choice, e.g. after a failure.
    func backToChoosing() {
        guard phase != .translating else { return }
        phase = .choosing
    }

    // MARK: Applying

    /// Writes the translation into the note. Only while the stored text is still the original; otherwise nothing is written and
    /// the phase says so. Returns whether the note was changed.
    @discardableResult
    func replace() -> Bool {
        guard case .preview(let original, let translated) = phase else { return false }
        guard let note = store.note(id: noteID), note.deletedAt == nil, note.text == original else {
            phase = .failed(String(localized: "Die Notiz wurde inzwischen geändert."))
            return false
        }
        store.updateText(noteID, text: translated)
        return true
    }

    /// Saves the translation as a new note in the same folder, with attachments of its own. The note itself stays as it is.
    func saveCopy() -> NoteRecord? {
        guard case .preview(_, let translated) = phase else { return nil }
        return store.duplicate(noteID, text: translated)
    }
}
