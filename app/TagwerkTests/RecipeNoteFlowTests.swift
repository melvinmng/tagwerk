import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// A recipe as the importer returns it, for the tests of saving and of the sources.
@MainActor private func sampleResult(language: VoiceLanguage = .german, servings: Int? = 4, url: URL? = nil) -> RecipeImporter.Result {
    func item(_ name: String, _ text: String) -> RecipeImporter.Candidate {
        let line = IngredientLine.parse(text + " " + name)
        return RecipeImporter.Candidate(name: name, quantity: RecipeImporter.quantityText(of: line, locale: language.locale),
                                        line: line.amount == nil ? nil : line, category: "Sonstiges", alreadyOnList: false)
    }
    var salt = RecipeImporter.Candidate(name: "Salz", quantity: "nach Geschmack", category: "Sonstiges", alreadyOnList: false)
    salt.line = nil
    return RecipeImporter.Result(title: "Linsencurry", servings: servings,
                                 candidates: [item("rote Linsen", "250 g"), item("Zwiebel", "2"), item("Kokosmilch", "1 Dose"), salt],
                                 steps: ["Zwiebeln andünsten.", "Linsen garen."], sourceURL: url, language: language)
}

@MainActor
struct RecipeNoteSaveTests {
    final class Clock { var now = testNow() }
    let container: ModelContainer
    let clock = Clock()
    let store: NoteStore

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        let clock = self.clock
        store = NoteStore(context: container.mainContext, now: { clock.now })
        store.ensureDefaultFolders()
    }

    @Test func savesIntoRecipesFolder_withOriginalServings() throws {
        let result = sampleResult(url: URL(string: "https://www.chefkoch.de/rezepte/1"))
        let note = RecipeNoteWriter.recipeNote(from: result, title: "Linsencurry", servings: 4)
        let record = try #require(RecipeNoteWriter.save(note, language: .german, store: store))
        let folder = try #require(store.folder(role: .recipes))
        #expect(record.folderID == folder.id && record.kind == .free && store.notes(.folder(folder.id)).map(\.id) == [record.id])
        let parsed = try #require(RecipeNote.parse(record.text))
        #expect(parsed.title == "Linsencurry" && parsed.servings == 4)
        // The amounts are the ones of the recipe, in the plural their number asks for; free text keeps its words.
        #expect(parsed.ingredients == ["250 g rote Linsen", "2 Zwiebeln", "1 Dose Kokosmilch", "Salz nach Geschmack"])
        #expect(parsed.steps == result.steps && parsed.sourceURL?.absoluteString == "https://www.chefkoch.de/rezepte/1")
    }

    @Test func recipeNote_writesInTheRecipeLanguage() throws {
        let result = sampleResult(language: .english)
        let record = try #require(RecipeNoteWriter.save(RecipeNoteWriter.recipeNote(from: result, title: "Lentil curry", servings: 4),
                                                        language: result.language, store: store))
        #expect(record.text.contains("## Ingredients") && record.text.contains("Servings: 4") && record.text.contains("## Instructions"))
        #expect(RecipeNote.parse(record.text)?.servings == 4)
    }

    @Test func save_createsTheFolderWhenItIsMissing_andNothingWithoutIngredients() throws {
        let folder = try #require(store.folder(role: .recipes))
        let fresh = try ModelContainerFactory.make(inMemory: true)
        let freshStore = NoteStore(context: fresh.mainContext, now: { testNow() })
        #expect(freshStore.folder(role: .recipes) == nil)
        let record = RecipeNoteWriter.save(RecipeNote(title: "A", ingredients: ["1 Ei"]), language: .german, store: freshStore)
        #expect(record?.folderID == freshStore.folder(role: .recipes)?.id)
        #expect(RecipeNoteWriter.save(RecipeNote(title: "Leer", ingredients: []), language: .german, store: store) == nil)
        #expect(store.notes(.folder(folder.id)).isEmpty)
    }

    @Test func switchOff_savesNothing() {
        let result = sampleResult()
        #expect(RecipeResultView.noteToSave(result, fromNote: false, savesNote: false, servings: 4) == nil)
        // A recipe that came from a note is not saved a second time, whatever the switch says.
        #expect(RecipeResultView.noteToSave(result, fromNote: true, savesNote: true, servings: 4) == nil)
        let note = RecipeResultView.noteToSave(result, fromNote: false, savesNote: true, servings: 4)
        #expect(note?.title == "Linsencurry" && note?.servings == 4 && note?.ingredients.count == 4)
        // The switch starts on, unless the source is a note.
        #expect(RecipeResultView.defaultSavesNote(fromNote: false) && !RecipeResultView.defaultSavesNote(fromNote: true))
    }

    @Test func noteToSave_usesTheServingsTheUserSetWhenTheRecipeHadNone() {
        let note = RecipeResultView.noteToSave(sampleResult(servings: nil), fromNote: false, savesNote: true, servings: 6)
        #expect(note?.servings == 6)
    }
}

