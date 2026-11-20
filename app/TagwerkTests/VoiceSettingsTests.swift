import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

struct VoiceSettingsTests {
    @Test func defaults() {
        let settings = AppSettings()
        #expect(settings.voiceInputEnabled)
        #expect(!settings.voiceExplained)
        #expect(settings.voiceRecognitionLanguage == "auto")
        #expect(settings.voiceReadAloud == ReadAloudPolicy.never.rawValue)
        #expect(settings.voiceGermanVoiceID == nil)
        #expect(settings.voiceAnnounceActions)
        #expect(settings.recipeLanguage == "auto")
    }

    @Test func recognitionLanguage_autoFollowsLocale() {
        #expect(VoiceAvailability.recognitionLanguage(setting: "auto", locale: Locale(identifier: "en_GB")) == .english)
        #expect(VoiceAvailability.recognitionLanguage(setting: "auto", locale: Locale(identifier: "fr_FR")) == .german)
        #expect(VoiceAvailability.recognitionLanguage(setting: "en-US", locale: Locale(identifier: "de_DE")) == .english)
    }

    /// "Sprache im Sprachchat" replaced "Erkennung in" and kept its stored values (#226).
    @Test func voiceChatLanguage_readsTheStoredRecognitionValues() {
        let english = Locale(identifier: "en_GB")
        let german = Locale(identifier: "de_DE")
        for (stored, locale, expected) in [("auto", german, VoiceLanguage.german), ("auto", english, .english),
                                           ("de-DE", english, .german), ("en-US", german, .english)] {
            #expect(VoiceAvailability.recognitionLanguage(setting: stored, locale: locale) == expected)
            #expect(VoiceChatLanguage.resolve(setting: stored, locale: locale) == expected)
        }
        #expect(VoiceChatLanguage.fixed(setting: AppSettings().voiceRecognitionLanguage) == nil)
    }

    @Test func voiceChatLanguage_survivesTheBackup() throws {
        let source = AppSettings()
        source.voiceRecognitionLanguage = "en-US"
        let data = try JSONEncoder().encode(AppSettingsBackup(source))
        let target = AppSettings()
        try JSONDecoder().decode(AppSettingsBackup.self, from: data).apply(to: target)
        #expect(target.voiceRecognitionLanguage == "en-US")
    }

    @Test func summaryLine() {
        #expect(VoiceAvailability.summary(inputEnabled: true, readAloud: "never") == "Mikrofon an, Vorlesen nie")
        #expect(VoiceAvailability.summary(inputEnabled: false, readAloud: "always") == "Mikrofon aus, Vorlesen immer")
    }
}
