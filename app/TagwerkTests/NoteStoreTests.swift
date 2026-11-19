import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

extension NoteStore {
    /// Test helper: the live morning and evening notes.
    func thoughtNotes() -> [NoteRecord] { notes().filter { $0.kind == .morning || $0.kind == .evening } }
}

@MainActor
struct NoteStoreTests {
    final class Clock { var now = testNow() }
    let container: ModelContainer
    let clock = Clock()
    let store: NoteStore

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        let clock = self.clock
        store = NoteStore(context: container.mainContext, now: { clock.now })
    }

    private func advance(_ seconds: TimeInterval = 60) { clock.now = clock.now.addingTimeInterval(seconds) }

    @Test func create_trims_andIgnoresEmpty() throws {
        #expect(store.create(text: "  \n ") == nil)
        #expect(store.count == 0)
        let note = try #require(store.create(text: " a "))
        #expect(note.text == "a" && note.kindRaw == "free" && note.dayKey == nil && !note.wasDictated && !note.isPinned)
        #expect(note.createdAt == clock.now && note.updatedAt == clock.now && note.processedAt == nil)
        #expect(store.count == 1 && store.note(id: note.id)?.text == "a")
        #expect(store.create(text: "diktiert", wasDictated: true)?.wasDictated == true)
    }

    @Test func notes_pinnedFirst_thenByUpdatedAtDescending() throws {
        let a = try #require(store.create(text: "a")); advance()
        let b = try #require(store.create(text: "b")); advance()
        let c = try #require(store.create(text: "c"))
        #expect(store.notes().map(\.text) == ["c", "b", "a"])
        store.setPinned(a.id, true)
        #expect(store.notes().map(\.text) == ["a", "c", "b"])
        #expect(store.latest?.id == c.id)
        _ = b
    }

    @Test func updateText_changesUpdatedAtOnlyForNewText() throws {
        let note = try #require(store.create(text: "a"))
        let created = note.updatedAt
        advance()
        store.updateText(note.id, text: "a")
        #expect(note.updatedAt == created)
        store.updateText(note.id, text: "b")
        #expect(note.text == "b" && note.updatedAt == clock.now && note.createdAt == created)
    }

    @Test func setPinned_keepsUpdatedAt() throws {
        let note = try #require(store.create(text: "a"))
        let created = note.updatedAt
        advance()
        store.setPinned(note.id, true)
        #expect(note.isPinned && note.updatedAt == created)
    }

    @Test func filter_ownAndAll() throws {
        #expect(store.thoughtNotes().isEmpty)
        let a = try #require(store.create(text: "a")); advance()
        let b = try #require(store.create(text: "b", kind: .morning, dayKey: "2026-11-18")); advance()
        let c = try #require(store.create(text: "c", kind: .evening, dayKey: "2026-11-18"))
        #expect(store.thoughtNotes().map(\.id) == [c.id, b.id])
        #expect(store.notes(.own).map(\.id) == [a.id])
        #expect(store.notes(.all).count == 3)
        #expect(!store.thoughtNotes().isEmpty)
        #expect(store.note(kind: .morning, dayKey: "2026-11-18")?.id == b.id)
        #expect(store.note(kind: .morning, dayKey: "2026-11-19") == nil)
    }

    @Test func create_thoughtForSameKindAndDay_updatesExisting() throws {
        let first = try #require(store.create(text: "erst", kind: .evening, dayKey: "2026-11-18"))
        advance()
        let second = try #require(store.create(text: "dann", kind: .evening, dayKey: "2026-11-18"))
        #expect(store.count == 1 && first.id == second.id && second.text == "dann" && second.updatedAt == clock.now)
        _ = store.create(text: "anderer Tag", kind: .evening, dayKey: "2026-11-19")
        _ = store.create(text: "andere Art", kind: .morning, dayKey: "2026-11-18")
        #expect(store.count == 3)
    }

    @Test func markProcessed_andDelete() throws {
        let note = try #require(store.create(text: "a"))
        store.markProcessed(note.id, at: clock.now)
        #expect(note.processedAt == clock.now)
        store.delete(note.id)
        #expect(store.count == 0 && store.note(id: note.id) == nil)
    }

    @Test func deleteIfEmpty_removesOnlyEmptyNotes() throws {
        let kept = try #require(store.create(text: "a"))
        let emptied = try #require(store.create(text: "b"))
        store.updateText(emptied.id, text: "  \n")
        store.deleteIfEmpty(kept.id)
        store.deleteIfEmpty(emptied.id)
        #expect(store.notes().map(\.id) == [kept.id])
    }

    @Test func unknownKindRaw_readsAsFree() throws {
        let note = try #require(store.create(text: "a"))
        note.kindRaw = "weekly"
        #expect(note.kind == .free)
        #expect(store.notes(.own).count == 1 && store.thoughtNotes().isEmpty)
    }

    @Test func writes_bumpRevision() throws {
        let before = store.revision
        let note = try #require(store.create(text: "a"))
        store.setPinned(note.id, true)
        #expect(store.revision == before + 2)
    }

    @Test func schema_containsNoteRecord() {
        #expect(ModelContainerFactory.schema.entities.contains { $0.name == "NoteRecord" })
    }

    // MARK: Folders and trash (#152)

    @Test func createFolder_ordersTrimsAndValidates() throws {
        let first = try store.createFolder(name: " Arbeit ")
        let second = try store.createFolder(name: "Haus")
        #expect(first.name == "Arbeit" && first.order == 0 && second.order == 1)
        #expect(throws: NoteFolderRules.NameError.duplicate) { try store.createFolder(name: "arbeit") }
        #expect(throws: NoteFolderRules.NameError.empty) { try store.createFolder(name: "  ") }
        let child = try store.createFolder(name: "Arbeit", parentID: first.id)
        #expect(child.parentID == first.id)
        #expect(store.folderTree().map(\.folder.name) == ["Arbeit", "Haus"])
    }

    @Test func createFolder_stopsAtThirdLevel() throws {
        let one = try store.createFolder(name: "1")
        let two = try store.createFolder(name: "2", parentID: one.id)
        let three = try store.createFolder(name: "3", parentID: two.id)
        #expect(throws: NoteFolderRules.MoveError.tooDeep) { try store.createFolder(name: "4", parentID: three.id) }
    }

    @Test func renameAndMoveFolder() throws {
        let work = try store.createFolder(name: "Arbeit")
        let home = try store.createFolder(name: "Haus")
        try store.renameFolder(home.id, to: "Zuhause")
        #expect(store.folder(id: home.id)?.name == "Zuhause")
        try store.moveFolder(home.id, to: work.id)
        #expect(store.folder(id: home.id)?.parentID == work.id)
        #expect(throws: NoteFolderRules.MoveError.cycle) { try store.moveFolder(work.id, to: home.id) }
        // A name that exists on the new level blocks the move.
        _ = try store.createFolder(name: "Zuhause")
        #expect(throws: NoteFolderRules.NameError.duplicate) { try store.moveFolder(home.id, to: nil) }
    }

    @Test func create_inFolder_andMoveNotes() throws {
        let folder = try store.createFolder(name: "Ideen")
        let inside = try #require(store.create(text: "drin", folderID: folder.id))
        let loose = try #require(store.create(text: "lose"))
        let thought = try #require(store.create(text: "Gedanke", kind: .evening, dayKey: "2026-11-18", folderID: folder.id))
        // A thought note lands in the fixed folder of its kind, whatever folder was passed.
        #expect(thought.folderID == store.folder(role: .eveningRoutine)?.id)
        #expect(store.notes(.folder(folder.id)).map(\.id) == [inside.id])
        #expect(store.notes(.own).map(\.id) == [loose.id])
        store.move(noteIDs: [loose.id, thought.id], to: folder.id)
        #expect(Set(store.notes(.folder(folder.id)).map(\.id)) == [inside.id, loose.id])
        #expect(thought.folderID == store.folder(role: .eveningRoutine)?.id)
        store.move(noteIDs: [loose.id], to: nil)
        #expect(store.notes(.own).map(\.id) == [loose.id])
        // An unknown folder leaves the note where it is.
        store.move(noteIDs: [loose.id], to: UUID())
        #expect(loose.folderID == nil)
    }

    @Test func counts_includeSubfolders() throws {
        let work = try store.createFolder(name: "Arbeit")
        let plans = try store.createFolder(name: "Pläne", parentID: work.id)
        _ = store.create(text: "a", folderID: work.id)
        _ = store.create(text: "b", folderID: plans.id)
        let trashed = try #require(store.create(text: "c", folderID: plans.id))
        store.trash(trashed.id)
        let counts = store.folderCounts()
        #expect(counts[work.id] == 2 && counts[plans.id] == 1)
    }

    @Test func trash_hidesNote_restoreKeepsFolder() throws {
        let folder = try store.createFolder(name: "Ideen")
        let note = try #require(store.create(text: "a", folderID: folder.id))
        store.setPinned(note.id, true)
        store.trash(note.id)
        #expect(store.notes().isEmpty && store.count == 0 && store.trashedCount == 1)
        #expect(store.notes(.trash).map(\.id) == [note.id] && note.deletedAt == clock.now && !note.isPinned)
        #expect(store.notes(.folder(folder.id)).isEmpty && store.latest == nil)
        store.restore(note.id)
        #expect(note.deletedAt == nil && note.folderID == folder.id && store.count == 1)
    }

    @Test func restore_withoutOldFolder_landsInStandardFolder() throws {
        let folder = try store.createFolder(name: "Ideen")
        let note = try #require(store.create(text: "a", folderID: folder.id))
        store.trash(note.id)
        try store.deleteFolder(folder.id)
        store.restore(note.id)
        #expect(note.folderID == nil && store.notes(.own).map(\.id) == [note.id])
    }

    @Test func deleteFolder_sendsNotesOfSubtreeToTrash() throws {
        let work = try store.createFolder(name: "Arbeit")
        let plans = try store.createFolder(name: "Pläne", parentID: work.id)
        let other = try store.createFolder(name: "Haus")
        let a = try #require(store.create(text: "a", folderID: work.id))
        let b = try #require(store.create(text: "b", folderID: plans.id))
        let c = try #require(store.create(text: "c", folderID: other.id))
        #expect(store.notesAffectedByDeleting(folder: work.id) == 2)
        try store.deleteFolder(work.id)
        #expect(store.folder(id: work.id) == nil && store.folder(id: plans.id) == nil && store.folder(id: other.id) != nil)
        #expect(Set(store.notes(.trash).map(\.id)) == [a.id, b.id])
        #expect(store.notes(.folder(other.id)).map(\.id) == [c.id])
    }

    @Test func systemFolder_cannotBeDeletedOrMoved() throws {
        let system = store.ensureSystemFolder(.journal, name: "Tagebuch mit Gott")
        #expect(store.ensureSystemFolder(.journal, name: "Anders").id == system.id)
        #expect(throws: NoteFolderRules.MoveError.systemFolder) { try store.deleteFolder(system.id) }
        let other = try store.createFolder(name: "Haus")
        #expect(throws: NoteFolderRules.MoveError.systemFolder) { try store.moveFolder(system.id, to: other.id) }
        #expect(throws: NoteFolderRules.MoveError.tooDeep) { try store.createFolder(name: "Unter", parentID: system.id) }
        try store.renameFolder(system.id, to: "Mein Tagebuch")
        #expect(store.folder(role: .journal)?.name == "Mein Tagebuch")
    }

    // MARK: Fixed folders (P5)

    @Test func ensureDefaultFolders_createsFourFoldersOnce() {
        store.ensureDefaultFolders()
        store.ensureDefaultFolders()
        let roles = store.folders().compactMap(\.role)
        #expect(roles.count == 4 && Set(roles) == [.brainDump, .morningRoutine, .eveningRoutine, .dreamLog])
        #expect(store.folder(role: .brainDump)?.name == "Brain Dump")
        #expect(store.folder(role: .morningRoutine)?.name == "Tagesstart")
        #expect(store.folder(role: .eveningRoutine)?.name == "Tagesabschluss")
        #expect(store.folder(role: .dreamLog)?.name == "Dream Log")
        let orders = NoteStore.defaultFolderRoles.compactMap { store.folder(role: $0)?.order }
        #expect(orders == orders.sorted() && Set(orders).count == 4)
    }

    @Test func ensureDefaultFolders_keepsRenamedFolder() throws {
        store.ensureDefaultFolders()
        let id = try #require(store.folder(role: .brainDump)?.id)
        try store.renameFolder(id, to: "Kopf leeren")
        store.ensureDefaultFolders()
        #expect(store.folder(role: .brainDump)?.name == "Kopf leeren" && store.folders().count == 4)
    }

    @Test func ensureDefaultFolders_withoutChanges_doesNotWrite() {
        store.ensureDefaultFolders()
        let revision = store.revision
        store.ensureDefaultFolders()
        #expect(store.revision == revision)
    }

    /// Notes written before the fixed folders existed (or restored without them) have no folder yet.
    private func legacyNote(kind: NoteKind, dayKey: String, text: String, folderID: UUID? = nil) -> NoteRecord {
        let record = NoteRecord(text: text, kind: kind, dayKey: dayKey, now: clock.now)
        record.folderID = folderID
        container.mainContext.insert(record)
        store.save()
        return record
    }

    @Test func sortRoutineNotes_movesExistingThoughtNotesIntoTheirFolders() {
        let morning = legacyNote(kind: .morning, dayKey: "2026-11-18", text: "m")
        let evening = legacyNote(kind: .evening, dayKey: "2026-11-18", text: "e")
        let dream = legacyNote(kind: .dream, dayKey: "2026-11-18", text: "d")
        store.ensureDefaultFolders()
        #expect(morning.folderID == store.folder(role: .morningRoutine)?.id)
        #expect(evening.folderID == store.folder(role: .eveningRoutine)?.id)
        #expect(dream.folderID == store.folder(role: .dreamLog)?.id)
    }

    @Test func sortRoutineNotes_repairsDanglingFolderID_andCoversTheTrash() {
        let dangling = legacyNote(kind: .morning, dayKey: "2026-11-18", text: "m", folderID: UUID())
        let trashed = legacyNote(kind: .evening, dayKey: "2026-11-17", text: "e")
        store.trash(trashed.id)
        store.ensureDefaultFolders()
        #expect(dangling.folderID == store.folder(role: .morningRoutine)?.id)
        #expect(trashed.folderID == store.folder(role: .eveningRoutine)?.id && trashed.deletedAt != nil)
    }

    @Test func sortRoutineNotes_leavesFreeJournalAndBibleStudyNotesAlone() throws {
        let work = try store.createFolder(name: "Arbeit")
        let free = try #require(store.create(text: "frei", folderID: work.id))
        let loose = try #require(store.create(text: "lose"))
        let journal = try #require(store.create(text: "Eintrag", kind: .journal, dayKey: "2026-11-18"))
        let bible = try #require(store.create(text: "Studie", kind: .bibleStudy, dayKey: "2026-11-18", folderID: work.id))
        let journalFolder = journal.folderID
        store.ensureDefaultFolders()
        #expect(free.folderID == work.id && loose.folderID == nil && bible.folderID == work.id)
        #expect(journal.folderID == journalFolder)
    }

    @Test func saveThought_landsInTheRoutineFolder() throws {
        let morning = try #require(store.saveThought("Gedanke", kind: .morning, dayKey: "2026-11-18", wasDictated: false))
        let dream = try #require(store.saveThought("Traum", kind: .dream, dayKey: "2026-11-18", wasDictated: false))
        #expect(morning.folderID == store.folder(role: .morningRoutine)?.id)
        #expect(dream.folderID == store.folder(role: .dreamLog)?.id)
        #expect(store.notes(.folder(try #require(store.folder(role: .morningRoutine)?.id))).map(\.id) == [morning.id])
    }

    @Test func move_intoRoutineFolders_isRefused() throws {
        store.ensureDefaultFolders()
        let note = try #require(store.create(text: "frei"))
        for role in [NoteFolderRole.morningRoutine, .eveningRoutine, .dreamLog] {
            store.move(noteIDs: [note.id], to: store.folder(role: role)?.id)
            #expect(note.folderID == nil, "moved into \(role)")
        }
    }

    @Test func move_intoBrainDump_works() throws {
        store.ensureDefaultFolders()
        let note = try #require(store.create(text: "frei"))
        let brainDump = try #require(store.folder(role: .brainDump))
        store.move(noteIDs: [note.id], to: brainDump.id)
        #expect(note.folderID == brainDump.id && store.notes(.folder(brainDump.id)).map(\.id) == [note.id])
    }

    @Test func deleteFolder_fixedFolders_throwSystemFolder() throws {
        store.ensureDefaultFolders()
        for role in NoteStore.defaultFolderRoles {
            let id = try #require(store.folder(role: role)?.id)
            #expect(throws: NoteFolderRules.MoveError.systemFolder) { try store.deleteFolder(id) }
        }
    }

    @Test func purgeExpired_removesNotesAfterThirtyDays() throws {
        let calendar = testCalendar()
        let old = try #require(store.create(text: "alt"))
        let recent = try #require(store.create(text: "neu"))
        store.trash(old.id)
        clock.now = calendar.date(byAdding: .day, value: 20, to: clock.now)!
        store.trash(recent.id)
        clock.now = calendar.date(byAdding: .day, value: 11, to: clock.now)!
        #expect(store.purgeExpired(calendar: calendar) == 1)
        #expect(store.note(id: old.id) == nil && store.note(id: recent.id) != nil)
        #expect(store.purgeExpired(calendar: calendar) == 0)
    }

    @Test func emptyTrash_removesOnlyTrashedNotes() throws {
        let kept = try #require(store.create(text: "bleibt"))
        let gone = try #require(store.create(text: "weg"))
        store.trash(gone.id)
        store.emptyTrash()
        #expect(store.trashedCount == 0 && store.notes().map(\.id) == [kept.id])
    }

    @Test func trashedThought_doesNotBlockANewOneForTheSameDay() throws {
        let first = try #require(store.create(text: "erst", kind: .evening, dayKey: "2026-11-18"))
        store.trash(first.id)
        #expect(store.note(kind: .evening, dayKey: "2026-11-18") == nil)
        let second = try #require(store.create(text: "neu", kind: .evening, dayKey: "2026-11-18"))
        #expect(second.id != first.id && store.thoughtNotes().map(\.id) == [second.id])
    }

    @Test func sorting_byCreatedAndTitle() throws {
        let b = try #require(store.create(text: "Banane")); advance()
        let a = try #require(store.create(text: "Apfel")); advance()
        store.updateText(b.id, text: "Banane 2")
        #expect(store.notes(sortedBy: .modified).map(\.id) == [b.id, a.id])
        #expect(store.notes(sortedBy: .created).map(\.id) == [a.id, b.id])
        #expect(store.notes(sortedBy: .title).map(\.id) == [a.id, b.id])
        store.setPinned(b.id, true)
        #expect(store.notes(sortedBy: .created).map(\.id) == [b.id, a.id])
    }

    @Test func schema_containsNoteFolderRecord() {
        #expect(ModelContainerFactory.schema.entities.contains { $0.name == "NoteFolderRecord" })
    }
}
