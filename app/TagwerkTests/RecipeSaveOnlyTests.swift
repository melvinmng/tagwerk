import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// "Rezept mit ChatGPT anlegen": a recipe is read like for the shopping list, but only saved as a note.
@MainActor
struct RecipeSaveOnlyTests {
    final class Clock { var now = testNow() }
    let fixture = RecipeReadingFixture()
    let container: ModelContainer
    let clock = Clock()
    let notes: NoteStore

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        let clock = self.clock
        notes = NoteStore(context: container.mainContext, now: { clock.now })
        notes.ensureDefaultFolders()
    }

    @Test func saveOnly_writesNoteInRecipesFolder_andNoShoppingItems() async throws {
        // A shopping list next to the notes: it must stay as it is.
        let settings = try AppSettings.current(in: container.mainContext)
        settings.shoppingListID = "shop"
        let now = testNow()
        let reminders = InMemoryReminderStore(lists: [ListInfo(id: "shop", title: "Einkauf", colorHex: nil, kind: .calDAV)], records: [], now: { now })
        let categories = ShoppingCategoryStore(context: container.mainContext, settings: settings, now: { now })
        categories.seedIfNeeded()
        let model = ShoppingModel(store: reminders, settings: settings, categories: categories, now: { now })

        fixture.responder.enqueue(fixture.curry)
        let url = URL(string: "https://www.chefkoch.de/rezepte/linsencurry")!
        fixture.fetcher.page = "<html><body><p>250 g rote Linsen</p></body></html>"
        let result = try await fixture.importer().read(.link(url), language: .german, categoryNames: [], openItemKeys: [])
        let note = RecipeNoteWriter.recipeNote(from: result, title: result.title, servings: result.servings)
        let record = try #require(RecipeNoteWriter.save(note, language: result.language, store: notes))

        #expect(record.folderID == notes.folder(role: .recipes)?.id)
        #expect(reminders.records.isEmpty, "no item was written to the shopping list")
        #expect(categories.assignments().isEmpty, "no category was learned")
        #expect(model.openItems.isEmpty)
        #expect(notes.notes(.folder(try #require(notes.folder(role: .recipes)?.id))).count == 1)
    }

    @Test func saveOnly_noteIsStructured_roundTrips() async throws {
        fixture.responder.enqueue(fixture.curry)
        let url = URL(string: "https://www.chefkoch.de/rezepte/linsencurry")!
        fixture.fetcher.page = "<html><body><p>250 g rote Linsen</p></body></html>"
        let result = try await fixture.importer().read(.link(url), language: .german, categoryNames: [], openItemKeys: [])
        let record = try #require(RecipeNoteWriter.save(RecipeNoteWriter.recipeNote(from: result, title: "Linsencurry", servings: 4),
                                                        language: .german, store: notes))
        let parsed = try #require(RecipeNote.parse(record.text))
        #expect(parsed.title == "Linsencurry" && parsed.servings == 4)
        #expect(parsed.ingredients == ["250 g rote Linsen", "1 Dose Kokosmilch", "2 Eier", "Salz nach Geschmack"])
        #expect(parsed.steps == ["Zwiebeln andünsten.", "Linsen garen."] && parsed.sourceURL == url)
        // The saved note is the source of "Zutaten auf die Einkaufsliste": it is read on the device, with the servings.
        let again = try await fixture.importer(consent: false).read(.note(record.id, text: record.text), language: .german,
                                                                    categoryNames: [], openItemKeys: [])
        #expect(again.servings == 4 && again.readLocally && again.candidates.count == 4 && fixture.responder.calls.count == 1)
    }

    @Test func saveOnly_requestSendsNoCategoryNamesOrOpenItems() async throws {
        fixture.responder.enqueue(fixture.curry)
        _ = try await fixture.importer().read(.text("250 g Linsen"), language: .german, categoryNames: [], openItemKeys: ["milch"])
        let text = fixture.sentText()
        #expect(text.contains(#""categories":["Sonstiges"]"#) && text.contains("250 g Linsen"))
        #expect(!text.contains("Kühlregal") && !text.contains("milch"))
    }

    @Test func saveOnly_withoutConsent_readsNothing() async {
        await #expect(throws: RecipeImporter.Failure.consentMissing) {
            try await fixture.importer(consent: false).read(.text("250 g Linsen"), language: .german, categoryNames: [], openItemKeys: [])
        }
        await #expect(throws: RecipeImporter.Failure.consentMissing) {
            try await fixture.importer(consent: false).read(.photos([Data([1, 2, 3])]), language: .german, categoryNames: [], openItemKeys: [])
        }
        await #expect(throws: RecipeImporter.Failure.consentMissing) {
            try await fixture.importer(consent: false).read(.link(URL(string: "https://example.com/r")!), language: .german, categoryNames: [], openItemKeys: [])
        }
        #expect(fixture.responder.calls.isEmpty && fixture.modelCalls.models == 0 && fixture.fetcher.urls.isEmpty)
    }

    @Test func saveOnly_cancelSavesNothing() async throws {
        // Reading alone writes nothing; only "Rezept speichern" does.
        fixture.responder.enqueue(fixture.curry)
        _ = try await fixture.importer().read(.text("250 g Linsen"), language: .german, categoryNames: [], openItemKeys: [])
        #expect(notes.notes(.folder(try #require(notes.folder(role: .recipes)?.id))).isEmpty && notes.count == 0)
        // A title is needed to save.
        #expect(!RecipeNoteSaveView.canSave(title: "  ") && RecipeNoteSaveView.canSave(title: "Linsencurry"))
    }

    @Test func sharedRead_sameResultForBothPurposes() async throws {
        fixture.responder.enqueue(fixture.curry)
        fixture.responder.enqueue(fixture.curry)
        let shopping = try await fixture.importer().read(.text("250 g Linsen"), language: .german,
                                                         categoryNames: fixture.categories, openItemKeys: [])
        let saveOnly = try await fixture.importer().read(.text("250 g Linsen"), language: .german, categoryNames: [], openItemKeys: [])
        #expect(shopping.title == saveOnly.title && shopping.servings == saveOnly.servings && shopping.steps == saveOnly.steps)
        #expect(shopping.candidates.map(\.name) == saveOnly.candidates.map(\.name))
        #expect(shopping.candidates.map(\.quantity) == saveOnly.candidates.map(\.quantity))
        // Only the categories differ: without a list there is only "Sonstiges".
        #expect(Set(saveOnly.candidates.map(\.category)) == ["Sonstiges"])
        #expect(fixture.responder.instructions.count == 2 && fixture.responder.instructions[0] == fixture.responder.instructions[1])
    }
}

struct RecipeLanguageSettingTests {
    @Test func defaultFollowsTheApp() {
        let settings = AppSettings()
        #expect(settings.recipeLanguage == RecipeLanguage.automatic)
        #expect(settings.resolvedRecipeLanguage == VoiceLanguage.app)
    }

    @Test func fixedLanguage_winsOverTheApp() {
        let settings = AppSettings()
        settings.recipeLanguage = VoiceLanguage.english.rawValue
        #expect(settings.resolvedRecipeLanguage == .english)
        settings.recipeLanguage = VoiceLanguage.german.rawValue
        #expect(settings.resolvedRecipeLanguage == .german)
        settings.recipeLanguage = "unbekannt"
        #expect(settings.resolvedRecipeLanguage == VoiceLanguage.app)
    }
}
