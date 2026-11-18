import Foundation

public extension VoiceLanguage {
    /// The language the app shows (the iPhone language when it is English, else German).
    static var app: VoiceLanguage { from(locale: .current) }
}

public extension VoiceLanguage {
    /// How the (German) model prompts name the language to answer in; "auf \(promptName)" reads naturally for both.
    var promptName: String {
        switch self {
        case .german: "Deutsch"
        case .english: "Englisch (English)"
        }
    }

    /// Adjective for "kurzer … Name" in a prompt, in the nominative masculine form.
    var promptAdjective: String {
        switch self {
        case .german: "deutscher"
        case .english: "englischer"
        }
    }
}

/// Texts of a String Catalog in a given language, independent of the app language (plan english-app, Task 2):
/// spoken announcements follow the language of the answer, the screen follows the app.
public enum Localized {
    public static func string(_ key: String.LocalizationValue, in language: VoiceLanguage, bundle: Bundle) -> String {
        String(localized: LocalizedStringResource(key, locale: language.locale, bundle: .atURL(bundle.bundleURL)))
    }
}
