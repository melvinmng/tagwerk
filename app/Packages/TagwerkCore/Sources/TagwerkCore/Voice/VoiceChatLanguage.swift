import Foundation

/// The stored values of the dictation language ("Diktat", Einstellungen › Sprachen) and the helpers to read them. The key
/// `voiceRecognitionLanguage` once held the one shared "Sprache im Sprachchat" ("auto", "de-DE", "en-US"); since the
/// separate content languages (`ContentLanguages`) it is the dictation language only. It applies to
/// - speech recognition (dictation everywhere in the app, also in the voice mode),
/// - the language of the read-aloud voice when no answer language is fixed and the text gives no clear hint.
///
/// The language ChatGPT answers in during the voice mode is its own setting (`ContentLanguages.fixedAnswerLanguage`), derived
/// once from the former shared value. A typed chat keeps answering in the language the user writes.
public enum VoiceChatLanguage {
    /// The stored value that follows the language of the app.
    public static let automatic = "auto"

    /// The languages that can be chosen besides "Wie die App".
    public static var choices: [VoiceLanguage] { VoiceLanguage.allCases }

    /// The language a setting fixes, or `nil` for "auto" and for a value that is no supported language (written by a
    /// newer version or a damaged backup).
    public static func fixed(setting: String?) -> VoiceLanguage? {
        setting.flatMap(VoiceLanguage.init(rawValue:))
    }

    /// The language to use: the fixed one, or the app language in `locale`.
    public static func resolve(setting: String?, locale: Locale = .current) -> VoiceLanguage {
        fixed(setting: setting) ?? .from(locale: locale)
    }

    /// The sentence for the voice mode instructions. `nil` while the setting follows the user: then the base
    /// instruction applies, which answers in the language of the last message.
    public static func answerInstruction(for fixed: VoiceLanguage?) -> String? {
        guard let fixed else { return nil }
        return "Im Sprechmodus antwortest du immer auf \(fixed.promptName), auch wenn der Nutzer eine andere Sprache spricht."
    }
}
