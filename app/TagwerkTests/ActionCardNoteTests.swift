import AIKit
import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// Cards of `create_note`, `update_note` and `delete_note` (issue #233, mockup NC2b): what changes, and the proposal as raw values.
@MainActor
struct ActionCardNoteTests {
    let container: ModelContainer
    let store: NoteStore
    let settings: AppSettings
    let calendar = testCalendar()
    let describer: ActionCardDescriber

    init() async throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        store = NoteStore(context: container.mainContext)
        let taskList = TaskListModel(providers: [FakeTaskProvider(source: .local, tasks: [])], now: testNow, calendar: calendar)
        await taskList.reload()
        let planStore = PlanStore(context: container.mainContext)
        let calendarStore = FakeCalendarStore()
        let blocks = BlockPlanner(store: calendarStore, planStore: planStore, links: EventLinkStore(context: container.mainContext),
                                  settings: settings, calendar: calendar)
        let planning = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: FakeAccessStore(),
                                     planStore: planStore, efforts: RecurringEffortStore(context: container.mainContext),
                                     blocks: blocks, settings: settings, marks: EventMarkStore(context: container.mainContext),
                                     now: testNow, calendar: calendar)
        await planning.reload()
        var describer = ActionCardDescriber(planning: planning)
        describer.noteAccess = NoteToolAccess(store: store)
        self.describer = describer
    }

    private func call(_ name: String, _ arguments: [String: Any]) throws -> ToolCall {
        ToolCall(id: "c", name: name, arguments: try JSONSerialization.data(withJSONObject: arguments))
    }

    @Test func describe_updateNote_summarisesAndCarriesBeforeAfter() throws {
        let note = try #require(store.create(text: "Umzug\n- Kartons\n- Tape\n- Karte"))
        let new = "Umzug planen\n- Kartons\n- Tape\n- Lampen\n- Kabel"
        let card = describer.describe(try call("update_note", ["note_id": NoteToolAccess.key(for: note.id), "text": new]))
        #expect(card.title == "Notiz „Umzug“ überarbeiten")
        #expect(card.change == "3 Zeilen neu · 2 entfernt · Titel geändert")
        #expect(card.detail == .update(title: "Umzug", before: note.text, after: new))
        #expect(card.confirmTitle == nil && !card.isDestructive)
        // Spoken: no dot between the parts.
        let spoken = describer.describe(try call("update_note", ["note_id": NoteToolAccess.key(for: note.id), "text": new]), spoken: true)
        #expect(spoken.change == "3 Zeilen neu, 2 entfernt, Titel geändert")
        // Only the parts that apply.
        let small = describer.describe(try call("update_note", ["note_id": NoteToolAccess.key(for: note.id), "text": note.text + "\n- Folie"]))
        #expect(small.change == "1 Zeile neu")
        #expect(!small.change.contains("Titel"))
    }

    @Test func describe_createNote_namesFolderAndLines() throws {
        store.ensureDefaultFolders()
        let folder = try #require(store.folder(role: .brainDump))
        let card = describer.describe(try call("create_note", ["text": "Geschenk Mama\nBlumen\nKarte", "folder_id": NoteToolAccess.folderKey(for: folder.id)]))
        #expect(card.title == "Neue Notiz „Geschenk Mama“")
        #expect(card.change == "Ordner „Brain Dump“ · 3 Zeilen")
        #expect(card.confirmTitle == "Anlegen" && !card.isDestructive)
        #expect(card.detail == .create(text: "Geschenk Mama\nBlumen\nKarte"))
        // Without a folder: "Notizen", or the folder of the chat.
        let plain = describer.describe(try call("create_note", ["text": "Lose Idee", "folder_id": NSNull()]))
        #expect(plain.change == "Ordner „Notizen“ · 1 Zeile")
        var inFolder = describer
        inFolder.noteDefaultFolderID = { folder.id }
        #expect(inFolder.describe(try call("create_note", ["text": "Idee", "folder_id": NSNull()])).change.hasPrefix("Ordner „Brain Dump“"))
    }

    @Test func describe_deleteNote_mentionsTrash() throws {
        let note = try #require(store.create(text: "Doppelte Notiz\nText"))
        let card = describer.describe(try call("delete_note", ["note_id": NoteToolAccess.key(for: note.id), "reason": "Steht auch in „Umzug“"]))
        #expect(card.title == "Notiz „Doppelte Notiz“ löschen")
        #expect(card.change == "Grund: Steht auch in „Umzug“\nKommt nach „Zuletzt gelöscht“ und bleibt dort 30 Tage wiederherstellbar.")
        #expect(card.confirmTitle == "Löschen" && card.isDestructive)
        #expect(card.detail == .delete(text: note.text))
        #expect(card.doneNote == "In „Zuletzt gelöscht“")
        let noReason = describer.describe(try call("delete_note", ["note_id": NoteToolAccess.key(for: note.id), "reason": NSNull()]))
        #expect(noReason.change == "Kommt nach „Zuletzt gelöscht“ und bleibt dort 30 Tage wiederherstellbar.")
    }

    @Test func describe_storedForm_hasNoDetail() throws {
        let note = try #require(store.create(text: "Plan\nMontag"))
        let update = describer.describe(try call("update_note", ["note_id": NoteToolAccess.key(for: note.id), "title": "Wochenplan"]))
        #expect(update.detail == nil && update.title == "Notiz „Plan“ überarbeiten")
        // A note that is not visible any more: the title comes from the arguments.
        store.trash(note.id)
        let gone = describer.describe(try call("update_note", ["note_id": NoteToolAccess.key(for: note.id), "title": "Wochenplan"]))
        #expect(gone.detail == nil)
        let created = describer.describe(try call("create_note", ["title": "Geschenk Mama", "folder_id": NSNull()]))
        #expect(created.title == "Neue Notiz „Geschenk Mama“" && created.detail == nil)
        // A card that was answered carries no detail and no summary.
        var closed = describer
        closed.isOpen = false
        let fresh = try #require(store.create(text: "Frisch\nZeile"))
        let done = closed.describe(try call("update_note", ["note_id": NoteToolAccess.key(for: fresh.id), "text": "Frisch\nZeile\nNeu"]))
        #expect(done.detail == nil && done.change == "Text überarbeitet")
        let deleted = closed.describe(try call("delete_note", ["note_id": NoteToolAccess.key(for: fresh.id), "reason": NSNull()]))
        #expect(deleted.detail == nil)
    }

    @Test func describe_trashedNote_keepsItsTitleOnTheDoneCard() throws {
        let note = try #require(store.create(text: "Weg damit\nText"))
        store.trash(note.id)
        var closed = describer
        closed.isOpen = false
        #expect(closed.describe(try call("delete_note", ["note_id": NoteToolAccess.key(for: note.id), "reason": NSNull()])).title == "Notiz „Weg damit“ löschen")
    }

    @Test func describe_privateNote_showsNoTitleOrText() throws {
        let journal = try #require(store.create(text: "Dankbar für Ruhe", kind: .journal, dayKey: "2026-11-18"))
        let card = describer.describe(try call("update_note", ["note_id": NoteToolAccess.key(for: journal.id), "text": "Anders"]))
        #expect(card.detail == nil && !card.title.contains("Dankbar"))
        let delete = describer.describe(try call("delete_note", ["note_id": NoteToolAccess.key(for: journal.id), "reason": NSNull()]))
        #expect(delete.detail == nil && !delete.title.contains("Dankbar"))
    }
}
