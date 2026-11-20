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
