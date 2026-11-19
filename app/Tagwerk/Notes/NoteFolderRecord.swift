import Foundation
import SwiftData
import TagwerkCore

/// A folder of notes, stored on this device only. Same schema rules as `NoteRecord`: defaults everywhere, nothing
/// is unique, no relationships (notes point to a folder by `NoteRecord.folderID`). `id` is kept unique by `NoteStore`.
@Model
final class NoteFolderRecord {
    var id: UUID = UUID()
    var name: String = ""
    /// `nil` for a top-level folder.
    var parentID: UUID? = nil
    var order: Int = 0
    var createdAt: Date = Date.now
    /// Raw value of `NoteFolderRole` for system folders ("journal", "bibleStudy"); `nil` for the user's own folders.
    var roleRaw: String? = nil

    init(name: String, parentID: UUID? = nil, order: Int = 0, role: NoteFolderRole? = nil, now: Date = .now) {
        self.name = name
        self.parentID = parentID
        self.order = order
        self.createdAt = now
        self.roleRaw = role?.rawValue
    }

    /// An unknown raw value reads as an ordinary folder.
    var role: NoteFolderRole? { roleRaw.flatMap(NoteFolderRole.init(rawValue:)) }

    var info: NoteFolderInfo { NoteFolderInfo(id: id, name: name, parentID: parentID, order: order, role: role) }
}
