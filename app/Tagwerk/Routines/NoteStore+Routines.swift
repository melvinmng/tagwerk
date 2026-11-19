import Foundation
import TagwerkCore

/// What the routines need on top of the notes store (phase 7 design §5.4). Writing still goes only through `NoteStore`.
extension NoteStore {
    /// Creates, updates or, for text of whitespace only, deletes the one thought note of that day and kind.
    /// `kind` is `.morning` or `.evening`; `create` keeps it at one note per day and kind.
    @discardableResult
    func saveThought(_ text: String, kind: NoteKind, dayKey: String, wasDictated: Bool) -> NoteRecord? {
        precondition(kind == .morning || kind == .evening, "a thought note is a morning or an evening note")
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let existing = note(kind: kind, dayKey: dayKey) { delete(existing.id) }
            return nil
        }
        return create(text: text, kind: kind, dayKey: dayKey, wasDictated: wasDictated)
    }

    /// One more task or executed suggestion came from the note ("2 Aufgaben daraus").
    func addDerivedAction(_ id: UUID) {
        guard let record = note(id: id) else { return }
        record.derivedActionCount += 1
        save()
    }
}
