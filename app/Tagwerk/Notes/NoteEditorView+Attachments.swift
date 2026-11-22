import PhotosUI
import SwiftUI
import TagwerkCore
import UniformTypeIdentifiers

/// The attachments of the note editor: the insert menu, the pickers' results and the reference that goes into the text.
extension NoteEditorView {
    var insertMenu: some View {
        NoteInsertMenu(onChoosePhoto: { isChoosingPhotos = true }, onTakePhoto: { isTakingPhoto = true },
                       onScanDocument: startScan, onPaste: { providers in Task { await addPasted(providers) } },
                       onChooseFile: { isChoosingFile = true }, onDrawing: {}, onTable: {})
    }

    // MARK: Scanning

    /// Opens the document camera (in the UI tests the test pages stand in for it).
    func startScan() {
        if let count = UITestMode.scanPageCount {
            addScan(pages: DocumentScanner.testPages(count: count))
        } else {
            inserts.isScanning = true
        }
    }

    /// Stores the scanned pages as one PDF, named by the day, and puts its reference at the cursor. No pages (the scan was
    /// cancelled) change nothing.
    func addScan(pages: [UIImage]) {
        guard !pages.isEmpty, let attachments = store.attachments else { return }
        let day = PlanDay(date: UITestMode.now(), calendar: environment.planning.calendar)
        let name = ScanPDFBuilder.fileName(for: day, existing: attachments.attachments(of: noteID).map(\.fileName))
        let pdf = ScanPDFBuilder.pdf(pages: pages)
        var scanID: UUID?
        run { () throws -> NoteAttachmentRecord in
            let record = try attachments.addData(pdf, fileName: name, type: .pdf, role: .scan, to: noteID, pageCount: pages.count)
            scanID = record.id
            return record
        } insert: { record in
            MarkdownText.reference(for: record.id, name: (name as NSString).deletingPathExtension, isImage: false)
        }
        if let scanID { recognizeText(ofScan: scanID) }
    }

    /// Recognises the text of a scan in the background; the page shows "Text erkannt" when it is done.
    func recognizeText(ofScan id: UUID) {
        guard let attachments = store.attachments else { return }
        ScanTextRecognition.start(for: id, store: attachments) { [inserts] in inserts.revision += 1 }
    }

    /// Starts recognition for the scans of this note that have none yet, e.g. after the app was closed during a run.
    func resumeTextRecognition() {
        for id in store.attachments?.scansAwaitingRecognition(of: noteID) ?? [] { recognizeText(ofScan: id) }
    }

    /// Puts the recognised text of a scan into the note as a paragraph below the reference. An own save of the page.
    func insertRecognizedText(ofScan id: UUID) {
        guard let recognized = store.attachments?.record(id: id)?.recognizedText, !recognized.isEmpty else { return }
        let updated = MarkdownText.insertingParagraph(recognized, belowReferenceTo: id, in: text)
        guard updated != text else { return }
        text = updated
        saveText()
    }

    /// The menu of a long press on a scan card in the page: open, rename, share.
    func attachmentMenu(for url: URL) -> UIMenu? {
        guard url.scheme?.lowercased() == MarkdownText.attachmentScheme, let id = HTMLSanitizer.attachmentID(inReference: url.absoluteString),
              let record = store.attachments?.record(id: id), record.roleRaw == NoteAttachmentStore.Role.scan.rawValue else { return nil }
        var actions = [UIAction(title: String(localized: "Öffnen"), image: UIImage(systemName: "doc.viewfinder")) { _ in openAttachment(id) }]
        if let recognized = record.recognizedText, !recognized.isEmpty {
            actions.append(UIAction(title: String(localized: "Erkannten Text einfügen"), image: UIImage(systemName: "text.append")) { _ in
                insertRecognizedText(ofScan: id)
            })
            actions.append(UIAction(title: String(localized: "Erkannten Text kopieren"), image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.string = recognized
            })
        } else if record.recognizedText != nil {
            // Recognition found nothing or failed: a new try.
            actions.append(UIAction(title: String(localized: "Text erkennen"), image: UIImage(systemName: "text.viewfinder")) { _ in
                if let attachments = store.attachments {
                    attachments.setRecognizedTextPending(for: id)
                    inserts.revision += 1
                    recognizeText(ofScan: id)
                }
            })
        }
        actions.append(UIAction(title: String(localized: "Umbenennen"), image: UIImage(systemName: "pencil")) { _ in
            inserts.renaming = NoteInsertState.Renaming(id: id, name: (record.fileName as NSString).deletingPathExtension)
        })
        actions.append(UIAction(title: String(localized: "Teilen"), image: UIImage(systemName: "square.and.arrow.up")) { _ in
            if let url = store.attachments?.exportURL(for: id) { inserts.sharing = NoteInsertState.Sharing(urls: [url]) }
        })
        return UIMenu(children: actions)
    }

    /// Renames a scan and the label of its reference in the text, so the page shows the new name. It is an own save of the page.
    func renameAttachment(_ id: UUID, to name: String) {
        guard let attachments = store.attachments else { return }
        attachments.rename(id, to: name)
        guard let renamed = attachments.record(id: id) else { return }
        text = MarkdownText.renamingReference(of: id, to: (renamed.fileName as NSString).deletingPathExtension, in: text)
        saveText()
        refreshShareURLs()
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
        let result = NoteInsertMenu.inserting(reference, into: text, replacing: range)
        text = result.text
        selection = TextSelection(insertionPoint: text.index(text.startIndex, offsetBy: result.cursorOffset))
        mode = .edit
        saveText()
        refreshShareURLs()
    }

    func refreshShareURLs() {
        shareURLs = store.attachments?.shareableURLs(of: noteID, text: text) ?? []
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
