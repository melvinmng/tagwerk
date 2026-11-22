import SwiftUI
import TagwerkCore

/// The "more" menu of the note editor.
extension NoteEditorView {
    func moreMenu(_ note: NoteRecord?) -> some View {
        Menu {
            // A way into writing without a gesture (the page also offers it as an accessibility action).
            if mode == .view, Self.usesTapToEdit {
                Button { beginEditing(atLine: nil) } label: { Label("Bearbeiten", systemImage: "pencil") }
            }
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

    /// A note of the folder "Rezepte" that is not locked offers "Zutaten auf die Einkaufsliste".
    func isRecipeNote(_ note: NoteRecord) -> Bool {
        guard note.kind == .free, !note.isLocked, let folderID = note.folderID else { return false }
        return store.folder(id: folderID)?.role == .recipes
    }
}
