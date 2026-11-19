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
    /// Raw value of `NoteKind`: "free", "morning" or "evening".
    var kindRaw: String = "free"
    /// "YYYY-MM-DD" (`NoteDayKey`), only for morning and evening notes.
    var dayKey: String? = nil
    var isPinned: Bool = false
    var wasDictated: Bool = false
    /// When suggestions were derived from the note (phase 7); `nil` until then.
    var processedAt: Date? = nil
    /// Phase 7: executed suggestions and tasks created by hand from this note ("2 Aufgaben daraus").
    var derivedActionCount: Int = 0

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
