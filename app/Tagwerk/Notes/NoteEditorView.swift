import PhotosUI
import QuickLook
import SwiftUI
import TagwerkCore
import UniformTypeIdentifiers

/// One note as a full page: the rendered Markdown, or a text field to write it. It saves by itself: half a second after
/// the last keystroke and when the page closes; a note left without text is removed. Attachments (pictures, files) are
/// inserted as Markdown references at the cursor. It has no navigation stack of its own.
struct NoteEditorView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let noteID: UUID
    let store: NoteStore
    /// Whether the page offers the assistant. The note in its own sheet (`NoteEditorSheet`) does not: the chat is a sheet
    /// over the tabs and cannot appear on top of another sheet.
    let showsAssistant: Bool

    private enum Mode { case view, edit }

    @State private var text = ""
    /// The text this page wrote to the store last, or loaded when it opened. A stored text that differs came from outside.
    @State private var lastSavedText = ""
    @State private var isLoaded = false
    @State private var wasDeleted = false
    @State private var selection: TextSelection?
    @State private var mode: Mode = .edit
    @State private var isChoosingPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isTakingPhoto = false
    @State private var isChoosingFile = false
    @State private var previewURL: URL?
    @State private var shareURLs: [URL] = []
    @State private var failureText: String?
    @State private var isAddingToShopping = false
    @State private var translation: RecipeTranslationModel?
    /// A hint after an action that ends in a sheet ("Als „…“ gesichert.", the result of the shopping list).
    @State private var notice: String?

    init(noteID: UUID, store: NoteStore, showsAssistant: Bool = true) {
        self.noteID = noteID
        self.store = store
        self.showsAssistant = showsAssistant
    }

    var body: some View {
        let note = store.note(id: noteID)
        content
            .navigationTitle(title(of: note))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        switchMode()
                    } label: {
                        Image(systemName: mode == .edit ? "eye" : "pencil")
                    }
                    .accessibilityLabel(mode == .edit ? "Ansicht" : "Bearbeiten")
                }
                if store.attachments != nil {
                    ToolbarItem(placement: .topBarTrailing) { attachMenu }
                    ToolbarItemGroup(placement: .keyboard) { attachMenu }
                }
                ToolbarItem(placement: .topBarTrailing) { moreMenu(note) }
            }
            // The page saves first, so the assistant reads what is on the screen.
            .noteAssistantEntry(.note(noteID), store: store, isEnabled: showsAssistant, beforeOpening: saveText)
            .photosPicker(isPresented: $isChoosingPhotos, selection: $photoItems, matching: .images)
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                photoItems = []
                Task { await addPhotos(items) }
            }
            .fullScreenCover(isPresented: $isTakingPhoto) {
                CameraPicker { image in
                    isTakingPhoto = false
                    if let image { add(image: image) }
                }
                .ignoresSafeArea()
            }
            .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { for url in urls { addFile(url) } }
            }
            .quickLookPreview($previewURL)
            .alert(failureText ?? "", isPresented: failureBinding) { Button("OK", role: .cancel) {} }
            .alert(notice ?? "", isPresented: noticeBinding) { Button("OK", role: .cancel) {} }
            .sheet(isPresented: $isAddingToShopping) {
                RecipeSheet(model: environment.shopping, onFinished: { notice = $0 }, start: .note(noteID))
            }
            .sheet(item: $translation) { model in
                RecipeTranslationSheet(model: model, store: store) { copy in
                    let title = NoteText.title(copy.text)
                    let shown = title.isEmpty ? String(localized: "Ohne Titel") : title
                    notice = String(localized: "Als „\(shown)“ gesichert.")
                }
            }
            .onAppear {
                guard !isLoaded else { return }
                text = note?.text ?? ""
                lastSavedText = text
                isLoaded = true
                // A new or empty note, a journal entry that is still the template and a running Bible Study session
                // open for writing; a note with text opens as a page.
                let isRunningSession = store.openSession(noteID: noteID) != nil
                let isUntouched = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || (note?.kind == .journal && JournalTemplate.isOnlyTemplate(text))
                    || (note?.kind == .free && RecipeNote.isOnlyTemplate(text))
                mode = isRunningSession || isUntouched ? .edit : .view
                // A running Bible Study session starts with the cursor below its new section.
                if isRunningSession { selection = TextSelection(insertionPoint: text.endIndex) }
                refreshShareURLs()
            }
            // Debounced saving: every keystroke restarts the wait.
            .task(id: text) {
                guard isLoaded, !wasDeleted else { return }
                try? await Task.sleep(for: .milliseconds(500))
                if !Task.isCancelled { saveText() }
            }
            // A change of the note from outside (the translation, a confirmed suggestion) replaces the text on this page;
            // otherwise the delayed save above would write the old text over it.
            .onChange(of: store.revision) { adoptStoredText() }
            .onDisappear {
                guard isLoaded, !wasDeleted else { return }
                saveText()
                // The camera and Quick Look cover this page; SwiftUI may report that as the page going away. The note is
                // neither an empty one to remove nor an attachment list to trim while one of them is open.
                guard !isTakingPhoto, previewURL == nil else { return }
                store.deleteIfEmpty(noteID)
                // An attachment goes only when its reference is gone from the saved text, not while the user is still writing.
                if store.note(id: noteID) != nil { store.attachments?.removeUnreferenced(noteID: noteID, text: text) }
            }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch mode {
        case .edit:
            VStack(alignment: .leading, spacing: 0) {
                gratitudeHeader
                TextEditor(text: $text, selection: $selection)
                    .keyboardDoneButton()
                    .padding(.horizontal, 12)
            }
        case .view:
            VStack(alignment: .leading, spacing: 0) {
                gratitudeHeader
                NoteMarkdownView(markdown: text, attachments: store.attachments,
                                 attachmentNames: Dictionary(uniqueKeysWithValues: (store.attachments?.attachments(of: noteID) ?? []).map { ($0.id, $0.fileName) }),
                                 onToggleCheckbox: toggleCheckbox, onOpenAttachment: openAttachment)
                    .padding(.horizontal, 16)
            }
        }
    }

    /// The gratitude of a morning entry stays in the routine record; the editor only shows it above the text.
    @ViewBuilder private var gratitudeHeader: some View {
        let line = NotesListView.gratitudeLine(gratitude(of: store.note(id: noteID)))
        if !line.isEmpty {
            Text(line)
                .font(.subheadline).foregroundStyle(.secondaryText)
                .padding(.horizontal, 17).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var attachMenu: some View {
        NoteAttachmentMenu(onChoosePhoto: { isChoosingPhotos = true }, onTakePhoto: { isTakingPhoto = true },
                           onPaste: { providers in Task { await addPasted(providers) } }, onChooseFile: { isChoosingFile = true })
    }

    private func moreMenu(_ note: NoteRecord?) -> some View {
        Menu {
            if let note {
                Button {
                    store.setPinned(noteID, !note.isPinned)
                } label: {
                    Label(note.isPinned ? "Anheftung lösen" : "Anheften", systemImage: note.isPinned ? "pin.slash" : "pin")
                }
            }
            if let session = store.openSession(noteID: noteID) {
                Button {
                    saveText()
                    store.completeSession(session.id)
                } label: { Label("Bible Study abschließen", systemImage: "checkmark.circle") }
            }
            if let note, isRecipeNote(note) {
                Button {
                    // The recipe sheet reads the saved text of the note.
                    saveText()
                    isAddingToShopping = true
                } label: { Label("Zutaten auf die Einkaufsliste", systemImage: "cart.badge.plus") }
            }
            if let note, RecipeTranslationModel.isOffered(note, store: store) {
                Button {
                    // The translation reads the saved text of the note.
                    saveText()
                    translation = RecipeTranslationModel(noteID: noteID, store: store, translator: environment.recipeTranslator,
                                                         recipeLanguage: environment.settings.resolvedRecipeLanguage)
                } label: { Label("Übersetzen …", systemImage: "globe") }
            }
            ShareLink(item: text) { Label("Teilen", systemImage: "square.and.arrow.up") }
            if !shareURLs.isEmpty {
                ShareLink(items: shareURLs) { Label("Anhänge teilen", systemImage: "paperclip") }
            }
            // The trash is the way back, so deleting does not ask.
            Button(role: .destructive) {
                saveText()
                wasDeleted = true
                store.trash(noteID)
                dismiss()
            } label: { Label("Löschen", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Mehr")
    }

    /// A note of the folder "Rezepte" offers "Zutaten auf die Einkaufsliste".
    private func isRecipeNote(_ note: NoteRecord) -> Bool {
        guard note.kind == .free, let folderID = note.folderID else { return false }
        return store.folder(id: folderID)?.role == .recipes
    }

    private var noticeBinding: Binding<Bool> {
        Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
    }

    // MARK: Actions

    /// Writes the text to the store. Every write of this page goes through here, so `lastSavedText` always names what the
    /// page stored itself (`NoteEditorSync`).
    private func saveText() {
        lastSavedText = text
        store.updateText(noteID, text: text)
    }

    /// Follows a change of the stored note that did not come from this page.
    private func adoptStoredText() {
        guard isLoaded, !wasDeleted else { return }
        let note = store.note(id: noteID)
        switch NoteEditorSync.resolution(local: text, lastSaved: lastSavedText, stored: note?.text, isTrashed: note?.deletedAt != nil) {
        case .keep: break
        case .adopt(let stored):
            text = stored
            lastSavedText = stored
            refreshShareURLs()
        case .close:
            wasDeleted = true
            dismiss()
        }
    }

    private func switchMode() {
        // Saving is immediate on a switch, so the list and the page never show an older text.
        saveText()
        mode = mode == .edit ? .view : .edit
        refreshShareURLs()
    }

    /// A tap on a checkbox of the page flips it in the text and saves.
    private func toggleCheckbox(_ index: Int) {
        let toggled = MarkdownText.togglingCheckbox(at: index, in: text)
        guard toggled != text else { return }
        text = toggled
        saveText()
    }

    private func openAttachment(_ id: UUID) {
        previewURL = store.attachments?.exportURL(for: id)
    }

    private func addPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                failureText = Self.message(for: .unreadable)
                continue
            }
            add(data: data)
        }
    }

    private func addPasted(_ providers: [NSItemProvider]) async {
        for provider in providers {
            guard let data = await Self.imageData(from: provider) else {
                failureText = Self.message(for: .unreadable)
                continue
            }
            add(data: data)
        }
    }

    /// The bytes of the picture on the clipboard, in the best image type the provider has.
    private static func imageData(from provider: NSItemProvider) async -> Data? {
        guard let type = provider.registeredTypeIdentifiers.compactMap(UTType.init).first(where: { $0.conforms(to: .image) }) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in continuation.resume(returning: data) }
        }
    }

    private func add(data: Data) {
        guard let attachments = store.attachments else { return }
        run { try attachments.addImage(data: data, to: noteID).id } insert: { id in
            MarkdownText.reference(for: id, name: String(localized: "Bild"), isImage: true)
        }
    }

    private func add(image: UIImage) {
        guard let attachments = store.attachments else { return }
        run { try attachments.addImage(image, to: noteID).id } insert: { id in
            MarkdownText.reference(for: id, name: String(localized: "Bild"), isImage: true)
        }
    }

    private func addFile(_ url: URL) {
        guard let attachments = store.attachments else { return }
        run { try attachments.addFile(at: url, to: noteID) } insert: { record in
            MarkdownText.reference(for: record.id, name: record.fileName, isImage: false)
        }
    }

    /// Stores an attachment and puts its reference into the text; shows a failure as an alert.
    private func run<Result>(_ store: () throws -> Result, insert reference: (Result) -> String) {
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
    private func insertReference(_ reference: String) {
        var range: Range<String.Index>?
        if case .selection(let selected)? = selection?.indices { range = selected }
        let result = NoteAttachmentMenu.inserting(reference, into: text, replacing: range)
        text = result.text
        selection = TextSelection(insertionPoint: text.index(text.startIndex, offsetBy: result.cursorOffset))
        mode = .edit
        saveText()
        refreshShareURLs()
    }

    private func refreshShareURLs() {
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

    private var failureBinding: Binding<Bool> {
        Binding(get: { failureText != nil }, set: { if !$0 { failureText = nil } })
    }

    private func gratitude(of note: NoteRecord?) -> [String] {
        guard let note, note.kind == .morning, let day = note.dayKey.flatMap(NoteDayKey.day) else { return [] }
        return environment.routines.value(day).gratitude
    }

    /// Thought notes name their origin and day; kind and day cannot be changed here.
    private func title(of note: NoteRecord?) -> String {
        guard let note, note.kind != .free else { return String(localized: "Notiz") }
        return NotesListView.footer(for: note, now: .now, calendar: environment.planning.calendar)
    }
}
