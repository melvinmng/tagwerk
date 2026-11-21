import Foundation

/// What the open editor does when the stored note changes: its own delayed save keeps it as it is, a change from another
/// place (the translation sheet, later the assistant) replaces its text, and a note that is gone closes the page.
///
/// The editor holds the text as `@State` and writes it back half a second after the last keystroke and when it closes.
/// Without this rule that write would put the old text over every change made while the note is open.
enum NoteEditorSync {
    enum Resolution: Equatable {
        /// Nothing to do: the stored text is the one the editor wrote itself.
        case keep
        /// Take this text: the change did not come from the editor.
        case adopt(String)
        /// The note was deleted or moved to the trash; close the page without saving.
        case close
    }

    /// - Parameters:
    ///   - local: the text in the editor (not yet saved while the user is typing).
    ///   - lastSaved: the text the editor wrote last, or loaded when it opened.
    ///   - stored: the text of the note in the store; `nil` when the note does not exist any more.
    ///   - isTrashed: whether the note is in "Zuletzt gelöscht".
    static func resolution(local: String, lastSaved: String, stored: String?, isTrashed: Bool) -> Resolution {
        guard let stored, !isTrashed else { return .close }
        // The editor's own saves set `lastSaved` first, so a stored text that equals it came from the editor. The text the
        // user is typing (`local`) is not part of the decision: it is not stored yet, and a change from outside wins over it.
        return stored == lastSaved ? .keep : .adopt(stored)
    }
}
