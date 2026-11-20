import SwiftUI
import TagwerkCore

/// "Rezept mit ChatGPT anlegen" in the folder "Rezepte": the same input and the same reading as "Rezept hinzufügen"
/// (photo, text, link; the same consent), then a confirmation that saves the result as a structured recipe note. The
/// shopping list is not touched; "Zutaten auf die Einkaufsliste" in the note leads there later.
struct RecipeNoteSaveSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: NoteStore
    /// Called with the new note after it was saved.
    let onSaved: (UUID) -> Void

    @State private var result: Found?

    /// The recipe found, identifiable for the navigation.
    struct Found: Identifiable, Hashable {
        let id = UUID()
        let recipe: RecipeImporter.Result
        static func == (lhs: Found, rhs: Found) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    var body: some View {
        NavigationStack {
            RecipeInputView(purpose: .saveOnly, model: nil) { recipe, _ in result = Found(recipe: recipe) }
                .navigationTitle("Rezept mit ChatGPT anlegen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                }
                .navigationDestination(item: $result) { found in
                    RecipeNoteSaveView(result: found.recipe, store: store) { id in
                        dismiss()
                        onSaved(id)
                    } onDiscard: {
                        dismiss()
                    }
                }
        }
        .presentationDetents([.large])
    }
}

/// The confirmation step: title, servings, ingredients and steps as they will be saved. Title and servings can be changed;
/// the rest is the recipe as it was read.
struct RecipeNoteSaveView: View {
    @Environment(AppEnvironment.self) private var environment
    let result: RecipeImporter.Result
    let store: NoteStore
    let onSaved: (UUID) -> Void
    let onDiscard: () -> Void

    @State private var title: String
    @State private var servings: Int?
    @State private var isSaving = false

    init(result: RecipeImporter.Result, store: NoteStore, onSaved: @escaping (UUID) -> Void, onDiscard: @escaping () -> Void) {
        self.result = result
        self.store = store
        self.onSaved = onSaved
        self.onDiscard = onDiscard
        _title = State(initialValue: result.title)
        _servings = State(initialValue: result.servings)
    }

    /// Saving needs a title; without servings a recipe is still saved (the question comes when it goes to the list).
    static func canSave(title: String) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var lines: [String] {
        result.candidates.map { RecipeNoteWriter.ingredientLine(for: $0, locale: result.language.locale) }
    }

    var body: some View {
        List {
            Section("Titel") {
                TextField("Titel", text: $title)
            }
            Section {
                ValueStepper("Portionen", value: $servings, start: RecipeResultView.startServings, in: RecipeResultView.servingsRange)
            } footer: {
                if servings == nil { Text("Im Rezept steht keine Portionszahl. Du kannst sie später in der Notiz ergänzen.") }
            }
            Section("Zutaten") {
                ForEach(Array(lines.enumerated()), id: \.offset) { Text($0.element) }
            }
            if !result.steps.isEmpty {
                Section("Zubereitung") {
                    ForEach(Array(result.steps.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                    }
                }
            }
            Section {} footer: {
                Text("Das Rezept wird als Notiz im Ordner „Rezepte“ gespeichert. Die Einkaufsliste bleibt unverändert.")
            }
        }
        .navigationTitle("Rezept speichern")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Verwerfen", action: onDiscard) }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: save) {
                Text("Rezept speichern").fontWeight(.semibold).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!Self.canSave(title: title) || isSaving)
            .padding()
            .background(.bar)
        }
    }

    private func save() {
        guard Self.canSave(title: title), !isSaving else { return }
        isSaving = true
        let note = RecipeNoteWriter.recipeNote(from: result, title: title, servings: servings)
        if let record = RecipeNoteWriter.save(note, language: result.language, store: store) {
            onSaved(record.id)
        } else {
            isSaving = false
        }
    }
}
