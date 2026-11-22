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

    // MARK: Passages as numbers (BS2)

    private func reference(_ chapter: Int, _ verse: Int) -> BibleReference { BibleReference(chapter: chapter, verse: verse) }

    @Test func startSession_withPassage_storesNumbersAndWritesTheOpenHeading() {
        let started = store.startSession(book: romans, passage: BiblePassage(start: reference(3, 21)), dayKey: "2026-11-19",
                                         dateText: "19.11.2026", locale: german)
        #expect(started.note.text.hasSuffix("Notizen\n\n19.11.2026 · 3,21–\n\n"))
        let session = started.session
        #expect(session.passage == "3,21–" && session.startChapter == 3 && session.startVerse == 21)
        #expect(session.endChapter == 0 && session.endVerse == 0)
        #expect(session.resolvedPassage == BiblePassage(start: reference(3, 21)))
    }

    @Test func startSession_withChosenEnd_storesTheEnd() {
        let passage = BiblePassage(start: reference(3, 21), end: reference(3, 26))
        let started = store.startSession(book: romans, passage: passage, dayKey: "2026-11-19", dateText: "19.11.2026", locale: german)
        #expect(started.note.text.hasSuffix("19.11.2026 · 3,21–26\n\n") && started.session.passage == "3,21–26")
        #expect(started.session.endChapter == 3 && started.session.endVerse == 26)
    }

    @Test func startSession_passageOutsideTheTable_isFreeText() {
        let outside = BiblePassage(start: reference(BibleVerseCounts.chapterCount(book: 45) + 1, 1))
        let started = store.startSession(book: romans, passage: outside, freeText: " Kap. 99 ", dayKey: "2026-11-19",
                                         dateText: "19.11.2026", locale: german)
        #expect(started.session.passage == "Kap. 99" && started.session.startChapter == 0 && started.session.resolvedPassage == nil)
        #expect(started.note.text.hasSuffix("19.11.2026 · Kap. 99\n\n"))
    }

    @Test func startSession_freeText_keepsTheTextWithoutNumbers() {
        let started = store.startSession(book: romans, passage: nil, freeText: "Anfang des Briefs", dayKey: "2026-11-19",
                                         dateText: "19.11.2026", locale: german)
        #expect(started.session.passage == "Anfang des Briefs" && started.session.startChapter == 0)
        let bare = store.startSession(book: romans, passage: nil, dayKey: "2026-11-19", dateText: "19.11.2026", locale: german)
        #expect(bare.session.passage.isEmpty && bare.note.text.hasSuffix("19.11.2026\n\n"))
    }

    @Test func lastSession_perBook() throws {
        #expect(store.lastSession(bookKey: "45") == nil)
        let first = store.startSession(book: romans, passage: BiblePassage(start: reference(1, 1)), dayKey: "2026-11-17", dateText: "17.11.2026", locale: german)
        clock.now = clock.now.addingTimeInterval(86_400)
        let other = store.startSession(book: john, passage: BiblePassage(start: reference(1, 1)), dayKey: "2026-11-18", dateText: "18.11.2026", locale: german)
        clock.now = clock.now.addingTimeInterval(86_400)
        let latest = store.startSession(book: romans, passage: BiblePassage(start: reference(2, 1)), dayKey: "2026-11-19", dateText: "19.11.2026", locale: german)
        #expect(store.lastSession(bookKey: "45")?.id == latest.session.id, "the latest by start counts, open or not")
        #expect(store.lastSession(bookKey: "43")?.id == other.session.id)
        store.completeSession(first.session.id)
        #expect(store.lastSession(bookKey: "45")?.id == latest.session.id, "completing an older session changes nothing")
    }

    @Test func recentBookKeys_distinctNewestFirst() {
        let genesis = BibleBooks.book(number: 1)!
        for (book, dayOffset) in [(romans, 0), (john, 1), (romans, 2), (genesis, 3), (john, 4)] {
            clock.now = testNow().addingTimeInterval(Double(dayOffset) * 86_400)
            _ = store.startSession(book: book, passage: nil, freeText: "x", dayKey: "2026-11-1\(dayOffset)", dateText: "d", locale: german)
        }
        #expect(store.recentBookKeys() == ["43", "1", "45"])
        #expect(store.recentBookKeys(limit: 2) == ["43", "1"])
        #expect(store.recentBookKeys(limit: 10) == ["43", "1", "45"])
    }

    @Test func completeSession_storesEndAndCompletesHeading() throws {
        let started = store.startSession(book: romans, passage: BiblePassage(start: reference(3, 21)), dayKey: "2026-11-19",
                                         dateText: "19.11.2026", locale: german)
        store.updateText(started.note.id, text: started.note.text + "Gerechtigkeit ohne Gesetz.\n")
        clock.now = clock.now.addingTimeInterval(600)
        store.completeSession(started.session.id, end: reference(3, 26))
        let session = started.session
        #expect(session.completedAt == clock.now && session.endChapter == 3 && session.endVerse == 26 && session.passage == "3,21–26")
        #expect(started.note.text.contains("\n19.11.2026 · 3,21–26\n\nGerechtigkeit ohne Gesetz.\n"))
        #expect(!started.note.text.contains("3,21–\n"))
        #expect(started.note.updatedAt == clock.now)
        #expect(session.resolvedPassage == BiblePassage(start: reference(3, 21), end: reference(3, 26)))
        // The next suggestion follows the stored end.
        #expect(store.suggestion(for: romans) == BibleProgress.next(after: reference(3, 26), book: 45))
    }

    @Test func completeSession_changedHeading_leavesTextAlone() throws {
        let started = store.startSession(book: romans, passage: BiblePassage(start: reference(3, 21)), dayKey: "2026-11-19",
                                         dateText: "19.11.2026", locale: german)
        let edited = started.note.text.replacingOccurrences(of: "19.11.2026 · 3,21–", with: "19.11.2026 · Römer 3 gelesen")
        store.updateText(started.note.id, text: edited)
        store.completeSession(started.session.id, end: reference(3, 26))
        #expect(started.note.text == edited)
        #expect(started.session.endChapter == 3 && started.session.endVerse == 26 && started.session.completedAt != nil)
    }

    @Test func completeSession_endOutsideTheBookOrBeforeTheStart_isNotStored() {
        let started = store.startSession(book: romans, passage: BiblePassage(start: reference(3, 21)), dayKey: "2026-11-19",
                                         dateText: "19.11.2026", locale: german)
        let text = started.note.text
        store.completeSession(started.session.id, end: reference(3, 5))
        #expect(started.session.completedAt != nil && started.session.endChapter == 0 && started.note.text == text)
        let second = store.startSession(book: romans, passage: BiblePassage(start: reference(4, 1)), dayKey: "2026-11-20",
                                        dateText: "20.11.2026", locale: german)
        store.completeSession(second.session.id, end: reference(BibleVerseCounts.chapterCount(book: 45) + 1, 1))
        #expect(second.session.completedAt != nil && second.session.endChapter == 0 && second.session.passage == "4,1–")
    }

    @Test func completeSession_withoutEnd_keepsTheChosenEnd() {
        let passage = BiblePassage(start: reference(3, 21), end: reference(3, 26))
        let started = store.startSession(book: romans, passage: passage, dayKey: "2026-11-19", dateText: "19.11.2026", locale: german)
        store.completeSession(started.session.id)
        #expect(started.session.endChapter == 3 && started.session.endVerse == 26 && started.session.passage == "3,21–26")
        #expect(started.note.text.hasSuffix("19.11.2026 · 3,21–26\n\n"))
    }

    @Test func completeSession_twice_keepsTheFirstEnd() {
        let started = store.startSession(book: romans, passage: BiblePassage(start: reference(3, 21)), dayKey: "2026-11-19",
                                         dateText: "19.11.2026", locale: german)
        store.completeSession(started.session.id, end: reference(3, 26))
        store.completeSession(started.session.id, end: reference(3, 30))
        #expect(started.session.endVerse == 26 && started.session.passage == "3,21–26")
    }

    @Test func legacySession_isParsedOnRead() {
        let started = store.startSession(book: romans, passage: " 3,21-31 ", dayKey: "2026-11-19", dateText: "19.11.2026", locale: german)
        let session = started.session
        #expect(session.startChapter == 0, "no migration: the numbers are read from the text")
        #expect(session.resolvedPassage == BiblePassage(start: reference(3, 21), end: reference(3, 31)))
        #expect(store.suggestion(for: romans) == BibleProgress.next(after: reference(3, 31), book: 45))
    }

    @Test func legacySession_freeTextOrOutsideTheTable_isNotResolved() {
        _ = store.startSession(book: romans, passage: "Kap. 3", dayKey: "2026-11-19", dateText: "19.11.2026", locale: german)
        #expect(store.lastSession(bookKey: "45")?.resolvedPassage == nil)
        #expect(store.suggestion(for: romans) == .start(reference(1, 1)))
        clock.now = clock.now.addingTimeInterval(60)
        let beyond = "\(BibleVerseCounts.chapterCount(book: 45) + 1),1-2"
        _ = store.startSession(book: romans, passage: beyond, dayKey: "2026-11-19", dateText: "19.11.2026", locale: german)
        #expect(store.lastSession(bookKey: "45")?.resolvedPassage == nil, "a passage outside the table counts as free text")
    }

    @Test func legacySession_completedWithAnEnd_continuesAfterIt() {
        let started = store.startSession(book: romans, passage: "3,21", dayKey: "2026-11-19", dateText: "19.11.2026", locale: german)
        #expect(store.suggestion(for: romans) == .start(reference(3, 21)), "an open session continues at its start")
        store.completeSession(started.session.id, end: reference(3, 26))
        #expect(started.session.passage == "3,21–26" && started.note.text.hasSuffix("19.11.2026 · 3,21–26\n\n"))
        #expect(store.suggestion(for: romans) == BibleProgress.next(after: reference(3, 26), book: 45))
    }

    @Test func freeTextSession_completedWithAnEnd_stillSuggestsAfterIt() {
        let started = store.startSession(book: romans, passage: "Anfang des Briefs", dayKey: "2026-11-19", dateText: "19.11.2026", locale: german)
        store.completeSession(started.session.id, end: reference(1, 17))
        #expect(started.session.passage == "Anfang des Briefs", "without a known start the heading stays")
        #expect(store.suggestion(for: romans) == BibleProgress.next(after: reference(1, 17), book: 45))
    }

    @Test func suggestion_withoutSessions_isOneOne_evenWithAnImportedNote() {
        _ = store.importBibleNotes([NotionBibleNote(id: "a", title: "Römer", text: "Notizen\n\nGnade.")])
        #expect(store.suggestion(for: romans) == .start(reference(1, 1)))
        #expect(store.suggestion(for: john) == .start(reference(1, 1)))
    }

    @Test func suggestion_afterTheLastVerseOfTheBook_isFinished() {
        let lastChapter = BibleVerseCounts.chapterCount(book: 45)
        let lastVerse = BibleVerseCounts.verseCount(book: 45, chapter: lastChapter)
        let end = reference(lastChapter, lastVerse)
        let started = store.startSession(book: romans, passage: BiblePassage(start: reference(lastChapter, 1), end: end),
                                         dayKey: "2026-11-19", dateText: "19.11.2026", locale: german)
        store.completeSession(started.session.id)
        #expect(store.suggestion(for: romans) == .bookFinished(last: end))
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
        #expect(note.folderID == store.folder(role: .bibleStudy)?.id && store.thoughtNotes().isEmpty)
    }
}
