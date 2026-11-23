import Foundation
import Observation
import TagwerkCore

/// State and texts of the start sheet of a Bible Study session (BS2b, BV1b, BV2b, BV3a): the book, where reading begins and
/// ends, and the hint that tells what the suggestion is based on. The numbers are limited by `BibleVerseCounts`, so the
/// stored passage can always be read back; free text is the way out for a passage the wheels cannot express.
@MainActor @Observable
final class BibleStudyStartModel {
    /// The books of the latest sessions, newest first, at most three.
    private(set) var recentBooks: [BibleBook]
    private(set) var book: BibleBook
    private(set) var from: BibleReference
    /// `nil` while the end is open ("offen"); it is set when the end is chosen at the start or when the session is completed.
    private(set) var to: BibleReference?
    var usesFreeText = false
    var freeText = ""

    @ObservationIgnored private let store: NoteStore
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let locale: Locale

    init(store: NoteStore, calendar: Calendar = .tagwerk, locale: Locale = .current) {
        self.store = store
        self.calendar = calendar
        self.locale = locale
        let recent = store.recentBookKeys(limit: 3).compactMap(BibleBooks.book(key:))
        recentBooks = recent
        let initial = recent.first ?? BibleBooks.all[0]
        book = initial
        from = Self.start(of: store.suggestion(for: initial))
    }

    // MARK: Choice

    /// Takes the book and offers its next verse (or 1,1) as the start with an open end; the passage typed before is dropped.
    func select(_ newBook: BibleBook) {
        book = newBook
        from = Self.start(of: store.suggestion(for: newBook))
        to = nil
        usesFreeText = false
        freeText = ""
    }

    /// The start by chapter and verse, held inside the book. The end moves along when it would lie before the start.
    func setFrom(chapter: Int, verse: Int) {
        guard let reference = clamped(chapter: chapter, verse: verse) else { return }
        from = reference
        if let end = to, end < reference { to = reference }
    }

    /// The end by chapter and verse, held inside the book and not before the start; `nil` makes the end open.
    func setTo(chapter: Int, verse: Int) {
        guard let reference = clamped(chapter: chapter, verse: verse) else { return }
        to = max(reference, from)
    }

    func openEnd() { to = nil }

    var chapterCount: Int { BibleVerseCounts.chapterCount(book: book.number) }

    func verseCount(chapter: Int) -> Int { BibleVerseCounts.verseCount(book: book.number, chapter: chapter) }

    private func clamped(chapter: Int, verse: Int) -> BibleReference? {
        let chapters = chapterCount
        guard chapters > 0 else { return nil }
        let chosenChapter = min(max(chapter, 1), chapters)
        let verses = verseCount(chapter: chosenChapter)
        return BibleReference(chapter: chosenChapter, verse: min(max(verse, 1), max(verses, 1)))
    }

    private static func start(of next: BibleProgress.Next) -> BibleReference {
        switch next {
        case .start(let reference): reference
        case .bookFinished: BibleReference(chapter: 1, verse: 1)
        }
    }

    // MARK: Texts

    /// "Weiter nach 3,1–20 vom 17.11." / "Weiter ab 3,21 (Sitzung vom 20.11. ist noch offen)" / "Kapitel 3 ist gelesen (bis 3,31
    /// am 20.11.)"; `nil` for a first session, a finished book (see `finishedNotice`) and a session typed as free text.
    var hint: String? {
        guard let last = store.lastSession(bookKey: book.key), case .start = store.suggestion(for: book) else { return nil }
        let date = dateText(of: last)
        if let end = last.resolvedEnd, let passage = last.resolvedPassage {
            if end.verse >= verseCount(chapter: end.chapter) {
                return String(localized: "Kapitel \(end.chapter) ist gelesen (bis \(end.text) am \(date))")
            }
            return String(localized: "Weiter nach \(passage.text()) vom \(date)")
        }
        guard let start = last.resolvedStart else { return nil }
        if last.completedAt == nil {
            return String(localized: "Weiter ab \(start.text) (Sitzung vom \(date) ist noch offen)")
        }
        return String(localized: "Weiter ab \(start.text) (Sitzung vom \(date))")
    }

    /// "Römer ist zu Ende gelesen (16,27 am 14.01.). Wähle ein anderes Buch oder beginne Römer neu."; `nil` otherwise.
    var finishedNotice: String? {
        guard let last = store.lastSession(bookKey: book.key), case .bookFinished(let end) = store.suggestion(for: book) else { return nil }
        let name = book.name(locale: locale)
        return String(localized: "\(name) ist zu Ende gelesen (\(end.text) am \(dateText(of: last))). Wähle ein anderes Buch oder beginne \(name) neu.")
    }

    /// The label of the button: "Sitzung starten · Römer 3,21"; with a chosen end "… 3,21–26"; with an open end only the start.
    var startTitle: String {
        let name = book.name(locale: locale)
        let passageText: String
        if usesFreeText {
            passageText = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            passageText = to.map { BiblePassage(start: from, end: $0).text() } ?? from.text
        }
        let place = passageText.isEmpty ? name : "\(name) \(passageText)"
        return String(localized: "Sitzung starten · \(place)")
    }

    private func dateText(of session: BibleStudySessionRecord) -> String {
        PlanDay(dayKey: session.dayKey).map { DateText.numericDay($0, calendar: calendar, locale: locale) } ?? ""
    }

    // MARK: Start

    /// Starts the session and returns the id of the note it wrote into. Numbers the wheels or the free text give are stored
    /// as numbers; text that is no passage of the book stays free text.
    @discardableResult
    func start(day: PlanDay) -> UUID {
        let dayKey = NoteDayKey.string(day)
        let dateText = BibleStudyTemplate.dateText(day)
        if usesFreeText {
            return store.startSession(book: book, passage: BiblePassage.parse(freeText), freeText: freeText, dayKey: dayKey,
                                      dateText: dateText, locale: locale).note.id
        }
        return store.startSession(book: book, passage: BiblePassage(start: from, end: to), dayKey: dayKey, dateText: dateText,
                                  locale: locale).note.id
    }
}
