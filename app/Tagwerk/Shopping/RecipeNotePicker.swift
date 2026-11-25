import SwiftUI
import TagwerkCore

/// The notes that can be the source of "Rezept hinzufügen": the notes of the folder "Rezepte" first, and any other note
/// of the user on request. Private notes (journal, Bible Study, Dream Log, and anything lying in such a folder) never
/// appear: a note is only ever sent to ChatGPT when the user picked it, and these are never offered.
enum RecipeNoteSource {
    struct Entry: Identifiable, Equatable {
        let id: UUID
        let title: String
        /// A recipe note with an ingredient section: it is read on the device.
        let isStructured: Bool
    }

    /// The notes of the folder "Rezepte", newest first.
    @MainActor
    static func recipeNotes(in store: NoteStore) -> [Entry] {
        guard let folder = store.folder(role: .recipes) else { return [] }
        return entries(store.notes(.folder(folder.id)), store: store)
    }

    /// All other notes the user may pick, newest first.
    @MainActor
    static func otherNotes(in store: NoteStore) -> [Entry] {
        let recipesFolderID = store.folder(role: .recipes)?.id
        return entries(store.notes(.all).filter { $0.folderID == nil || $0.folderID != recipesFolderID }, store: store)
    }

    /// Whether a note may be offered: a free note with text that does not lie in a private folder.
    @MainActor
    static func isOffered(_ note: NoteRecord, store: NoteStore) -> Bool {
        guard note.kind == .free, note.deletedAt == nil,
              !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return !store.isPrivate(note)
    }

    @MainActor
    private static func entries(_ notes: [NoteRecord], store: NoteStore) -> [Entry] {
        notes.filter { isOffered($0, store: store) }
            .sorted { $0.createdAt > $1.createdAt }
            .map { Entry(id: $0.id, title: NoteText.title($0.text).isEmpty ? String(localized: "Ohne Titel") : NoteText.title($0.text),
                         isStructured: RecipeNote.parse($0.text) != nil) }
    }
}

/// The part of the input form for the source "Notiz". The sheet with the other notes belongs to the form
/// (`RecipeOtherNotesSheet`), not to this section.
struct RecipeNoteSection: View {
    let store: NoteStore
    @Binding var selectedID: UUID?
    @Binding var showsOthers: Bool

    var body: some View {
        let recipes = RecipeNoteSource.recipeNotes(in: store)
        let selectedOther = selectedID.flatMap { id in recipes.contains { $0.id == id } ? nil : entry(for: id) }
        Section {
            if recipes.isEmpty, selectedOther == nil {
                Text("Im Ordner „Rezepte“ ist noch keine Notiz.").foregroundStyle(.secondaryText)
            }
            ForEach(recipes) { row($0) }
            if let selectedOther { row(selectedOther) }
            Button { showsOthers = true } label: { Label("Andere Notiz wählen …", systemImage: "note.text") }
        } header: {
            Text("Notiz")
                .foregroundStyle(.secondaryText)
        } footer: {
            Text("Eine Notiz mit den Abschnitten „Zutaten“ und „Zubereitung“ liest Tagwerk auf dem iPhone. Jede andere Notiz liest ChatGPT, nachdem du „Zutaten holen“ getippt hast.")
                .foregroundStyle(.secondaryText)
        }
    }

    private func entry(for id: UUID) -> RecipeNoteSource.Entry? {
        guard let note = store.note(id: id), RecipeNoteSource.isOffered(note, store: store) else { return nil }
        return RecipeNoteSource.Entry(id: id, title: NoteText.title(note.text), isStructured: RecipeNote.parse(note.text) != nil)
    }

    private func row(_ entry: RecipeNoteSource.Entry) -> some View {
        Button { selectedID = entry.id } label: { RecipeNoteRowLabel(entry: entry, isOn: selectedID == entry.id) }
            .accessibilityAddTraits(selectedID == entry.id ? .isSelected : [])
    }
}

private struct RecipeNoteRowLabel: View {
    let entry: RecipeNoteSource.Entry
    let isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle").foregroundStyle(isOn ? Color.accentColor : Color.secondaryText)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).foregroundStyle(.primary)
                // A fixed grey: the hierarchical `.secondary` takes the tint of the button around it and fails the contrast audit.
                Text(entry.isStructured ? "strukturiert" : "wird mit ChatGPT gelesen").font(.subheadline).foregroundStyle(Color.secondaryText)
            }
            Spacer(minLength: 0)
        }
    }
}

/// "Andere Notiz wählen …": every note the user may pick, as a sheet of the input form.
struct RecipeOtherNotesSheet: View {
    let store: NoteStore
    @Binding var selectedID: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let entries = RecipeNoteSource.otherNotes(in: store)
        NavigationStack {
            List(entries) { entry in
                Button {
                    selectedID = entry.id
                    dismiss()
                } label: { RecipeNoteRowLabel(entry: entry, isOn: selectedID == entry.id) }
            }
            .overlay {
                if entries.isEmpty { Text("Keine Notizen vorhanden.").foregroundStyle(.secondaryText) }
            }
            .navigationTitle("Andere Notiz wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        }
    }
}
