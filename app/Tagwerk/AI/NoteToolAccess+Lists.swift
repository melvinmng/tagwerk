import Foundation
import TagwerkCore

/// Folders, titles and the rules for new notes of the notes chat. Like everything in `NoteToolAccess` they leave out
/// private and trashed notes.
extension NoteToolAccess {
    /// Prefix of the folder id the assistant sees: "folder:<UUID>".
    static let folderKeyPrefix = "folder:"

    static func folderKey(for id: UUID) -> String { folderKeyPrefix + id.uuidString }

    /// One line of `list_notes`: no text, no excerpt.
    struct Entry: Equatable {
        enum MatchedIn: String { case title, text }
        let id: UUID
        let title: String
        let folderName: String
        let updatedAt: Date
        /// Set only when the list was filtered by a query.
        let matchedIn: MatchedIn?
    }

    /// The folders the assistant may see: every folder that is not private and not below a private one, in display order.
    func visibleFolders() -> [NoteFolderInfo] {
        let infos = store.folders().map(\.info)
        let hidden = NoteFolderRules.privateFolderIDs(in: infos)
        return NoteFolderRules.tree(infos).flatMap(\.flattened).map(\.folder).filter { !hidden.contains($0.id) }
    }

    /// The visible folder for a key of the form "folder:<UUID>"; `nil` for private and unknown folders alike.
    func visibleFolder(key: String) -> NoteFolderInfo? {
        guard key.hasPrefix(Self.folderKeyPrefix), let id = UUID(uuidString: String(key.dropFirst(Self.folderKeyPrefix.count))) else {
            return nil
        }
        return visibleFolders().first { $0.id == id }
    }

    /// Whether a new free note may be created in the folder (`nil` is "Notizen"): a visible folder that takes the user's own
    /// notes. The routine folders and the Dream Log are filled by the routines only.
    func acceptsNewNote(folderID: UUID?) -> Bool {
        guard let folderID else { return true }
        guard let folder = visibleFolders().first(where: { $0.id == folderID }) else { return false }
        return folder.role?.acceptsOwnNotes ?? true
    }

    enum FolderChoiceError: Error {
        /// The key names no visible folder.
        case unknown
        /// The folder is visible but takes no notes of the assistant (the routine folders).
        case notAccepted
    }

    /// The folder a new note of the assistant goes to: the folder `key` names; without a key the default folder of the chat
    /// when it takes new notes, else "Notizen" (`nil`). Used by the tool and by the card, so both agree.
    func newNoteFolder(key: String?, defaultFolderID: UUID?) throws -> UUID? {
        if let key {
            guard let folder = visibleFolder(key: key) else { throw FolderChoiceError.unknown }
            guard acceptsNewNote(folderID: folder.id) else { throw FolderChoiceError.notAccepted }
            return folder.id
        }
        if let defaultFolderID, acceptsNewNote(folderID: defaultFolderID) { return defaultFolderID }
        return nil
    }

    /// Title of a note for a card that is shown on the screen only: also a note that went to the trash meanwhile, never a
    /// private one. Nothing of it is sent.
    func cardTitle(key: String) -> String? {
        guard key.hasPrefix(Self.keyPrefix), let id = UUID(uuidString: String(key.dropFirst(Self.keyPrefix.count))),
              let note = store.note(id: id), !store.isPrivate(note) else { return nil }
        return Self.displayTitle(note)
    }

    /// The visible notes, newest change first (pinned notes get no precedence). `folderID` limits the list to the folder and
    /// the folders below it, `query` to notes in which every word occurs in the title or the text.
    func entries(folderID: UUID?, query: String?) -> [Entry] {
        let infos = store.folders().map(\.info)
        let names = Dictionary(infos.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let folderScope = folderID.map { NoteFolderRules.subtreeIDs(of: $0, in: infos) }
        let words = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        return visibleNotes()
            .filter { note in
                guard let folderScope else { return true }
                return note.folderID.map(folderScope.contains) ?? false
            }
            .compactMap { note -> Entry? in
                let title = Self.displayTitle(note)
                var matchedIn: Entry.MatchedIn?
                if let words, !words.isEmpty {
                    guard NoteText.matches(note.text, query: words) else { return nil }
                    matchedIn = NoteText.matches(title, query: words) ? .title : .text
                }
                // A note whose folder is gone reads as lying in "Notizen", like in the notes list.
                let folderName = note.folderID.flatMap { names[$0] } ?? String(localized: "Notizen")
                return Entry(id: note.id, title: title, folderName: folderName, updatedAt: note.updatedAt, matchedIn: matchedIn)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// First line of the note, "Ohne Titel" for a note without one.
    static func displayTitle(_ note: NoteRecord) -> String {
        let title = NoteText.title(note.text)
        return title.isEmpty ? String(localized: "Ohne Titel") : title
    }
}
