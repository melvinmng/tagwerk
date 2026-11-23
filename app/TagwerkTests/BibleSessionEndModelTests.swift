import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// "Bis wohin gelesen?" (BV2b): completing a running session with the end chosen on the wheels. Passages are invented; the limits
/// come from `BibleVerseCounts`.
@MainActor
struct BibleSessionEndModelTests {
    let container: ModelContainer
    let store: NoteStore
    let german = Locale(identifier: "de_DE")

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        store = NoteStore(context: container.mainContext, now: { testNow() })
    }

    private var romans: BibleBook { BibleBooks.book(number: 45)! }
    private func reference(_ chapter: Int, _ verse: Int) -> BibleReference { BibleReference(chapter: chapter, verse: verse) }
    private var lastVerseOfChapter3: Int { BibleVerseCounts.verseCount(book: 45, chapter: 3) }

    private func open(_ passage: BiblePassage? = nil, freeText: String? = nil) -> (note: NoteRecord, session: BibleStudySessionRecord) {
        store.startSession(book: romans, passage: passage, freeText: freeText, dayKey: "2026-11-20", dateText: "20.11.2026", locale: german)
    }

    private func model(_ session: BibleStudySessionRecord) throws -> BibleSessionEndModel {
        try #require(BibleSessionEndModel(session: session, store: store, locale: german))
    }

    @Test func defaultEnd_isTheEndOfTheStartChapter() throws {
        let started = open(BiblePassage(start: reference(3, 21)))
        let model = try model(started.session)
        #expect(model.asksForEnd && model.end == reference(3, lastVerseOfChapter3))
        #expect(model.runningTitle == "Sitzung läuft · Römer ab 3,21")
        #expect(model.confirmTitle == "Abschließen · 3,21–\(lastVerseOfChapter3)")
    }

    @Test func endChosenAtTheStart_isKept() throws {
        let started = open(BiblePassage(start: reference(3, 21), end: reference(3, 26)))
        let model = try model(started.session)
        #expect(model.end == reference(3, 26))
        #expect(model.runningTitle == "Sitzung läuft · Römer 3,21–26")
        #expect(model.confirmTitle == "Abschließen · 3,21–26")
    }

    @Test func setEnd_staysInsideTheBookAndBehindTheStart() throws {
        let started = open(BiblePassage(start: reference(3, 21)))
        let model = try model(started.session)
        model.setEnd(chapter: 3, verse: 5)
        #expect(model.end == reference(3, 21), "not before the start")
        model.setEnd(chapter: 1, verse: 1)
        #expect(model.end == reference(3, 21))
        model.setEnd(chapter: 4, verse: 999)
        #expect(model.end == reference(4, BibleVerseCounts.verseCount(book: 45, chapter: 4)))
        model.setEnd(chapter: 999, verse: 1)
        #expect(model.end?.chapter == BibleVerseCounts.chapterCount(book: 45))
        #expect(model.chapterRange.lowerBound == 3 && model.verseRange(chapter: 3).lowerBound == 21 && model.verseRange(chapter: 4).lowerBound == 1)
    }

    @Test func complete_storesTheChosenEndAndCompletesTheHeading() throws {
        let started = open(BiblePassage(start: reference(3, 21)))
        #expect(started.note.text.contains("20.11.2026 · 3,21–"))
        let model = try model(started.session)
        model.setEnd(chapter: 3, verse: 26)
        model.complete()
        #expect(started.session.completedAt != nil && started.session.endChapter == 3 && started.session.endVerse == 26)
        #expect(started.session.passage == "3,21–26")
        #expect(store.note(id: started.note.id)?.text.contains("20.11.2026 · 3,21–26") == true)
        #expect(store.openSession(noteID: started.note.id) == nil)
    }

    @Test func complete_savesBeforeCompleting() throws {
        let started = open(BiblePassage(start: reference(3, 21)))
        var order: [String] = []
        try model(started.session).complete { order.append("save"); #expect(started.session.completedAt == nil) }
        order.append("done")
        #expect(order == ["save", "done"] && started.session.completedAt != nil)
    }

    @Test func completeFromEditor_adoptsNewHeading() throws {
        let started = open(BiblePassage(start: reference(3, 21)))
        // The editor holds the text it stored itself (`lastSaved`); completing changes the heading in the store.
        let editorText = started.note.text
        let model = try model(started.session)
        model.setEnd(chapter: 3, verse: 26)
        model.complete { store.updateText(started.note.id, text: editorText) }
        let stored = try #require(store.note(id: started.note.id)?.text)
        #expect(stored != editorText)
        #expect(NoteEditorSync.resolution(local: editorText, lastSaved: editorText, stored: stored, isTrashed: false) == .adopt(stored))
    }

    @Test func freeTextPassage_asksForNoEnd() throws {
        let started = open(freeText: "Kap. 3")
        let model = try model(started.session)
        #expect(!model.asksForEnd && model.end == nil)
        #expect(model.runningTitle == "Sitzung läuft · Römer Kap. 3")
        model.complete()
        #expect(started.session.completedAt != nil && started.session.endChapter == 0 && started.session.passage == "Kap. 3")
    }
}
