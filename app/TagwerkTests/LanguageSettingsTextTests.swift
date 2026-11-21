import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

struct LanguageSettingsTextTests {
    @Test func summary_auto_namesTheAppLanguage() {
        let languages = ContentLanguages(dictation: VoiceChatLanguage.automatic)
        #expect(LanguageSettingsText.summary(languages, locale: Locale(identifier: "de_DE")) == "Deutsch")
        #expect(LanguageSettingsText.summary(languages, locale: Locale(identifier: "en_GB")) == "English")
    }

    @Test func summary_fixed_namesIt() {
        let languages = ContentLanguages(dictation: "en-US")
        #expect(LanguageSettingsText.summary(languages, locale: Locale(identifier: "de_DE")) == "English")
        #expect(LanguageSettingsText.summary(ContentLanguages(dictation: "de-DE"), locale: Locale(identifier: "en_GB")) == "Deutsch")
    }

    @Test func name_isIndependentOfTheAppLanguageOfTheDevice() {
        #expect(LanguageSettingsText.name(.german) == "Deutsch")
        #expect(LanguageSettingsText.name(.english) == "English")
    }
}
