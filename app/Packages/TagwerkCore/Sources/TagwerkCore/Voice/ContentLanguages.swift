import Foundation

/// A place with a dictation field. The raw value is stored.
public enum DictationPlace: String, CaseIterable, Sendable {
    case notes, chat, meal, planning, shopping
}

/// Resolves the four content languages from their stored settings (Einstellungen › Sprachen). Pure; the app passes the
/// stored strings.
///
/// | Setting | Stored in | Values |
/// |---|---|---|
/// | Dictation | `voiceRecognitionLanguage` (the former shared value) | "auto", "de-DE", "en-US" |
/// | Voice chat answer | `voiceAnswerLanguage` | "spoken", "de-DE", "en-US"; `nil` before the takeover |
/// | Recipes | `recipeLanguage` | "auto", "de-DE", "en-US" |
/// | Shopping list | `shoppingLanguage` | "recipes", "auto", "de-DE", "en-US" |
/// | Switch at a place | `dictationPlaceLanguagesData` | place → "de-DE" / "en-US" |
public struct ContentLanguages: Equatable, Sendable {
    /// Voice chat answer: in the language the user speaks.
    public static let spoken = "spoken"
    /// Shopping list: follows the recipe language.
    public static let likeRecipes = "recipes"

    public var dictation: String
    public var answer: String?
    public var recipe: String
    public var shopping: String
    /// `DictationPlace.rawValue` → `VoiceLanguage.rawValue`.
    public var places: [String: String]

    public init(dictation: String = VoiceChatLanguage.automatic, answer: String? = nil,
                recipe: String = RecipeLanguage.automatic, shopping: String = ContentLanguages.likeRecipes,
                places: [String: String] = [:]) {
        self.dictation = dictation
        self.answer = answer
        self.recipe = recipe
        self.shopping = shopping
        self.places = places
    }

    // MARK: Dictation

    /// The language dictation uses at `place`: the shopping list uses its own language, another place its remembered
    /// switch, and everything else (also `nil`) the dictation setting. A stored value that is no supported language is ignored.
    public func dictationLanguage(at place: DictationPlace?, locale: Locale = .current) -> VoiceLanguage {
        if place == .shopping { return shoppingLanguage(locale: locale) }
        if let place, let stored = places[place.rawValue], let language = VoiceLanguage(rawValue: stored) { return language }
        return VoiceChatLanguage.resolve(setting: dictation, locale: locale)
    }

    /// The places after switching at `place` to `language`: the entry goes when it equals the dictation setting again.
    /// The shopping list never has an entry; its language is the shopping language.
    public func places(switching place: DictationPlace, to language: VoiceLanguage, locale: Locale = .current) -> [String: String] {
        guard place != .shopping else { return places }
        var updated = places
        if language == VoiceChatLanguage.resolve(setting: dictation, locale: locale) {
            updated.removeValue(forKey: place.rawValue)
        } else {
            updated[place.rawValue] = language.rawValue
        }
        return updated
    }

    public static func encodePlaces(_ places: [String: String]) -> Data? {
        places.isEmpty ? nil : try? JSONEncoder().encode(places)
    }

    public static func decodePlaces(_ data: Data?) -> [String: String] {
        data.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    // MARK: Voice chat

    /// The language the voice chat answers in; `nil` for "Wie gesprochen" (and for a value that is no supported language).
    public var fixedAnswerLanguage: VoiceLanguage? {
        answer.flatMap(VoiceLanguage.init(rawValue:))
    }

    /// The voice for read-aloud when the text gives no hint: the fixed answer language, else the dictation language.
    public func readAloudFallback(locale: Locale = .current) -> VoiceLanguage {
        fixedAnswerLanguage ?? VoiceChatLanguage.resolve(setting: dictation, locale: locale)
    }

    /// The value to store for the answer language of a settings object that has none yet: the fixed language of the former
    /// shared value, otherwise "spoken" (also for a value a newer version or a damaged backup wrote).
    public static func migratedAnswer(fromDictation setting: String) -> String {
        VoiceChatLanguage.fixed(setting: setting)?.rawValue ?? spoken
    }

    // MARK: Recipes and shopping

    public func recipeLanguage(locale: Locale = .current) -> VoiceLanguage {
        RecipeLanguage.resolve(setting: recipe, locale: locale)
    }

    /// The language of new shopping items: the recipe language, the app language, or a fixed one. A value that is none of
    /// these follows the recipes, like the default.
    public func shoppingLanguage(locale: Locale = .current) -> VoiceLanguage {
        switch shopping {
        case "auto": return .from(locale: locale)
        case Self.likeRecipes: return recipeLanguage(locale: locale)
        default: return VoiceLanguage(rawValue: shopping) ?? recipeLanguage(locale: locale)
        }
    }

    /// The second language of a recipe import; `nil` while list and recipe share one.
    public func shoppingLanguageIfDifferent(locale: Locale = .current) -> VoiceLanguage? {
        let shoppingLanguage = shoppingLanguage(locale: locale)
        return shoppingLanguage == recipeLanguage(locale: locale) ? nil : shoppingLanguage
    }
}
