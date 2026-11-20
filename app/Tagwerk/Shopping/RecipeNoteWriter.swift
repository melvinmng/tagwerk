import Foundation
import TagwerkCore

extension AppSettings {
    /// The language recipes are created in (#216): the setting "Sprache für Rezepte", or the app language for "Wie die App".
    var resolvedRecipeLanguage: VoiceLanguage {
        RecipeLanguage.resolve(setting: recipeLanguage)
    }
}

/// Saves a recipe that was read (`RecipeImporter.Result`) as a structured note in the folder "Rezepte". Used by both ways
/// to a recipe note: "Rezept mit ChatGPT anlegen" in the notes, and the switch "Auch als Rezept-Notiz sichern" of the
/// shopping import. It writes only the note; the shopping list is never touched.
@MainActor
enum RecipeNoteWriter {
    /// The recipe as a note: the title and servings the user confirmed, all ingredients with their original amounts (the
    /// ones that are not put on a shopping list too), and the steps.
    static func recipeNote(from result: RecipeImporter.Result, title: String, servings: Int?) -> RecipeNote {
        RecipeNote(title: title.trimmingCharacters(in: .whitespacesAndNewlines), servings: servings,
                   ingredients: result.candidates.map { ingredientLine(for: $0, locale: result.language.locale) },
                   steps: result.steps, sourceURL: result.sourceURL)
    }

    /// "250 g rote Linsen": amount, unit and name in the order of a recipe, with a counted name or unit in the plural that
    /// its amount asks for ("2 Zwiebeln"). A free text such as "nach Geschmack" stands behind the name.
    static func ingredientLine(for candidate: RecipeImporter.Candidate, locale: Locale) -> String {
        if var line = candidate.line, line.amount != nil {
            line.name = candidate.name
            return RecipeScaler.agreed(line).formatted(locale: locale)
        }
        guard let quantity = candidate.quantity, !quantity.isEmpty else { return candidate.name }
        // A quantity with a number goes in front ("2 Dosen Tomaten"), a text behind the name ("Salz nach Geschmack").
        return IngredientLine.parse(quantity + " x").amount == nil ? candidate.name + " " + quantity : quantity + " " + candidate.name
    }

    /// Writes the note into the folder "Rezepte" (created if it is missing). `nil` when there is nothing to write.
    @discardableResult
    static func save(_ note: RecipeNote, language: VoiceLanguage, store: NoteStore) -> NoteRecord? {
        guard !note.ingredients.isEmpty else { return nil }
        let folder = store.ensureSystemFolder(.recipes, name: NoteStore.defaultFolderName(for: .recipes))
        return store.create(text: note.markdown(language: language), kind: .free, folderID: folder.id)
    }
}
