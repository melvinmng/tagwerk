import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// SP4b: the language switched to while dictating is remembered per place.
struct DictationPlaceStoreTests {
    private let german = Locale(identifier: "de_DE")

    private func settings(dictation: String = "de-DE") -> AppSettings {
        let settings = AppSettings()
        settings.voiceRecognitionLanguage = dictation
        return settings
    }

    @Test func rememberedLanguage_appliesToTheNextRecordingAtThisPlace() {
        let settings = settings()
        settings.rememberDictationLanguage(.english, at: .notes)
        #expect(settings.dictationLanguage(at: .notes) == .english)
        #expect(settings.voiceRecognitionLanguage == "de-DE", "the setting itself stays")
    }

    @Test func rememberedLanguage_doesNotChangeOtherPlaces() {
        let settings = settings()
        settings.rememberDictationLanguage(.english, at: .notes)
        for place in [DictationPlace.chat, .meal, .planning] {
            #expect(settings.dictationLanguage(at: place) == .german, "place \(place)")
        }
    }

    @Test func switchingBack_removesTheEntry() {
        let settings = settings()
        settings.rememberDictationLanguage(.english, at: .chat)
        settings.rememberDictationLanguage(.german, at: .chat)
        #expect(settings.dictationPlaceLanguagesData == nil)
        #expect(settings.dictationLanguage(at: .chat) == .german)
    }

    @Test func shoppingPlace_isNeverStoredInPlaces() {
        let settings = settings()
        settings.rememberDictationLanguage(.english, at: .shopping)
        #expect(settings.dictationPlaceLanguagesData == nil)
        #expect(settings.contentLanguages.places.isEmpty)
        // Its switch is the shopping language, which also dictation at that place reads.
        #expect(settings.shoppingLanguage == "en-US")
        #expect(settings.dictationLanguage(at: .shopping) == .english)
    }

    @Test func aChangedDictationSetting_keepsTheRememberedPlaces() {
        let settings = settings()
        settings.rememberDictationLanguage(.english, at: .notes)
        settings.voiceRecognitionLanguage = "en-US"
        #expect(settings.dictationLanguage(at: .notes) == .english)
        #expect(settings.dictationLanguage(at: .meal) == .english)
    }
}
