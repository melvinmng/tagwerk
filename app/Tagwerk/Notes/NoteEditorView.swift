import SwiftUI
import TagwerkCore

/// One note as a full-page text field. It saves by itself: half a second after the last keystroke and when
/// the page closes; a note left without text is removed. It has no navigation stack of its own.
struct NoteEditorView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let noteID: UUID
    let store: NoteStore

    @State private var text = ""
    @State private var isLoaded = false
    @State private var wasDeleted = false
    @State private var selection: TextSelection?

    init(noteID: UUID, store: NoteStore) {
        self.noteID = noteID
        self.store = store
    }

    var body: some View {
        let note = store.note(id: noteID)
        VStack(alignment: .leading, spacing: 0) {
            // The gratitude of a morning entry stays in the routine record; the editor only shows it above the text.
            let gratitude = NotesListView.gratitudeLine(gratitude(of: note))
            if !gratitude.isEmpty {
                Text(gratitude)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(.horizontal, 17).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            TextEditor(text: $text, selection: $selection)
                .keyboardDoneButton()
                .padding(.horizontal, 12)
        }
            .navigationTitle(title(of: note))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
                                store.updateText(noteID, text: text)
                                store.completeSession(session.id)
                            } label: { Label("Bible Study abschließen", systemImage: "checkmark.circle") }
                        }
                        ShareLink(item: text) { Label("Teilen", systemImage: "square.and.arrow.up") }
                        // The trash is the way back, so deleting does not ask.
                        Button(role: .destructive) {
                            store.updateText(noteID, text: text)
                            wasDeleted = true
                            store.trash(noteID)
                            dismiss()
                        } label: { Label("Löschen", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Mehr")
                }
            }
            .onAppear {
                guard !isLoaded else { return }
                text = note?.text ?? ""
                isLoaded = true
                // A running Bible Study session starts with the cursor below its new section.
                if store.openSession(noteID: noteID) != nil { selection = TextSelection(insertionPoint: text.endIndex) }
            }
            // Debounced saving: every keystroke restarts the wait.
            .task(id: text) {
                guard isLoaded, !wasDeleted else { return }
                try? await Task.sleep(for: .milliseconds(500))
                if !Task.isCancelled { store.updateText(noteID, text: text) }
            }
            .onDisappear {
                guard isLoaded, !wasDeleted else { return }
                store.updateText(noteID, text: text)
                store.deleteIfEmpty(noteID)
            }
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
