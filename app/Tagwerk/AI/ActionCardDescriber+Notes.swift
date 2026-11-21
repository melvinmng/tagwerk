import AIKit
import Foundation
import TagwerkCore

/// The cards of the note tools of the notes chat (#233). The card shows what is written; an open card also carries the raw
/// values of the proposal (`detail`) for the sheet "Änderung ansehen". Executed and stored cards have no `detail`: the
/// text is gone from the arguments (stored form) or already in the note.
extension ActionCardDescriber {
    func describeNote(_ tool: String, args: [String: Any], language: VoiceLanguage, spoken: Bool) -> AssistantModel.ActionCard {
        func text(_ key: String.LocalizationValue) -> String { Localized.string(key, in: language, bundle: .main) }
        func string(_ key: String) -> String? { (args[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        // A spoken card avoids the dot between its parts, which speech drops.
        let separator = spoken ? ", " : " · "
        let key = string("note_id")
        let note = key.flatMap { noteAccess?.visibleNote(key: $0) }
        let currentTitle = note.map(NoteToolAccess.displayTitle) ?? key.flatMap { noteAccess?.cardTitle(key: $0) }
        let newText = string("text")
        func lines(_ value: String) -> String {
            let count = value.trimmingCharacters(in: .whitespacesAndNewlines).split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
            return text("\(count) Zeilen")
        }

        switch tool {
        case "update_note":
            // The stored form names the new title; the current title is better while the note is there.
            let name = currentTitle ?? string("title") ?? text("Ohne Titel")
            let title = text("Notiz „\(name)“ überarbeiten")
            guard isOpen, let note, let newText else {
                return AssistantModel.ActionCard(title: title, change: isOpen ? text("Text überarbeiten") : text("Text überarbeitet"))
            }
            let summary = NoteDiff.summary(old: note.text, new: newText)
            var parts: [String] = []
            if summary.added > 0 { parts.append(text("\(summary.added) Zeilen neu")) }
            if summary.removed > 0 { parts.append(text("\(summary.removed) entfernt")) }
            if summary.titleChanged { parts.append(text("Titel geändert")) }
            var card = AssistantModel.ActionCard(title: title, change: parts.isEmpty ? text("Keine Änderung") : parts.joined(separator: separator))
            card.detail = .update(title: name, before: note.text, after: newText)
            return card
        case "create_note":
            let name = string("title") ?? newText.map { NoteChatTools.firstLine(of: $0) } ?? text("Ohne Titel")
            let folderKey = string("folder_id")
            let folderID = (try? noteAccess?.newNoteFolder(key: folderKey, defaultFolderID: noteDefaultFolderID())).flatMap { $0 }
            let folderName = folderID.flatMap { id in noteAccess?.visibleFolders().first { $0.id == id }?.name } ?? text("Notizen")
            var parts = [text("Ordner „\(folderName)“")]
            if let newText { parts.append(lines(newText)) }
            var card = AssistantModel.ActionCard(title: text("Neue Notiz „\(name)“"), change: parts.joined(separator: separator),
                                                 confirmTitle: text("Anlegen"))
            if isOpen, let newText { card.detail = .create(text: newText.trimmingCharacters(in: .whitespacesAndNewlines)) }
            return card
        default:
            // delete_note
            let name = currentTitle ?? text("Ohne Titel")
            var parts: [String] = []
            if let reason = string("reason") { parts.append(text("Grund: \(reason)")) }
            parts.append(text("Kommt nach „Zuletzt gelöscht“ und bleibt dort 30 Tage wiederherstellbar."))
            var card = AssistantModel.ActionCard(title: text("Notiz „\(name)“ löschen"), change: parts.joined(separator: spoken ? " " : "\n"),
                                                 confirmTitle: text("Löschen"), isDestructive: true)
            card.doneNote = text("In „Zuletzt gelöscht“")
            if isOpen, let note { card.detail = .delete(text: note.text) }
            return card
        }
    }
}
