import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The paperclip menu of the note editor: photo from the library, photo from the camera, picture from the clipboard,
/// file. The menu only reports what was chosen; the editor owns the pickers and the store. (A picker presented from
/// inside a menu would disappear with it.)
struct NoteAttachmentMenu: View {
    let onChoosePhoto: () -> Void
    let onTakePhoto: () -> Void
    let onPaste: ([NSItemProvider]) -> Void
    let onChooseFile: () -> Void

    var body: some View {
        Menu {
            Button { onChoosePhoto() } label: { Label("Foto auswählen", systemImage: "photo") }
            if Self.cameraIsAvailable {
                Button { onTakePhoto() } label: { Label("Foto aufnehmen", systemImage: "camera") }
            }
            PasteButton(supportedContentTypes: [.image], payloadAction: onPaste)
            Button { onChooseFile() } label: { Label("Datei", systemImage: "doc") }
        } label: {
            Image(systemName: "paperclip")
        }
        .accessibilityLabel("Anhängen")
    }

    static var cameraIsAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    /// The text with `reference` inserted at the cursor (or the selection, which it replaces), or at the end when there is
    /// no cursor. The reference gets its own line: a line break goes before it unless it starts a line, and one behind it.
    /// Returns the new text and the offset right behind the inserted reference line.
    static func inserting(_ reference: String, into text: String, replacing range: Range<String.Index>?) -> (text: String, cursorOffset: Int) {
        let range = range ?? text.endIndex..<text.endIndex
        let before = text[..<range.lowerBound]
        let after = text[range.upperBound...]
        let prefix = before.isEmpty || before.hasSuffix("\n") ? "" : "\n"
        let suffix = after.hasPrefix("\n") ? "" : "\n"
        let inserted = prefix + reference + suffix
        let result = String(before) + inserted + String(after)
        return (result, before.count + inserted.count)
    }
}
