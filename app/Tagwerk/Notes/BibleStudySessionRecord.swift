import Foundation
import SwiftData
import TagwerkCore

/// One Bible Study session (#186): which book and passage were read on which day and which note holds the observations.
/// Same schema rules as the notes: defaults everywhere, nothing unique, no relationships (the note is named by its id).
@Model
final class BibleStudySessionRecord {
    var id: UUID = UUID()
    /// "YYYY-MM-DD" (`NoteDayKey`) of the day the session started.
    var dayKey: String = ""
    /// `BibleBook.key` (the number in the canon as text).
    var book: String = ""
    /// The passage as written in the heading of the session section: typed free text ("3,21-31") or the text of the chosen
    /// numbers ("3,21–31", "3,21–" while the end is open).
    var passage: String = ""
    /// The passage as numbers (BS2); 0 means unknown, as for sessions typed as free text.
    var startChapter: Int = 0
    var startVerse: Int = 0
    var endChapter: Int = 0
    var endVerse: Int = 0
    /// The book note the session wrote into.
    var noteID: UUID = UUID()
    var startedAt: Date = Date.now
    /// `nil` while the session is open; a completed session fulfils the Bible Study habit.
    var completedAt: Date? = nil

    init(dayKey: String, book: String, passage: String, noteID: UUID, startedAt: Date) {
        self.dayKey = dayKey
        self.book = book
        self.passage = passage
        self.noteID = noteID
        self.startedAt = startedAt
    }
}

extension BibleStudySessionRecord {
    /// Where the session started, as stored or, for a session typed as free text, as read from the text ("3,21-31").
    /// `nil` when neither gives a verse that exists in the book (the text then stays free text).
    var resolvedStart: BibleReference? {
        if startChapter > 0, startVerse > 0 { return validInBook(BibleReference(chapter: startChapter, verse: startVerse)) }
        return BiblePassage.parse(passage).flatMap { validInBook($0.start) }
    }

    /// Where the session ended, if it did: the stored end, else the end read from the free text.
    var resolvedEnd: BibleReference? {
        if endChapter > 0, endVerse > 0 { return validInBook(BibleReference(chapter: endChapter, verse: endVerse)) }
        return BiblePassage.parse(passage)?.end.flatMap { validInBook($0) }
    }

    /// The passage as numbers; `nil` when the start is unknown. An end before the start is dropped.
    var resolvedPassage: BiblePassage? {
        guard let start = resolvedStart else { return nil }
        let end = resolvedEnd.flatMap { $0 >= start ? $0 : nil }
        return BiblePassage(start: start, end: end)
    }

    private func validInBook(_ reference: BibleReference) -> BibleReference? {
        guard let number = Int(book), BibleVerseCounts.isValid(book: number, chapter: reference.chapter, verse: reference.verse) else {
            return nil
        }
        return reference
    }
}
