import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

/// The insert menu of the note editor, in the bar above the keyboard: one button with two groups. "Aufnehmen" brings in
/// something from outside (photo from the library, photo from the camera, scanned document, file, picture from the
/// clipboard), "Erstellen" makes something new (drawing, table). The menu only reports what was chosen; the editor owns
/// the pickers, the scanner and the sheets. (A picker presented from inside a menu would disappear with it.)
struct NoteInsertMenu: View {
    /// What the menu can offer, in the order it shows them.
    enum Entry: Hashable {
        case choosePhoto, takePhoto, scanDocument, chooseFile, paste
        case drawing, table
    }

    /// The two groups of the menu; an empty group is left out.
    enum Group: Hashable {
        case capture, create

        var entries: [Entry] {
            switch self {
            case .capture: [.choosePhoto, .takePhoto, .scanDocument, .chooseFile, .paste]
            case .create: [.drawing, .table]
            }
        }
    }

    /// One group with the entries it shows on this device.
    struct Block: Identifiable, Equatable {
        let group: Group
        let entries: [Entry]
        var id: Group { group }
    }

    /// The entries of each group for a device: "Foto aufnehmen" needs a camera and "Dokument scannen" the document camera.
    /// Injected, so the rules are tried without hardware.
    static func groups(canTakePhoto: Bool, canScan: Bool) -> [Block] {
        [Group.capture, .create].map { group in
            Block(group: group, entries: group.entries.filter { entry in
                switch entry {
                case .takePhoto: canTakePhoto
                case .scanDocument: canScan
                default: true
                }
            })
        }.filter { !$0.entries.isEmpty }
    }

    let onChoosePhoto: () -> Void
    let onTakePhoto: () -> Void
    let onScanDocument: () -> Void
    let onPaste: ([NSItemProvider]) -> Void
    let onChooseFile: () -> Void
    let onDrawing: () -> Void
    let onTable: () -> Void

    var body: some View {
        Menu {
            ForEach(Self.groups(canTakePhoto: Self.cameraIsAvailable, canScan: Self.scannerIsAvailable)) { block in
                Section(block.group.title) {
                    ForEach(block.entries, id: \.self) { entry in row(entry) }
                }
            }
        } label: {
            Image(systemName: "plus.circle")
        }
        .accessibilityLabel("Einfügen")
        .accessibilityIdentifier(AccessibilityID.NoteEditor.insertMenu)
    }

    @ViewBuilder private func row(_ entry: Entry) -> some View {
        switch entry {
        case .choosePhoto: Button { onChoosePhoto() } label: { Label("Foto auswählen", systemImage: "photo") }
        case .takePhoto: Button { onTakePhoto() } label: { Label("Foto aufnehmen", systemImage: "camera") }
        case .scanDocument: Button { onScanDocument() } label: { Label("Dokument scannen", systemImage: "doc.viewfinder") }
        case .chooseFile: Button { onChooseFile() } label: { Label("Datei", systemImage: "doc") }
        case .paste: PasteButton(supportedContentTypes: [.image], payloadAction: onPaste)
        case .drawing: Button { onDrawing() } label: { Label("Zeichnung", systemImage: "pencil.tip.crop.circle") }
        case .table: Button { onTable() } label: { Label("Tabelle", systemImage: "tablecells") }
        }
    }

    static var cameraIsAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    /// The document camera needs a camera and is missing in the simulator; the UI tests bring their own test pages.
    static var scannerIsAvailable: Bool { VNDocumentCameraViewController.isSupported || UITestMode.scanPageCount != nil }

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

extension NoteInsertMenu.Group {
    var title: LocalizedStringKey {
        switch self {
        case .capture: "Aufnehmen"
        case .create: "Erstellen"
        }
    }
}
