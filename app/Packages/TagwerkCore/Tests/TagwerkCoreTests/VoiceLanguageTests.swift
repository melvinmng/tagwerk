import Foundation
import Testing
@testable import TagwerkCore

struct VoiceLanguageTests {
    @Test func rawValues_andShortNames() {
        #expect(VoiceLanguage.german.rawValue == "de-DE")
        #expect(VoiceLanguage.english.rawValue == "en-US")
        #expect(VoiceLanguage.german.shortName == "DE")
        #expect(VoiceLanguage.english.shortName == "EN")
        #expect(VoiceLanguage.german.locale.language.languageCode?.identifier == "de")
        #expect(VoiceLanguage.english.locale.language.languageCode?.identifier == "en")
    }

    @Test func fromLocale_englishVariantsMapToEnglish_everythingElseToGerman() {
        #expect(VoiceLanguage.from(locale: Locale(identifier: "en_GB")) == .english)
        #expect(VoiceLanguage.from(locale: Locale(identifier: "en-US")) == .english)
        #expect(VoiceLanguage.from(locale: Locale(identifier: "de_AT")) == .german)
        #expect(VoiceLanguage.from(locale: Locale(identifier: "fr_FR")) == .german)
    }

    @Test func detect_recognisesGermanAndEnglish() {
        let german = "Bitte verschiebe meinen Termin auf morgen Nachmittag, weil ich krank bin."
        let english = "Please move my appointment to tomorrow afternoon because I am sick."
        #expect(VoiceLanguage.detect(german, fallback: .english) == .german)
        #expect(VoiceLanguage.detect(english, fallback: .german) == .english)
    }

    @Test func detect_shortTextFallsBack() {
        #expect(VoiceLanguage.detect("Hello there", fallback: .german) == .german)
        #expect(VoiceLanguage.detect("Hallo", fallback: .english) == .english)
        #expect(VoiceLanguage.detect("", fallback: .english) == .english)
    }

    @Test func detect_lowConfidenceFallsBack() {
        #expect(VoiceLanguage.detect("12 34 56 78", fallback: .english) == .english)
        #expect(VoiceLanguage.detect("12 34 56 78", fallback: .german) == .german)
    }
}
