import Foundation
import SwiftData
import TagwerkCore

/// A note stored on this device only. The title is the first line of `text`.
/// Schema rule: every attribute has a default value, nothing is unique, no relationships, so a later sync
/// stays possible. `id` is kept unique by `NoteStore`.
@Model
final class NoteRecord {
    var id: UUID = UUID()
    var text: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    /// Raw value of `NoteKind`: "free", "morning", "evening", "journal" or "bibleStudy".
    var kindRaw: String = "free"
    /// "YYYY-MM-DD" (`NoteDayKey`), only for morning, evening and journal notes.
    var dayKey: String? = nil
    var isPinned: Bool = false
    var wasDictated: Bool = false
    /// When suggestions were derived from the note (phase 7); `nil` until then.
    var processedAt: Date? = nil
    /// Phase 7: executed suggestions and tasks created by hand from this note ("2 Aufgaben daraus").
    var derivedActionCount: Int = 0
    /// The folder the note lies in; `nil` is the default folder "Notizen".
    /// A note in the trash keeps its folder, so "Wiederherstellen" can put it back.
    var folderID: UUID? = nil
    /// When the note went to "Zuletzt gelöscht"; `nil` for a live note.
    var deletedAt: Date? = nil
    /// Ids of the Notion pages this note was filled from, separated by spaces; `nil` for notes that were never imported.
    /// An import of the same page twice is skipped; a day that already had an entry gets later pages appended.
    var importSourceID: String? = nil
    /// `BibleBook.key` of a Bible Study note (one note per book); `nil` for every other note.
    var bookKey: String? = nil

    init(text: String, kind: NoteKind = .free, dayKey: String? = nil, wasDictated: Bool = false, now: Date = .now) {
        self.text = text
        self.createdAt = now
        self.updatedAt = now
        self.kindRaw = kind.rawValue
        self.dayKey = dayKey
        self.wasDictated = wasDictated
    }

    /// An unknown raw value reads as an own note.
    var kind: NoteKind { NoteKind(rawValue: kindRaw) ?? .free }
}
