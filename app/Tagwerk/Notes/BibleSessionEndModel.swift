import Foundation
import Observation
import TagwerkCore

/// "Bis wohin gelesen?" (BV2b): the end of a running session, chosen when it is completed. The wheels start at the end chosen at
/// the start of the session or, without one, at the end of its first chapter; the end can not lie before the start. A session
/// whose passage was typed as free text has no numbers to ask for and is completed as it is.
@MainActor @Observable
final class BibleSessionEndModel: Identifiable {
    nonisolated let sessionID: UUID
    private let book: BibleBook
    private let passageText: String
    /// Where the session started; `nil` for a passage that is free text.
    let start: BibleReference?
    /// The chosen end; `nil` exactly when `start` is `nil`.
    private(set) var end: BibleReference?
    @ObservationIgnored private let store: NoteStore
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let chosenAtStart: Bool

    nonisolated var id: UUID { sessionID }

    init?(session: BibleStudySessionRecord, store: NoteStore, locale: Locale = .current) {
        guard let book = BibleBooks.book(key: session.book) else { return nil }
        self.sessionID = session.id
        self.book = book
        self.store = store
        self.locale = locale
        passageText = session.passage
        start = session.resolvedStart
        chosenAtStart = session.resolvedEnd != nil
        end = session.resolvedStart.map {
            BibleProgress.defaultEnd(start: $0, chosenEnd: session.resolvedEnd, book: book.number)
        }
    }

    /// Whether completing asks for an end: only a passage as numbers has one.
    var asksForEnd: Bool { start != nil }

    var chapterRange: ClosedRange<Int> {
        guard let start else { return 1...1 }
        return start.chapter...max(BibleVerseCounts.chapterCount(book: book.number), start.chapter)
    }

    func verseRange(chapter: Int) -> ClosedRange<Int> {
        let first = start.map { chapter == $0.chapter ? $0.verse : 1 } ?? 1
        return first...max(BibleVerseCounts.verseCount(book: book.number, chapter: chapter), first)
    }

    /// The end by chapter and verse, held inside the book and not before the start.
    func setEnd(chapter: Int, verse: Int) {
        guard let start else { return }
        let chosenChapter = min(max(chapter, start.chapter), chapterRange.upperBound)
        let range = verseRange(chapter: chosenChapter)
        end = BibleReference(chapter: chosenChapter, verse: min(max(verse, range.lowerBound), range.upperBound))
    }

    /// "Sitzung läuft · Römer ab 3,21" while the end is open, "… Römer 3,21–26" once it is set, the typed text for free text.
    var runningTitle: String {
        let name = book.name(locale: locale)
        if let start {
            if chosenAtStart, let end { return String(localized: "Sitzung läuft · \(name) \(BiblePassage(start: start, end: end).text())") }
            return String(localized: "Sitzung läuft · \(name) ab \(start.text)")
        }
        let typed = passageText.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(localized: "Sitzung läuft · \(typed.isEmpty ? name : "\(name) \(typed)")")
    }

    /// The label of the button below the wheels: "Abschließen · 3,21–26".
    var confirmTitle: String {
        guard let start, let end else { return String(localized: "Abschließen") }
        return String(localized: "Abschließen · \(BiblePassage(start: start, end: end).text())")
    }

    /// Completes the session with the chosen end. `beforeCompleting` runs first: the editor saves its text, so the store changes
    /// the heading of the section in the text it holds and the page adopts it afterwards.
    func complete(beforeCompleting: () -> Void = {}) {
        beforeCompleting()
        store.completeSession(sessionID, end: asksForEnd ? end : nil)
    }
}
