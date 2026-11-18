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
    }

    @Test func recognitionLanguage_autoFollowsLocale() {
        #expect(VoiceAvailability.recognitionLanguage(setting: "auto", locale: Locale(identifier: "en_GB")) == .english)
        #expect(VoiceAvailability.recognitionLanguage(setting: "auto", locale: Locale(identifier: "fr_FR")) == .german)
        #expect(VoiceAvailability.recognitionLanguage(setting: "en-US", locale: Locale(identifier: "de_DE")) == .english)
    }

    @Test func summaryLine() {
        #expect(VoiceAvailability.summary(inputEnabled: true, readAloud: "never") == "Mikrofon an, Vorlesen nie")
        #expect(VoiceAvailability.summary(inputEnabled: false, readAloud: "always") == "Mikrofon aus, Vorlesen immer")
    }
}
