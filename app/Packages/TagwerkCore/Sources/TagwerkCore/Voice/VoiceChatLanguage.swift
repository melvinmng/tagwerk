import Foundation

/// The preferred language of the voice chat ("Sprache im Sprachchat", Einstellungen › KI › Sprache). It replaces the old
/// setting "Erkennung in" and keeps its stored values, so nothing has to be migrated: "auto" ("Wie die App"), "de-DE" and
/// "en-US" mean what they meant before. The setting applies to
/// - speech recognition (dictation everywhere in the app, as before),
/// - the language ChatGPT is asked to answer in while the voice mode runs,
/// - the language of the read-aloud voice when the text itself gives no clear hint.
///
/// A typed chat keeps answering in the language the user writes.
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
