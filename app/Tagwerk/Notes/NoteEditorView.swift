import PhotosUI
import QuickLook
import SwiftUI
import TagwerkCore
import UniformTypeIdentifiers

/// One note as a full page: the rendered Markdown, or a text field to write it. It saves by itself: half a second after
/// the last keystroke and when the page closes; a note left without text is removed. Attachments (pictures, files) are
/// inserted as Markdown references at the cursor. It has no navigation stack of its own.
struct NoteEditorView: View {
    @Environment(AppEnvironment.self) var environment
    @Environment(\.dismiss) var dismiss
    let noteID: UUID
    let store: NoteStore
    /// Whether the page offers the assistant. The note in its own sheet (`NoteEditorSheet`) does not: the chat is a sheet
    /// over the tabs and cannot appear on top of another sheet.
    let showsAssistant: Bool

    enum Mode { case view, edit }

    @State var text = ""
    /// The text this page wrote to the store last, or loaded when it opened. A stored text that differs came from outside.
    @State var lastSavedText = ""
    @State var isLoaded = false
    @State var wasDeleted = false
    @State var selection: TextSelection?
    @State var mode: Mode = .edit
    @State var isChoosingPhotos = false
    @State var photoItems: [PhotosPickerItem] = []
    @State var isTakingPhoto = false
    @State var isChoosingFile = false
    @State var previewURL: URL?
    @State var shareURLs: [URL] = []
    @State var failureText: String?
    @State var isAddingToShopping = false
    @State var translation: RecipeTranslationModel?
    /// A hint after an action that ends in a sheet ("Als „…“ gesichert.", the result of the shopping list).
    @State var notice: String?

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
                                 attachmentDisplays: store.attachments?.displays(of: noteID) ?? [:],
                                 onToggleCheckbox: toggleCheckbox, onOpenAttachment: openAttachment)
            }
        }
    }

    /// The gratitude of a morning entry stays in the routine record; the editor only shows it above the text.
    @ViewBuilder private var gratitudeHeader: some View {
        let line = NotesListView.gratitudeLine(gratitude(of: store.note(id: noteID)))
        if !line.isEmpty {
            Text(line)
                .font(.subheadline).foregroundStyle(.secondary)
                .padding(.horizontal, 17).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var noticeBinding: Binding<Bool> {
        Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
    }

    // MARK: Actions

    /// Writes the text to the store. Every write of this page goes through here, so `lastSavedText` always names what the
    /// page stored itself (`NoteEditorSync`).
    func saveText() {
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

    // MARK: Texts

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
