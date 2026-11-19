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
    /// The passage as typed, e.g. "3,21-31".
    var passage: String = ""
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
