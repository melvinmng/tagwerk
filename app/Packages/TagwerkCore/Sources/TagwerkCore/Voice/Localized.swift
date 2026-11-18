import Foundation

public extension VoiceLanguage {
    /// The language the app shows (the iPhone language when it is English, else German).
    static var app: VoiceLanguage { from(locale: .current) }
}

/// Texts of a String Catalog in a given language, independent of the app language (plan english-app, Task 2):
/// spoken announcements follow the language of the answer, the screen follows the app.
public enum Localized {
    public static func string(_ key: String.LocalizationValue, in language: VoiceLanguage, bundle: Bundle) -> String {
        String(localized: LocalizedStringResource(key, locale: language.locale, bundle: .atURL(bundle.bundleURL)))
    }
}
