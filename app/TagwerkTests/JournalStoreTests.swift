import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The journal on top of the notes store (#182). All texts are invented.
@MainActor
struct JournalStoreTests {
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

    private func entry(_ id: String, _ dayKey: String, text: String = "Tagebuch\n\nText") -> NotionJournalEntry {
        NotionJournalEntry(id: id, title: dayKey, day: NoteDayKey.day(dayKey)!, createdAt: clock.now.addingTimeInterval(-86_400), text: text)
    }

    @Test func openJournalEntry_createsFromTemplateOnceInTheSystemFolder() throws {
        let first = store.openJournalEntry(dayKey: "2026-11-19", locale: german)
        let second = store.openJournalEntry(dayKey: "2026-11-19", locale: german)
        #expect(first.id == second.id && store.count == 1)
        #expect(first.kind == .journal && first.dayKey == "2026-11-19")
        #expect(first.text.hasPrefix("Allgemeine Stimmung"))
        let folder = try #require(store.folder(role: .journal))
        #expect(first.folderID == folder.id && folder.name == "Tagebuch mit Gott")
        #expect(store.notes(.folder(folder.id)).map(\.id) == [first.id])
        #expect(store.journalDayKeys == ["2026-11-19"])
    }

    @Test func untouchedEntry_isRemovedWhenTheEditorCloses_editedOneStays() {
        let untouched = store.openJournalEntry(dayKey: "2026-11-18", locale: german)
        let written = store.openJournalEntry(dayKey: "2026-11-19", locale: german)
        store.updateText(written.id, text: written.text + "Heute war gut.")
        store.deleteIfEmpty(untouched.id)
        store.deleteIfEmpty(written.id)
        #expect(store.note(id: untouched.id) == nil && store.note(id: written.id) != nil)
    }

    @Test func journalEntry_isNotMovableAndNotAThought() throws {
        let note = store.openJournalEntry(dayKey: "2026-11-19", locale: german)
        let other = try store.createFolder(name: "Haus")
        store.move(noteIDs: [note.id], to: other.id)
        #expect(note.folderID == store.folder(role: .journal)?.id)
        #expect(store.notes(.thoughts).isEmpty && !store.hasThoughts)
    }

    @Test func import_createsEntriesDatedLikeNotion() throws {
        let result = store.importJournal([entry("a", "2024-03-16"), entry("b", "2024-03-17")])
        #expect(result == NoteStore.ImportResult(created: 2, appended: 0, skipped: 0))
        let created = try #require(store.journalEntry(dayKey: "2024-03-16"))
        #expect(created.importSourceID == "a" && created.createdAt == clock.now.addingTimeInterval(-86_400))
        #expect(created.folderID == store.folder(role: .journal)?.id)
    }

    @Test func import_twiceCreatesNoDuplicates() {
        let entries = [entry("a", "2024-03-16"), entry("b", "2024-03-17")]
        store.importJournal(entries)
        let again = store.importJournal(entries)
        #expect(again == NoteStore.ImportResult(created: 0, appended: 0, skipped: 2))
        #expect(store.notes(.all).count == 2)
    }

    @Test func import_intoADayWithAnEntry_appendsBelowASeparator() throws {
        let existing = store.openJournalEntry(dayKey: "2024-03-16", locale: german)
        store.updateText(existing.id, text: "Allgemeine Stimmung\n\nMüde.")
        let result = store.importJournal([entry("a", "2024-03-16", text: "Tagebuch\n\nAlt.")])
        #expect(result == NoteStore.ImportResult(created: 0, appended: 1, skipped: 0))
        let text = try #require(store.journalEntry(dayKey: "2024-03-16")).text
        #expect(text == "Allgemeine Stimmung\n\nMüde.\n\n———\nAus Notion importiert\n\nTagebuch\n\nAlt.")
        #expect(store.journalEntry(dayKey: "2024-03-16")?.importSourceID == "a")
        // The appended page counts as imported, too.
        #expect(store.importJournal([entry("a", "2024-03-16")]).skipped == 1)
    }

    @Test func import_intoAnUntouchedTemplate_replacesIt() throws {
        _ = store.openJournalEntry(dayKey: "2024-03-16", locale: german)
        store.importJournal([entry("a", "2024-03-16", text: "Tagebuch\n\nAlt.")])
        #expect(store.journalEntry(dayKey: "2024-03-16")?.text == "Tagebuch\n\nAlt.")
    }

    @Test func import_twoPagesForOneDay_secondIsAppended() throws {
        let result = store.importJournal([entry("a", "2024-03-16", text: "Erst"), entry("b", "2024-03-16", text: "Zweit")])
        #expect(result == NoteStore.ImportResult(created: 1, appended: 1, skipped: 0))
        let record = try #require(store.journalEntry(dayKey: "2024-03-16"))
        #expect(record.importSourceID == "a b" && record.text.contains("Erst") && record.text.hasSuffix("Zweit"))
    }

    @Test func importedIDs_includeTrashedNotes() throws {
        store.importJournal([entry("a", "2024-03-16")])
        let note = try #require(store.journalEntry(dayKey: "2024-03-16"))
        store.trash(note.id)
        #expect(store.importedSourceIDs == ["a"])
        #expect(store.importJournal([entry("a", "2024-03-16")]).skipped == 1)
    }

    @Test func trashedEntry_doesNotBlockANewOneForTheDay() {
        let first = store.openJournalEntry(dayKey: "2026-11-19", locale: german)
        store.trash(first.id)
        let second = store.openJournalEntry(dayKey: "2026-11-19", locale: german)
        #expect(second.id != first.id)
    }

    @Test func journalIsFoundByTheGlobalSearchSource() {
        let note = store.openJournalEntry(dayKey: "2026-11-19", locale: german)
        store.updateText(note.id, text: "Allgemeine Stimmung\n\nDankbar")
        // The in-app search is local, so the journal is shown there (the privacy rule concerns what leaves the device).
        #expect(store.notes(.all).contains { $0.id == note.id })
    }
}
