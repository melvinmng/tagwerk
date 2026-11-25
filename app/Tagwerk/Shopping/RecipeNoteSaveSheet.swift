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
        var reviser: RecipeReviser? = nil
        static func == (lhs: Found, rhs: Found) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    var body: some View {
        NavigationStack {
            RecipeInputView(purpose: .saveOnly, model: nil) { recipe, _, _, reviser in result = Found(recipe: recipe, reviser: reviser) }
                .navigationTitle("Rezept anlegen")
                .modifier(LargeTitleAtAccessibilitySizes())
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                }
                .navigationDestination(item: $result) { found in
                    RecipeNoteSaveView(result: found.recipe, reviser: found.reviser, store: store) { id in
                        dismiss()
                        onSaved(id)
                    } onDiscard: {
                        dismiss()
                    }
                }
        }
        .presentationDetents([.large])
        // A sheet does not take the forced text size of the UI test mode from the window; no effect outside that mode.
        .modifier(UITestAppearance())
    }
}

/// The inline title of a navigation bar is cut at accessibility text sizes; the large title wraps. Read where the view is
/// shown (not in the sheet itself), so the forced size of the UI test mode counts too.
private struct LargeTitleAtAccessibilitySizes: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .large : .inline)
    }
}

/// The confirmation step: title, servings, ingredients and steps as they will be saved. Title and servings can be changed;
/// the rest is the recipe as it was read.
struct RecipeNoteSaveView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let result: RecipeImporter.Result
    let store: NoteStore
    let onSaved: (UUID) -> Void
    let onDiscard: () -> Void

    @State private var title: String
    @State private var servings: Int?
    @State private var isSaving = false
    /// The ingredients as the user and ChatGPT left them (plan ki-vorschlaege-anpassen, task D2); what is saved is this state.
    @State private var draft: RecipeDraftModel

    init(result: RecipeImporter.Result, reviser: RecipeReviser? = nil, store: NoteStore, onSaved: @escaping (UUID) -> Void,
         onDiscard: @escaping () -> Void) {
        self.result = result
        self.store = store
        self.onSaved = onSaved
        self.onDiscard = onDiscard
        _draft = State(initialValue: RecipeDraftModel(result: result, reviser: reviser))
        _title = State(initialValue: result.title)
        _servings = State(initialValue: result.servings)
    }

    /// Saving needs a title; without servings a recipe is still saved (the question comes when it goes to the list).
    static func canSave(title: String) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var lines: [String] {
        draft.candidates.map { RecipeNoteWriter.ingredientLine(for: $0, locale: result.language.locale) }
    }

    var body: some View {
        List {
            Section {
                if dynamicTypeSize.isAccessibilitySize {
                    // A single line cuts a long title at accessibility sizes.
                    TextField("Titel", text: $title, axis: .vertical).lineLimit(1...5)
                } else {
                    TextField("Titel", text: $title)
                }
            } header: {
                Text("Titel")
                    .foregroundStyle(.secondaryText)
            }
            Section {
                ValueStepper("Portionen", value: $servings, start: RecipeResultView.startServings, in: RecipeResultView.servingsRange)
            } footer: {
                if servings == nil { Text("Im Rezept steht keine Portionszahl. Du kannst sie später in der Notiz ergänzen.").foregroundStyle(.secondaryText) }
            }
            Section {
                ForEach(Array(lines.enumerated()), id: \.offset) { Text($0.element) }
            } header: {
                Text("Zutaten")
                    .foregroundStyle(.secondaryText)
            }
            if draft.hasFollowUp {
                PreviewFollowUpSection(
                    model: draft.followUp,
                    availability: FollowUpAvailability.state(hasConsent: environment.settings.shoppingRecipeConsent,
                                                             isSignedIn: environment.ai.isSignedIn, isOffline: false),
                    place: .notes,
                    quickReplies: [String(localized: "Ohne Gewürze"), String(localized: "Mengen runden"), String(localized: "Fehlt etwas?")],
                    placeholder: "Zum Rezept etwas sagen …",
                    footer: Text("Senden gibt das Rezept (Text, Fotos oder der gelesene Text der Seite), die Zutaten mit deinen Änderungen und deine Nachricht an ChatGPT."),
                    focusLabel: { String(localized: "Zu: \($0.candidate.listName)") }, onSend: { message in Task { await draft.send(message) } })
            }
            if !draft.result.steps.isEmpty {
                Section {
                    ForEach(Array(draft.result.steps.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                    }
                } header: {
                    Text("Zubereitung")
                        .foregroundStyle(.secondaryText)
                }
            }
            Section {} footer: {
                Text("Das Rezept wird als Notiz im Ordner „Rezepte“ gespeichert. Die Einkaufsliste bleibt unverändert.")
                    .foregroundStyle(.secondaryText)
            }
        }
        .navigationTitle("Rezept speichern")
        .navigationBarTitleDisplayMode(.inline)
        // An answer that changes the title replaces the one the user did not touch.
        .onChange(of: draft.result.title) { old, new in if title == old { title = new } }
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
        let note = RecipeNoteWriter.recipeNote(from: draft.current, title: title, servings: servings)
        if let record = RecipeNoteWriter.save(note, language: result.language, store: store) {
            onSaved(record.id)
        } else {
            isSaving = false
        }
    }
}
