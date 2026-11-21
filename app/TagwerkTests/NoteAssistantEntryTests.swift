import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The entries of the notes chat (issue #233, mockup NC1c, NC5b): where the assistant button shows and what it opens.
@MainActor
struct NoteAssistantEntryTests {
    let container: ModelContainer
    let store: NoteStore

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        store = NoteStore(context: container.mainContext)
    }

    @Test func isOffered_privateFolderAndTrash_false() throws {
        store.ensureDefaultFolders()
        let journal = store.ensureJournalFolder()
        let bible = store.ensureSystemFolder(.bibleStudy, name: "Bible Study")
        let dream = try #require(store.folder(role: .dreamLog))
        // Guard only: the app cannot create a subfolder below a system folder.
        let sub = NoteFolderRecord(name: "Unterordner", parentID: journal.id, order: 0)
        container.mainContext.insert(sub)
        store.save()
        for id in [journal.id, bible.id, dream.id, sub.id] {
            #expect(!NoteAssistantEntry.isOffered(target: .folder(id), store: store))
        }
        #expect(!NoteAssistantEntry.isOffered(target: .trash, store: store))
        #expect(!NoteAssistantEntry.isOffered(target: .folder(UUID()), store: store))
        #expect(NoteAssistantEntry.Target(scope: .trash) == .trash)
        #expect(NoteAssistantEntry.Target(scope: .folder(journal.id)) == .folder(journal.id))
    }

    @Test func isOffered_privateNote_false() throws {
        let journal = try #require(store.create(text: "Dankbar für Ruhe", kind: .journal, dayKey: "2026-11-18"))
        let bible = try #require(store.create(text: "Römer 8", kind: .bibleStudy))
        let dream = try #require(store.create(text: "Flug", kind: .dream, dayKey: "2026-11-18"))
        let journalFolder = store.ensureJournalFolder()
        let inJournalFolder = try #require(store.create(text: "Im Tagebuch-Ordner", folderID: journalFolder.id))
        let trashed = try #require(store.create(text: "Gelöscht"))
        store.trash(trashed.id)
        for note in [journal, bible, dream, inJournalFolder, trashed] {
            #expect(!NoteAssistantEntry.isOffered(target: .note(note.id), store: store), "\(note.kind)")
        }
        #expect(!NoteAssistantEntry.isOffered(target: .note(UUID()), store: store))
    }

    @Test func isOffered_ownFolder_true() throws {
        store.ensureDefaultFolders()
        let own = try store.createFolder(name: "Reisen")
        let note = try #require(store.create(text: "Packliste", folderID: own.id))
        let brainDump = try #require(store.folder(role: .brainDump))
        #expect(NoteAssistantEntry.isOffered(target: .overview, store: store))
        #expect(NoteAssistantEntry.isOffered(target: .folder(own.id), store: store))
        #expect(NoteAssistantEntry.isOffered(target: .folder(brainDump.id), store: store))
        #expect(NoteAssistantEntry.isOffered(target: .note(note.id), store: store))
        #expect(NoteAssistantEntry.Target(scope: .all) == .overview && NoteAssistantEntry.Target(scope: .standard) == .overview)
    }
}

extension AssistantNotesTests {
    @Test func openNote_setsScopeToThatNote() async throws {
        let rig = await make()
        let note = try #require(rig.notes.create(text: "Umzug Ideen"))
        NoteAssistantEntry.open(.note(note.id), assistant: rig.model)
        #expect(rig.model.isPresented && rig.model.context == .note(note.id))
        #expect(rig.noteTools.scope == note.id)
        let folder = try rig.notes.createFolder(name: "Reisen")
        NoteAssistantEntry.open(.folder(folder.id), assistant: rig.model)
        #expect(rig.model.context == .notes(folderID: folder.id) && rig.noteTools.scope == nil && rig.noteTools.defaultFolderID == folder.id)
        NoteAssistantEntry.open(.overview, assistant: rig.model)
        #expect(rig.model.context == .notes(folderID: nil) && rig.noteTools.defaultFolderID == nil)
    }
}
