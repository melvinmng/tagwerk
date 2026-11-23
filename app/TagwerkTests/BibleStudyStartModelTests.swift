import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The start sheet of a Bible Study session (BS2b, BV1b, BV2b, BV3a). Passages and dates are invented; chapter and verse
/// limits come from `BibleVerseCounts` and are not repeated as numbers.
@MainActor
struct BibleStudyStartModelTests {
    final class Clock { var now = testNow() }
    let container: ModelContainer
    let clock = Clock()
    let store: NoteStore
    let german = Locale(identifier: "de_DE")
    let calendar = Calendar(identifier: .gregorian)

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        let clock = self.clock
        store = NoteStore(context: container.mainContext, now: { clock.now })
    }

    private var romans: BibleBook { BibleBooks.book(number: 45)! }
    private var john: BibleBook { BibleBooks.book(number: 43)! }

    private func model() -> BibleStudyStartModel {
        BibleStudyStartModel(store: store, calendar: calendar, locale: german)
    }

    @discardableResult
    private func session(_ book: BibleBook, _ passage: BiblePassage, day: String, completed: Bool = true) -> BibleStudySessionRecord {
        // Sessions are ordered by their start, so each one starts a minute after the one before.
        clock.now = clock.now.addingTimeInterval(60)
        let started = store.startSession(book: book, passage: passage, dayKey: day, dateText: day, locale: german)
        if completed { store.completeSession(started.session.id) }
        return started.session
    }

    private func reference(_ chapter: Int, _ verse: Int) -> BibleReference { BibleReference(chapter: chapter, verse: verse) }

    @Test func model_preselectsLastBookAndNextVerse() {
        session(john, BiblePassage(start: reference(1, 1), end: reference(1, 5)), day: "2026-11-10")
        session(romans, BiblePassage(start: reference(3, 1), end: reference(3, 20)), day: "2026-11-17")
        let model = model()
        #expect(model.book == romans)
        #expect(model.from == reference(3, 21) && model.to == nil)
        #expect(model.recentBooks == [romans, john])
    }

    @Test func model_firstSessionStartsAtOneOne() {
        let model = model()
        #expect(model.from == reference(1, 1) && model.to == nil)
        #expect(model.recentBooks.isEmpty && model.hint == nil && model.finishedNotice == nil)
    }

    @Test func select_otherBook_resetsFromAndTo() {
        session(romans, BiblePassage(start: reference(3, 1), end: reference(3, 20)), day: "2026-11-17")
        session(john, BiblePassage(start: reference(1, 1), end: reference(1, 18)), day: "2026-11-10")
        let model = model()
        model.setTo(chapter: 3, verse: 26)
        model.usesFreeText = true
        model.freeText = "Kap. 3"
        model.select(john)
        #expect(model.book == john && model.from == reference(1, 19) && model.to == nil)
        #expect(!model.usesFreeText && model.freeText.isEmpty)
        // A book without a session starts at 1,1.
        model.select(BibleBooks.book(number: 59)!)
        #expect(model.from == reference(1, 1))
    }

    @Test func hint_namesLastPassageAndDate() {
        session(romans, BiblePassage(start: reference(3, 1), end: reference(3, 20)), day: "2026-11-17")
        #expect(model().hint == "Weiter nach 3,1–20 vom 17.11.")
    }

    @Test func hint_openSession_continuesAtItsStart() {
        session(romans, BiblePassage(start: reference(3, 21)), day: "2026-11-20", completed: false)
        let model = model()
        #expect(model.from == reference(3, 21))
        #expect(model.hint == "Weiter ab 3,21 (Sitzung vom 20.11. ist noch offen)")
    }

    @Test func hint_chapterRead_namesTheChapter() {
        let lastVerse = BibleVerseCounts.verseCount(book: 45, chapter: 3)
        session(romans, BiblePassage(start: reference(3, 21), end: reference(3, lastVerse)), day: "2026-11-20")
        let model = model()
        #expect(model.from == reference(4, 1))
        #expect(model.hint == "Kapitel 3 ist gelesen (bis 3,\(lastVerse) am 20.11.)")
    }

    @Test func finishedNotice_onlyAfterLastVerse() {
        let chapters = BibleVerseCounts.chapterCount(book: 45)
        let lastVerse = BibleVerseCounts.verseCount(book: 45, chapter: chapters)
        session(romans, BiblePassage(start: reference(chapters, 1), end: reference(chapters, lastVerse - 1)), day: "2026-01-13")
        #expect(model().finishedNotice == nil)
        session(romans, BiblePassage(start: reference(chapters, lastVerse), end: reference(chapters, lastVerse)), day: "2026-01-14")
        let model = model()
        #expect(model.finishedNotice == "Römer ist zu Ende gelesen (\(chapters),\(lastVerse) am 14.01.). Wähle ein anderes Buch oder beginne Römer neu.")
        // "Von 1,1 · von vorn": no jump into the next book.
        #expect(model.from == reference(1, 1) && model.hint == nil && model.book == romans)
    }

    @Test func startTitle_withOpenEnd() {
        session(romans, BiblePassage(start: reference(3, 1), end: reference(3, 20)), day: "2026-11-17")
        let model = model()
        #expect(model.startTitle == "Sitzung starten · Römer 3,21")
        model.setTo(chapter: 3, verse: 26)
        #expect(model.startTitle == "Sitzung starten · Römer 3,21–26")
        model.usesFreeText = true
        #expect(model.startTitle == "Sitzung starten · Römer")
        model.freeText = " Kap. 3 "
        #expect(model.startTitle == "Sitzung starten · Römer Kap. 3")
    }

    @Test func toCannotPrecedeFrom() {
        let model = model()
        model.select(romans)
        model.setFrom(chapter: 3, verse: 21)
        model.setTo(chapter: 3, verse: 10)
        #expect(model.to == reference(3, 21))
        model.setTo(chapter: 3, verse: 26)
        model.setFrom(chapter: 3, verse: 30)
        #expect(model.to == reference(3, 30))
        model.setFrom(chapter: 3, verse: 1)
        #expect(model.to == reference(3, 30), "an end behind the new start stays")
    }

    @Test func wheels_stayInsideTheBook() {
        let model = model()
        model.select(romans)
        model.setFrom(chapter: 999, verse: 999)
        let chapters = BibleVerseCounts.chapterCount(book: 45)
        #expect(model.from == reference(chapters, BibleVerseCounts.verseCount(book: 45, chapter: chapters)))
        model.setFrom(chapter: 0, verse: 0)
        #expect(model.from == reference(1, 1))
    }

    @Test func start_wheels_storesNumbers() throws {
        let model = model()
        model.select(romans)
        model.setFrom(chapter: 3, verse: 21)
        model.setTo(chapter: 3, verse: 26)
        let noteID = model.start(day: PlanDay(year: 2026, month: 11, day: 20))
        let stored = try #require(store.sessions().first)
        #expect(stored.noteID == noteID && stored.dayKey == "2026-11-20" && stored.passage == "3,21–26")
        #expect(stored.resolvedPassage == BiblePassage(start: reference(3, 21), end: reference(3, 26)))
        #expect(store.note(id: noteID)?.text.contains("20.11.2026 · 3,21–26") == true)
    }

    @Test func start_openEnd_storesStartOnly() throws {
        let model = model()
        model.select(romans)
        model.setFrom(chapter: 3, verse: 21)
        model.start(day: PlanDay(year: 2026, month: 11, day: 20))
        let stored = try #require(store.sessions().first)
        #expect(stored.passage == "3,21–" && stored.endChapter == 0 && stored.resolvedEnd == nil)
    }

    @Test func freeText_parsable_storesNumbers() throws {
        let model = model()
        model.select(romans)
        model.usesFreeText = true
        model.freeText = "3, 21 - 31"
        model.start(day: PlanDay(year: 2026, month: 11, day: 20))
        let stored = try #require(store.sessions().first)
        #expect(stored.startChapter == 3 && stored.startVerse == 21 && stored.endChapter == 3 && stored.endVerse == 31)
        #expect(stored.passage == "3,21–31")
    }

    @Test func freeText_unparsable_storesText() throws {
        let model = model()
        model.select(romans)
        model.usesFreeText = true
        model.freeText = "Kap. 3"
        model.start(day: PlanDay(year: 2026, month: 11, day: 20))
        let stored = try #require(store.sessions().first)
        #expect(stored.passage == "Kap. 3" && stored.startChapter == 0)
        // No suggestion follows from free text.
        #expect(self.model().hint == nil)
    }
}
