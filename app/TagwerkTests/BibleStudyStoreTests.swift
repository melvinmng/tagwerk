import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// Bible Study notes, sessions and the import (#186). All texts are invented.
@MainActor
struct BibleStudyStoreTests {
    final class Clock { var now = testNow() }
    let container: ModelContainer
    let clock = Clock()
    let store: NoteStore
    let german = Locale(identifier: "de_DE")

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        let clock = self.clock
        store = NoteStore(context: container.mainContext, now: { clock.now })
    }

    private var romans: BibleBook { BibleBooks.book(number: 45)! }
    private var john: BibleBook { BibleBooks.book(number: 43)! }

    @Test func openBibleNote_createsOnePerBookInTheSystemFolder() throws {
        let first = store.openBibleNote(book: romans, locale: german)
        let again = store.openBibleNote(book: romans, locale: german)
        let other = store.openBibleNote(book: john, locale: german)
        #expect(first.id == again.id && first.id != other.id)
        #expect(first.kind == .bibleStudy && first.bookKey == "45" && first.text.hasPrefix("Römer\n"))
        let folder = try #require(store.folder(role: .bibleStudy))
        #expect(folder.name == "Bible Study" && first.folderID == folder.id)
        #expect(store.bibleNote(bookKey: "43")?.id == other.id)
    }

    @Test func startSession_appendsADatedSectionAndRecordsTheSession() throws {
        let started = store.startSession(book: romans, passage: " 3,21-31 ", dayKey: "2026-11-19", dateText: "19.11.2026", locale: german)
        #expect(started.note.text.hasSuffix("Notizen\n\n19.11.2026 · 3,21-31\n\n"))
        #expect(started.session.passage == "3,21-31" && started.session.book == "45" && started.session.noteID == started.note.id)
        #expect(started.session.completedAt == nil && store.openSession(noteID: started.note.id)?.id == started.session.id)
        #expect(store.lastBookKey == "45")
        // A second session the same day adds a second section to the same note.
        let second = store.startSession(book: romans, passage: "4,1-8", dayKey: "2026-11-19", dateText: "19.11.2026", locale: german)
        #expect(second.note.id == started.note.id && second.note.text.contains("4,1-8") && store.sessions().count == 2)
    }

    @Test func completeSession_setsTheDateOnce() throws {
        let started = store.startSession(book: john, passage: "1,1-5", dayKey: "2026-11-19", dateText: "19.11.2026", locale: german)
        clock.now = clock.now.addingTimeInterval(600)
        store.completeSession(started.session.id)
        let completed = try #require(started.session.completedAt)
        #expect(completed == clock.now && store.openSession(noteID: started.note.id) == nil)
        clock.now = clock.now.addingTimeInterval(600)
        store.completeSession(started.session.id)
        #expect(started.session.completedAt == completed)
    }

    @Test func completedSessionDays_ignoreOpenSessionsAndOtherDays() {
        let done = store.startSession(book: romans, passage: "1", dayKey: "2026-11-18", dateText: "18.11.2026", locale: german)
        store.completeSession(done.session.id)
        _ = store.startSession(book: romans, passage: "2", dayKey: "2026-11-19", dateText: "19.11.2026", locale: german)
        let range = PlanDay(year: 2026, month: 11, day: 1)...PlanDay(year: 2026, month: 11, day: 30)
        #expect(store.completedSessionDays(in: range) == [PlanDay(year: 2026, month: 11, day: 18)])
        #expect(store.completedSessionDays(in: PlanDay(year: 2026, month: 11, day: 19)...PlanDay(year: 2026, month: 11, day: 20)).isEmpty)
    }

    @Test func lastBookKey_isNilWithoutSessions() {
        #expect(store.lastBookKey == nil)
    }

    @Test func import_createsANotePerBook_andSkipsRepeats() throws {
        let pages = [NotionBibleNote(id: "a", title: "Römer", text: "Generelle Gedanken\n\nGnade."),
                     NotionBibleNote(id: "b", title: "1. Korinther", text: "Notizen\n\nLiebe."),
                     NotionBibleNote(id: "c", title: "Kochbuch", text: "x")]
        let result = store.importBibleNotes(pages)
        #expect(result == NoteStore.BibleImportResult(created: 2, appended: 0, skipped: 0, unmatched: ["Kochbuch"]))
        let note = try #require(store.bibleNote(bookKey: "45"))
        #expect(note.text == "Römer\n\nGenerelle Gedanken\n\nGnade." && note.importSourceID == "a")
        #expect(NoteText.title(note.text) == "Römer")
        let again = store.importBibleNotes(pages)
        #expect(again.created == 0 && again.skipped == 2 && again.unmatched == ["Kochbuch"])
        #expect(store.sessions().isEmpty)
    }

    @Test func import_intoAnExistingBookNote_appendsBelowASeparator() throws {
        let note = store.openBibleNote(book: romans, locale: german)
        let result = store.importBibleNotes([NotionBibleNote(id: "a", title: "Römer", text: "Notizen\n\nAlt.")])
        #expect(result.appended == 1 && result.created == 0)
        #expect(note.text.contains("———\nAus Notion importiert\n\nNotizen\n\nAlt."))
        #expect(note.importSourceID == "a")
    }

    @Test func bibleNotes_areNeitherMovableNorThoughts() throws {
        let note = store.openBibleNote(book: romans, locale: german)
        let folder = try store.createFolder(name: "Haus")
        store.move(noteIDs: [note.id], to: folder.id)
        #expect(note.folderID == store.folder(role: .bibleStudy)?.id && !store.hasThoughts)
    }
}
