import Foundation
import Testing
@testable import TagwerkCore

struct RecipeLanguageTests {
    private let germanApp = Locale(identifier: "de_DE")
    private let englishApp = Locale(identifier: "en_GB")

    @Test func automatic_followsTheAppLanguage() {
        #expect(RecipeLanguage.resolve(setting: RecipeLanguage.automatic, locale: englishApp) == .english)
        #expect(RecipeLanguage.resolve(setting: "auto", locale: germanApp) == .german)
        // Every other iPhone language shows the app in German.
        #expect(RecipeLanguage.resolve(setting: "auto", locale: Locale(identifier: "fr_FR")) == .german)
    }

    @Test func fixedLanguage_winsOverTheAppLanguage() {
        // German recipes while the app is English, and the other way round.
        #expect(RecipeLanguage.resolve(setting: VoiceLanguage.german.rawValue, locale: englishApp) == .german)
        #expect(RecipeLanguage.resolve(setting: VoiceLanguage.english.rawValue, locale: germanApp) == .english)
    }

    @Test func unknownOrMissingSetting_followsTheAppLanguage() {
        #expect(RecipeLanguage.resolve(setting: "xx-XX", locale: englishApp) == .english)
        #expect(RecipeLanguage.resolve(setting: "", locale: germanApp) == .german)
        #expect(RecipeLanguage.resolve(setting: nil, locale: englishApp) == .english)
    }

    @Test func choices_offerEveryLanguageTheAppSupports() {
        #expect(Set(RecipeLanguage.choices) == [.german, .english])
        // Every choice survives a round trip through the stored value.
        for language in RecipeLanguage.choices {
            #expect(RecipeLanguage.resolve(setting: language.rawValue, locale: germanApp) == language)
        }
    }

    @Test func promptName_isTheLanguageNameInThatLanguage() {
        #expect(RecipeLanguage.promptName(.german) == "Deutsch")
        #expect(RecipeLanguage.promptName(.english) == "English")
    }
}