@MainActor
struct RecipeSourceTests {
    final class Clock { var now = testNow() }
    let container: ModelContainer
    let clock = Clock()
    let store: NoteStore

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        let clock = self.clock
        store = NoteStore(context: container.mainContext, now: { clock.now })
        store.ensureDefaultFolders()
    }

    private func advance() { clock.now = clock.now.addingTimeInterval(60) }

    @Test func recipesFolderListsNewestFirst_noPrivateNotes() throws {
        let recipes = try #require(store.folder(role: .recipes))
        let old = try #require(store.create(text: "# Alt\n\n## Zutaten\n- 1 Ei", folderID: recipes.id)); advance()
        let unstructured = try #require(store.create(text: "Pfannkuchen: Mehl, Milch", folderID: recipes.id)); advance()
        let newest = try #require(store.create(text: "# Neu\n\n## Zutaten\n- 2 Eier", folderID: recipes.id)); advance()
        // Private content never appears: a journal entry, and a free note that lies in the journal folder.
        let journalFolder = store.ensureJournalFolder()
        _ = try #require(store.create(text: "Tagebuch heute", kind: .journal, dayKey: "2026-11-20"))
        let moved = try #require(store.create(text: "# Geheim\n\n## Zutaten\n- 1 Geheimnis"))
        store.move(noteIDs: [moved.id], to: journalFolder.id)
        _ = try #require(store.create(text: "Traum", kind: .dream, dayKey: "2026-11-20"))
        _ = try #require(store.create(text: "Gedanke", kind: .morning, dayKey: "2026-11-20"))
        let trashed = try #require(store.create(text: "# Weg\n\n## Zutaten\n- 1 x", folderID: recipes.id))
        store.trash(trashed.id)

        let listed = RecipeNoteSource.recipeNotes(in: store)
        #expect(listed.map(\.id) == [newest.id, unstructured.id, old.id])
        #expect(listed.map(\.isStructured) == [true, false, true])
        #expect(listed.map(\.title) == ["Neu", "Pfannkuchen: Mehl, Milch", "Alt"])
        let titles = Set(RecipeNoteSource.otherNotes(in: store).map(\.title))
        #expect(!titles.contains("Tagebuch heute") && !titles.contains("Geheim") && !titles.contains("Traum") && !titles.contains("Gedanke"))
        #expect(!titles.contains("Weg") && !titles.contains("Neu"))
        #expect(!listed.contains { $0.title == "Geheim" })
    }

    @Test func otherNotes_listFreeNotesOutsideTheRecipesFolder() throws {
        let recipes = try #require(store.folder(role: .recipes))
        _ = try #require(store.create(text: "# Im Ordner\n\n## Zutaten\n- 1 Ei", folderID: recipes.id)); advance()
        let loose = try #require(store.create(text: "Einkauf und Rezeptidee")); advance()
        let brainDump = try #require(store.folder(role: .brainDump))
        let inDump = try #require(store.create(text: "Idee", folderID: brainDump.id))
        #expect(RecipeNoteSource.otherNotes(in: store).map(\.id) == [inDump.id, loose.id])
        #expect(RecipeNoteSource.isOffered(loose, store: store))
        let empty = store.createBlank()
        #expect(!RecipeNoteSource.isOffered(empty, store: store))
    }

    @Test func withoutARecipesFolder_nothingIsListed() throws {
        let fresh = try ModelContainerFactory.make(inMemory: true)
        let freshStore = NoteStore(context: fresh.mainContext, now: { testNow() })
        #expect(RecipeNoteSource.recipeNotes(in: freshStore).isEmpty)
    }
}

@MainActor
struct RecipeManualNoteTests {
    let container: ModelContainer
    let store: NoteStore

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        store = NoteStore(context: container.mainContext, now: { testNow() })
        store.ensureDefaultFolders()
    }

    @Test func newRecipe_createsTheSkeletonInTheRecipesFolder() throws {
        let note = try #require(RecipeNoteWriter.createBlank(language: .german, store: store))
        #expect(note.folderID == store.folder(role: .recipes)?.id && note.kind == .free)
        #expect(note.text.contains("## Zutaten") && note.text.contains("## Zubereitung"))
        #expect(RecipeNote.isOnlyTemplate(note.text) && RecipeNote.parse(note.text) == nil)
        let english = try #require(RecipeNoteWriter.createBlank(language: .english, store: store))
        #expect(english.text.contains("## Ingredients"))
    }

    @Test func untouchedSkeleton_isRemovedWhenTheNoteCloses_aWrittenOneStays() throws {
        let untouched = try #require(RecipeNoteWriter.createBlank(language: .german, store: store))
        store.deleteIfEmpty(untouched.id)
        #expect(store.note(id: untouched.id) == nil)
        let written = try #require(RecipeNoteWriter.createBlank(language: .german, store: store))
        store.updateText(written.id, text: written.text.replacingOccurrences(of: "- \n", with: "- 2 Eier\n"))
        store.deleteIfEmpty(written.id)
        #expect(store.note(id: written.id) != nil)
        // The note is a recipe now: the ingredients can go on the shopping list.
        #expect(RecipeNote.parse(store.note(id: written.id)?.text ?? "")?.ingredients == ["2 Eier"])
    }
}
