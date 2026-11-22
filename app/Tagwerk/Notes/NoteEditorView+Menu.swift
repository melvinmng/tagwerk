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
            if let note { lockItems(note) }
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

    /// "Sperren", "Sperre aufheben" and "Jetzt sperren" (NL2a, NL3a). Locking closes the page: the lock is not open for anything the
    /// owner did not check.
    @ViewBuilder
    func lockItems(_ note: NoteRecord) -> some View {
        let lock = environment.noteLock
        let privateFolders = NoteFolderRules.privateFolderIDs(in: store.folders().map(\.info))
        if note.isLocked {
            Button {
                saveText()
                lock.removeLock([noteID], store: store)
            } label: { Label("Sperre aufheben", systemImage: "lock.open") }
            Text(NoteLock.assistantNotice)
        } else if lock.canLock(note, privateFolderIDs: privateFolders) {
            Button {
                saveText()
                lock.requestLock([noteID], store: store, introFor: { lockIntroIDs = $0 })
                // Without the explanation the note is locked now: the page closes. With it, the sheet locks later.
                if !lock.needsIntro { dismiss() }
            } label: { Label("Sperren", systemImage: "lock") }
                .disabled(!lock.canAuthenticate)
            if !lock.canAuthenticate { Text("Richte zuerst einen Code für dein iPhone ein.") }
        }
        if lock.isUnlocked, lock.isProtected(note, privateFolderIDs: privateFolders) {
            Button { lock.lockNow() } label: { Label("Jetzt sperren", systemImage: "lock") }
        }
    }

    /// A note of the folder "Rezepte" that is not locked offers "Zutaten auf die Einkaufsliste".
    func isRecipeNote(_ note: NoteRecord) -> Bool {
        guard note.kind == .free, !note.isLocked, let folderID = note.folderID else { return false }
        return store.folder(id: folderID)?.role == .recipes
    }
}
