import PhotosUI
import SwiftUI
import TagwerkCore
import UniformTypeIdentifiers

/// The attachments of the note editor: the paperclip menu, the pickers' results and the reference that goes into the text.
extension NoteEditorView {
    var attachMenu: some View {
        NoteAttachmentMenu(onChoosePhoto: { isChoosingPhotos = true }, onTakePhoto: { isTakingPhoto = true },
                           onPaste: { providers in Task { await addPasted(providers) } }, onChooseFile: { isChoosingFile = true })
    }

    // MARK: Actions

    func addPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                failureText = Self.message(for: .unreadable)
                continue
            }
            add(data: data)
        }
    }

    func addPasted(_ providers: [NSItemProvider]) async {
        for provider in providers {
            guard let data = await Self.imageData(from: provider) else {
                failureText = Self.message(for: .unreadable)
                continue
            }
            add(data: data)
        }
    }

    /// The bytes of the picture on the clipboard, in the best image type the provider has.
    static func imageData(from provider: NSItemProvider) async -> Data? {
        guard let type = provider.registeredTypeIdentifiers.compactMap(UTType.init).first(where: { $0.conforms(to: .image) }) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in continuation.resume(returning: data) }
        }
    }

    func add(data: Data) {
        guard let attachments = store.attachments else { return }
        run { try attachments.addImage(data: data, to: noteID).id } insert: { id in
            MarkdownText.reference(for: id, name: String(localized: "Bild"), isImage: true)
        }
    }

    func add(image: UIImage) {
        guard let attachments = store.attachments else { return }
        run { try attachments.addImage(image, to: noteID).id } insert: { id in
            MarkdownText.reference(for: id, name: String(localized: "Bild"), isImage: true)
        }
    }

    func addFile(_ url: URL) {
        guard let attachments = store.attachments else { return }
        run { try attachments.addFile(at: url, to: noteID) } insert: { record in
            MarkdownText.reference(for: record.id, name: record.fileName, isImage: false)
        }
    }

    /// Stores an attachment and puts its reference into the text; shows a failure as an alert.
    func run<Result>(_ store: () throws -> Result, insert reference: (Result) -> String) {
        do {
            let result = try store()
            insertReference(reference(result))
        } catch let failure as NoteAttachmentStore.Failure {
            failureText = Self.message(for: failure)
        } catch {
            failureText = Self.message(for: .unreadable)
        }
    }

    /// Inserts the reference at the cursor (at the end without one) and switches to writing, so the user sees where it went.
    func insertReference(_ reference: String) {
        var range: Range<String.Index>?
        if case .selection(let selected)? = selection?.indices { range = selected }
        let result = NoteAttachmentMenu.inserting(reference, into: text, replacing: range)
        text = result.text
        selection = TextSelection(insertionPoint: text.index(text.startIndex, offsetBy: result.cursorOffset))
        mode = .edit
        saveText()
        refreshShareURLs()
    }

    func refreshShareURLs() {
        let referenced = MarkdownText.attachmentIDs(in: text)
        shareURLs = (store.attachments?.attachments(of: noteID) ?? []).filter { referenced.contains($0.id) }
            .compactMap { store.attachments?.exportURL(for: $0.id) }
    }

    // MARK: Texts

    static func message(for failure: NoteAttachmentStore.Failure) -> String {
        switch failure {
        case .tooLarge: String(localized: "Die Datei ist größer als \(NoteAttachmentStore.maximumFileBytes / 1_048_576) MB und lässt sich nicht anhängen.")
        case .notAnImage: String(localized: "Das ist kein Bild, das sich anhängen lässt.")
        case .unreadable: String(localized: "Die Datei ließ sich nicht lesen.")
        }
    }
}
