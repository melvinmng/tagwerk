import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// A recipe shared into Tagwerk: the app sheet asks whether the ingredients go on the shopping list or the recipe is only
/// saved as a note. Both ways read the recipe with one request.
@MainActor
struct ShareRecipeChoiceTests {
    let fixture = RecipeReadingFixture()
    let container: ModelContainer
    let notes: NoteStore

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        notes = NoteStore(context: container.mainContext, now: { testNow() })
        notes.ensureDefaultFolders()
    }

    // MARK: The choice

    @Test func choice_isOfferedOnlyWhenTheSheetAsksForIt() {
        #expect(RecipeSheet.savesOnly(offersSaveOnly: true, purpose: .saveOnly))
        #expect(!RecipeSheet.savesOnly(offersSaveOnly: true, purpose: .shopping))
        // A sheet without the second button always goes to the list. The shopping page offers both buttons too (EK3b).
        #expect(!RecipeSheet.savesOnly(offersSaveOnly: false, purpose: .saveOnly))
        #expect(!RecipeSheet.savesOnly(offersSaveOnly: false, purpose: .shopping))
    }

    @Test func shoppingChoice_savesTheNoteToo_unlessTheRecipeCameFromANote() async throws {
        fixture.responder.enqueue(fixture.curry)
        let result = try await fixture.importer().read(.text("250 g rote Linsen"), language: .german,
                                                       categoryNames: fixture.categories, openItemKeys: [])
        // "Both": the switch of the result page starts on, so the shopping choice keeps the recipe as a note as well.
        #expect(RecipeResultView.defaultSavesNote(fromNote: false))
        #expect(RecipeResultView.noteToSave(result, fromNote: false, savesNote: true, servings: 4) != nil)
        // The user can switch it off: then only the ingredients go on the list.
        #expect(RecipeResultView.noteToSave(result, fromNote: false, savesNote: false, servings: 4) == nil)
    }

    // MARK: Save only

    @Test func saveOnly_ofASharedPhoto_readsOnce_savesTheNote_andLeavesTheListAlone() async throws {
        let settings = try AppSettings.current(in: container.mainContext)
        settings.shoppingListID = "shop"
        let now = testNow()
        let reminders = InMemoryReminderStore(lists: [ListInfo(id: "shop", title: "Einkauf", colorHex: nil, kind: .calDAV)],
                                              records: [], now: { now })
        let categories = ShoppingCategoryStore(context: container.mainContext, settings: settings, now: { now })
        categories.seedIfNeeded()

        fixture.responder.enqueue(fixture.curry)
        // What `RecipeInputView.read` sends for "Nur als Rezept speichern": no category names, no open items.
        let result = try await fixture.importer().read(.photos([Data([1, 2, 3])]), language: .german, categoryNames: [],
                                                       openItemKeys: [])
        #expect(fixture.responder.calls.count == 1, "one request for the whole recipe")
        let sent = fixture.sentText()
        #expect(!sent.contains("Kühlregal"), "the names of the shopping categories are not sent when only a note is made")

        let record = try #require(RecipeNoteWriter.save(RecipeNoteWriter.recipeNote(from: result, title: result.title, servings: result.servings),
                                                        language: .german, store: notes))
        #expect(record.folderID == notes.folder(role: .recipes)?.id)
        #expect(RecipeNote.parse(record.text)?.ingredients.count == 4)
        #expect(reminders.records.isEmpty, "nothing was put on the shopping list")
        #expect(categories.assignments().isEmpty, "no category was learned")
        #expect(fixture.responder.calls.count == 1, "saving the note sends nothing more")
    }

    @Test func saveOnly_withoutConsent_sendsNothing() async {
        // The same consent rule as for the shopping list: nothing leaves the phone before the one-time agreement.
        await #expect(throws: RecipeImporter.Failure.consentMissing) {
            try await fixture.importer(consent: false).read(.photos([Data([1, 2, 3])]), language: .german, categoryNames: [],
                                                            openItemKeys: [])
        }
        #expect(fixture.responder.calls.isEmpty)
    }

    @Test func shoppingChoice_sendsTheCategoryNames_saveOnlyDoesNot() async throws {
        fixture.responder.enqueue(fixture.curry)
        fixture.responder.enqueue(fixture.curry)
        _ = try await fixture.importer().read(.text("250 g rote Linsen"), language: .german, categoryNames: fixture.categories,
                                              openItemKeys: [])
        _ = try await fixture.importer().read(.text("250 g rote Linsen"), language: .german, categoryNames: [], openItemKeys: [])
        #expect(fixture.sentText(0).contains("Kühlregal"))
        #expect(!fixture.sentText(1).contains("Kühlregal"))
    }
}
