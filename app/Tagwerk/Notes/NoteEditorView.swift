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
    @State private var confirmsDelete = false

    init(noteID: UUID, store: NoteStore) {
        self.noteID = noteID
        self.store = store
    }

    var body: some View {
        let note = store.note(id: noteID)
        TextEditor(text: $text)
            .keyboardDoneButton()
            .padding(.horizontal, 12)
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
                        Button(role: .destructive) { confirmsDelete = true } label: { Label("Löschen", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Mehr")
                }
            }
            .confirmationDialog("Notiz endgültig löschen?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    wasDeleted = true
                    store.delete(noteID)
                    dismiss()
                }
                Button("Abbrechen", role: .cancel) {}
            }
            .onAppear {
                guard !isLoaded else { return }
                text = note?.text ?? ""
                isLoaded = true
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

    /// Thought notes name their origin and day; kind and day cannot be changed here.
    private func title(of note: NoteRecord?) -> String {
        guard let note, note.kind != .free else { return String(localized: "Notiz") }
        return NotesListView.footer(for: note, now: .now, calendar: environment.planning.calendar)
    }
}
