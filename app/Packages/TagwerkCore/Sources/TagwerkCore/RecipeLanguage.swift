import Foundation

/// The language a recipe is created in: the title, the ingredients and the steps of an import, the headings of the
/// recipe note and the items that go on the shopping list. Chosen in the settings ("Sprache für Rezepte").
public enum RecipeLanguage {
    /// The stored value that follows the language of the app.
    public static let automatic = "auto"

    /// The languages that can be chosen: every language the app supports.
    public static var choices: [VoiceLanguage] { VoiceLanguage.allCases }

    /// The language for a stored setting. "auto" and a value that is no supported language (a setting written by a newer
    /// version, a damaged backup) follow the app language in `locale`.
    public static func resolve(setting: String?, locale: Locale = .current) -> VoiceLanguage {
        if let setting, let fixed = VoiceLanguage(rawValue: setting) { return fixed }
        return .from(locale: locale)
    }

    /// The name the language has in the request to ChatGPT: the model reads "Deutsch" or "English" as the target.
    public static func promptName(_ language: VoiceLanguage) -> String {
        switch language {
        case .german: "Deutsch"
        case .english: "English"
        }
    }
}
