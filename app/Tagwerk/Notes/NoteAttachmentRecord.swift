import Foundation
import SwiftData

/// The metadata of a file attached to a note. The file itself lies in `NoteAttachmentStore`'s folder, named by `id`.
/// Same schema rules as `NoteRecord`: defaults everywhere, nothing is unique, no relationships (the note is found by
/// `noteID`). `id` is kept unique by `NoteAttachmentStore`.
@Model
final class NoteAttachmentRecord {
    var id: UUID = UUID()
    /// The note the file belongs to; `nil` only for a record whose note is gone (removed at the next start).
    var noteID: UUID? = nil
    /// The name shown in the note, with the extension ("Rechnung.pdf", "Foto.jpg").
    var fileName: String = ""
    /// The uniform type identifier of the file ("public.jpeg", "com.adobe.pdf"); empty if unknown.
    var typeIdentifier: String = ""
    var byteCount: Int = 0
    var createdAt: Date = Date.now
    /// "" for a plain picture or file, "scan" for a scanned PDF, "drawing" for the picture of a drawing, "strokes" for the
    /// stroke data that belongs to a drawing (`NoteAttachmentStore.Role`).
    var roleRaw: String = ""
    /// The attachment this file belongs to (the picture of a drawing); `nil` for every file that stands on its own.
    var companionOfID: UUID? = nil
    /// Text recognised in a scan; `nil` until recognition has run, empty when it ran and found nothing. It belongs to the
    /// attachment and is never part of the note text.
    var recognizedText: String? = nil
    /// The number of pages of a scanned PDF; 0 for everything else.
    var pageCount: Int = 0

    init(id: UUID = UUID(), noteID: UUID?, fileName: String, typeIdentifier: String, byteCount: Int, createdAt: Date = .now,
         roleRaw: String = "", companionOfID: UUID? = nil, recognizedText: String? = nil, pageCount: Int = 0) {
        self.id = id
        self.noteID = noteID
        self.fileName = fileName
        self.typeIdentifier = typeIdentifier
        self.byteCount = byteCount
        self.createdAt = createdAt
        self.roleRaw = roleRaw
        self.companionOfID = companionOfID
        self.recognizedText = recognizedText
        self.pageCount = pageCount
    }

    /// A file that belongs to another attachment (the strokes of a drawing) and is never shown or counted on its own.
    var isCompanion: Bool { companionOfID != nil }
}
