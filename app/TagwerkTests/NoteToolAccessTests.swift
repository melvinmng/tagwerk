import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The single place that selects notes for ChatGPT (issue #173, point 8): private notes never get through.
@MainActor
struct NoteToolAccessTests {
    /// Held so the store's context stays valid for the whole test.
    let container: ModelContainer
    let store: NoteStore
    let access: NoteToolAccess

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        store = NoteStore(context: container.mainContext)
        access = NoteToolAccess(store: store)
    }

    /// One note of every kind that must stay out, plus a normal one. The subfolder note is a guard against damaged
    /// data: the app cannot create subfolders below system folders (`NoteFolderRulesTests`).
    private func fill() throws -> (normal: NoteRecord, hidden: [NoteRecord]) {
        let normal = try #require(store.create(text: "Einkaufsplan Wochenende"))
        let journalEntry = try #require(store.create(text: "Dankbar für Ruhe", kind: .journal, dayKey: "2026-11-18"))
        let bible = try #require(store.create(text: "Römer 8", kind: .bibleStudy))
        let dream = try #require(store.create(text: "Ich flog über ein Feld", kind: .dream, dayKey: "2026-11-18"))
        let journalFolder = store.ensureJournalFolder()
        let inJournalFolder = try #require(store.create(text: "Freie Notiz im Tagebuch-Ordner", folderID: journalFolder.id))
        let sub = NoteFolderRecord(name: "Unterordner", parentID: journalFolder.id, order: 0)
        store.context.insert(sub)
        store.save()
        let inSubfolder = try #require(store.create(text: "Notiz im Unterordner", folderID: sub.id))
        let trashed = try #require(store.create(text: "Gelöschte Notiz"))
        store.trash(trashed.id)
        return (normal, [journalEntry, bible, dream, inJournalFolder, inSubfolder, trashed])
    }

    @Test func toolAccess_excludesPrivateNotes() throws {
        let (normal, _) = try fill()
        #expect(access.visibleNotes().map(\.id) == [normal.id])
    }

    @Test func visibleNote_privateTrashedAndUnknown_areNil() throws {
        let (normal, hidden) = try fill()
        #expect(access.visibleNote(key: NoteToolAccess.key(for: normal.id))?.id == normal.id)
        for note in hidden { #expect(access.visibleNote(key: NoteToolAccess.key(for: note.id)) == nil, "\(note.kind)") }
        #expect(access.visibleNote(key: NoteToolAccess.key(for: UUID())) == nil)
    }

    /// The locked free note, recipe and morning note of the next two tests, plus a normal note.
    private func fillLocked() throws -> (normal: NoteRecord, locked: [NoteRecord], recipe: NoteRecord, free: NoteRecord) {
        let normal = try #require(store.create(text: "Einkaufsplan Wochenende"))
        let free = try #require(store.create(text: "Gesperrte freie Notiz"))
        let recipeFolder = store.ensureSystemFolder(.recipes, name: "Rezepte")
        let recipe = try #require(store.create(text: "# Gesperrtes Curry\n\n## Zutaten\n- 1 Zwiebel\n", folderID: recipeFolder.id))
        let morning = try #require(store.create(text: "Gesperrte Gedanken", kind: .morning, dayKey: "2026-11-18"))
        return (normal, [free, recipe, morning], recipe, free)
    }

    /// A locked note that is not unlocked reaches no outbound path: one locked free note, one locked recipe and one locked morning
    /// note. The store without a lock session keeps every locked note back.
    @Test func lockedNote_whileLocked_reachesNoOutboundPath() throws {
        let (normal, locked, recipe, free) = try fillLocked()
        let morning = locked[2]
        // Before the lock the routine note field offers suggestions (the check below would otherwise prove nothing).
        let field = NoteFieldModel(store: store, kind: .morning, day: PlanDay(year: 2026, month: 11, day: 18), isSignedIn: { true },
                                   now: { testNow() })
        #expect(field.canSuggest)
        store.setLocked(locked.map(\.id), true)
        // The notes chat: not listed, not readable, not searchable, no card title.
        #expect(access.visibleNotes().map(\.id) == [normal.id])
        for note in locked {
            #expect(access.visibleNote(key: NoteToolAccess.key(for: note.id)) == nil)
            #expect(access.cardTitle(key: NoteToolAccess.key(for: note.id)) == nil)
            #expect(!NoteAssistantEntry.isOffered(target: .note(note.id), store: store))
        }
        #expect(access.entries(folderID: nil, query: nil).map(\.id) == [normal.id])
        #expect(access.entries(folderID: nil, query: "gesperrte").isEmpty)
        // The recipe paths: the picker, "Rezept übersetzen" and "Zutaten auf die Einkaufsliste".
        #expect(!RecipeNoteSource.isOffered(recipe, store: store))
        #expect(!RecipeNoteSource.isOffered(free, store: store))
        #expect(!RecipeTranslationModel.isOffered(recipe, store: store))
        // The note field of the routines never offers "Vorschläge holen" for it (`NoteSuggestionModelTests` covers the request).
        #expect(!field.canSuggest)
        #expect(store.isPrivate(morning))
    }

    /// The same notes are open to the assistant while the lock session is open, and closed again when it ends. Private notes stay out
    /// in both states, also a locked one in a private folder.
    @Test func lockedNote_whileUnlocked_isOpenToTheAssistant_untilTheSessionEnds() throws {
        let (normal, locked, recipe, free) = try fillLocked()
        let morning = locked[2]
        let journalFolder = store.ensureJournalFolder()
        let lockedInJournal = try #require(store.create(text: "Gesperrt im Tagebuch-Ordner", folderID: journalFolder.id))
        let dream = try #require(store.create(text: "Traum", kind: .dream, dayKey: "2026-11-18"))
        var sessionIsOpen = false
        store.lockHoldsBack = { $0 && !sessionIsOpen }
        store.setLocked(locked.map(\.id) + [lockedInJournal.id, dream.id], true)
        let field = NoteFieldModel(store: store, kind: .morning, day: PlanDay(year: 2026, month: 11, day: 18), isSignedIn: { true },
                                   now: { testNow() })
        #expect(!field.canSuggest)
        sessionIsOpen = true
        #expect(Set(access.visibleNotes().map(\.id)) == Set([normal.id] + locked.map(\.id)))
        for note in locked {
            #expect(access.visibleNote(key: NoteToolAccess.key(for: note.id))?.id == note.id)
            #expect(NoteAssistantEntry.isOffered(target: .note(note.id), store: store))
        }
        #expect(!access.entries(folderID: nil, query: "gesperrte").isEmpty)
        #expect(RecipeNoteSource.isOffered(free, store: store))
        #expect(RecipeTranslationModel.isOffered(recipe, store: store))
        #expect(field.canSuggest && !store.isPrivate(morning))
        // Private kinds and folders stay out, locked or not.
        for note in [lockedInJournal, dream] {
            #expect(access.visibleNote(key: NoteToolAccess.key(for: note.id)) == nil, "\(note.kind)")
            #expect(store.isPrivate(note))
        }
        // The session ends: everything is closed again.
        sessionIsOpen = false
        #expect(access.visibleNotes().map(\.id) == [normal.id])
        for note in locked { #expect(access.visibleNote(key: NoteToolAccess.key(for: note.id)) == nil) }
        #expect(!RecipeTranslationModel.isOffered(recipe, store: store) && !field.canSuggest)
    }

    @Test func setLocked_callsHook() throws {
        let note = try #require(store.create(text: "Notiz"))
        var calls = 0
        store.onNoteLocked = { calls += 1 }
        store.setLocked([note.id], true)
        #expect(calls == 1)
        #expect(store.lockedCount == 1)
    }

    @Test func setLocked_unlock_doesNotCallHook() throws {
        let note = try #require(store.create(text: "Notiz"))
        store.setLocked([note.id], true)
        var calls = 0
        store.onNoteLocked = { calls += 1 }
        store.setLocked([note.id], false)
        #expect(calls == 0)
        #expect(store.lockedCount == 0)
        // Locking an already locked note changes nothing and does not end the session again.
        store.setLocked([note.id], true)
        #expect(calls == 1)
        store.setLocked([note.id], true)
        #expect(calls == 1)
    }

    @Test func visibleNote_malformedKey_isNil() throws {
        let (normal, _) = try fill()
        #expect(access.visibleNote(key: normal.id.uuidString) == nil)
        #expect(access.visibleNote(key: "note:") == nil)
        #expect(access.visibleNote(key: "note:kein-uuid") == nil)
        #expect(access.visibleNote(key: "") == nil)
    }

    @Test func key_hasTheFormNoteColonUUID() {
        let id = UUID()
        #expect(NoteToolAccess.key(for: id) == "note:\(id.uuidString)")
    }
}

@MainActor
struct NoteToolAccessFolderNamesTests {
    @Test func privateFolderNames_defaultNamesWithoutFolders() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let access = NoteToolAccess(store: NoteStore(context: container.mainContext))
        #expect(access.privateFolderNames() == ["Tagebuch mit Gott", "Bible Study", "Dream Log"])
    }

    @Test func privateFolderNames_followsRenamedFolders() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = NoteStore(context: container.mainContext)
        store.ensureDefaultFolders()
        _ = store.ensureJournalFolder()
        try store.renameFolder(try #require(store.folder(role: .journal)).id, to: "Gebet")
        let access = NoteToolAccess(store: store)
        #expect(access.privateFolderNames() == ["Gebet", "Bible Study", "Dream Log"])
    }
}
