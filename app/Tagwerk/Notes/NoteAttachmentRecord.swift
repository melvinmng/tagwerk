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

    init(id: UUID = UUID(), noteID: UUID?, fileName: String, typeIdentifier: String, byteCount: Int, createdAt: Date = .now) {
        self.id = id
        self.noteID = noteID
        self.fileName = fileName
        self.typeIdentifier = typeIdentifier
        self.byteCount = byteCount
        self.createdAt = createdAt
    }
}
