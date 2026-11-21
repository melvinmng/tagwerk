import Foundation
import Testing
@testable import TagwerkCore

struct ContentLanguagesTests {
    private let germanApp = Locale(identifier: "de_DE")
    private let englishApp = Locale(identifier: "en_GB")

    private func languages(dictation: String = "auto", answer: String? = nil, recipe: String = "auto",
                           shopping: String = ContentLanguages.likeRecipes, places: [String: String] = [:]) -> ContentLanguages {
        ContentLanguages(dictation: dictation, answer: answer, recipe: recipe, shopping: shopping, places: places)
    }

    // MARK: Takeover of the former shared value

    @Test func migration_auto_becomesSpoken() {
        #expect(ContentLanguages.migratedAnswer(fromDictation: "auto") == ContentLanguages.spoken)
    }

    @Test func migration_fixedLanguage_keepsAnswerLanguage() {
        #expect(ContentLanguages.migratedAnswer(fromDictation: "de-DE") == "de-DE")
        #expect(ContentLanguages.migratedAnswer(fromDictation: "en-US") == "en-US")
    }

    @Test func migration_unknownValue_becomesSpoken() {
        #expect(ContentLanguages.migratedAnswer(fromDictation: "xx-XX") == ContentLanguages.spoken)
        #expect(ContentLanguages.migratedAnswer(fromDictation: "") == ContentLanguages.spoken)
    }

    @Test func answer_spokenOrMissing_hasNoFixedLanguage() {
        #expect(languages(answer: nil).fixedAnswerLanguage == nil)
        #expect(languages(answer: ContentLanguages.spoken).fixedAnswerLanguage == nil)
        #expect(languages(answer: "xx-XX").fixedAnswerLanguage == nil)
        #expect(languages(answer: "en-US").fixedAnswerLanguage == .english)
    }

    // MARK: Dictation

    @Test func dictation_placeWithoutEntry_usesTheSetting() {
        let content = languages(dictation: "en-US")
        #expect(content.dictationLanguage(at: .notes, locale: germanApp) == .english)
        #expect(content.dictationLanguage(at: nil, locale: germanApp) == .english)
        #expect(languages().dictationLanguage(at: .chat, locale: englishApp) == .english)
    }

    @Test func dictation_placeWithEntry_winsOverTheSetting() {
        let content = languages(dictation: "de-DE", places: ["notes": "en-US"])
        #expect(content.dictationLanguage(at: .notes, locale: germanApp) == .english)
        // Other places and the setting itself stay as they are.
        #expect(content.dictationLanguage(at: .chat, locale: germanApp) == .german)
        #expect(content.dictationLanguage(at: nil, locale: germanApp) == .german)
    }

    @Test func dictation_shoppingPlace_isTheShoppingLanguage() {
        let content = languages(dictation: "de-DE", shopping: "en-US", places: ["shopping": "de-DE"])
        #expect(content.dictationLanguage(at: .shopping, locale: germanApp) == .english)
    }

    @Test func places_switchingBackToDefault_removesTheEntry() {
        let content = languages(dictation: "de-DE", places: ["notes": "en-US", "chat": "en-US"])
        let places = content.places(switching: .notes, to: .german, locale: germanApp)
        #expect(places == ["chat": "en-US"])
    }

    @Test func places_switchingAwayFromDefault_storesTheEntry() {
        let content = languages(dictation: "de-DE")
        #expect(content.places(switching: .meal, to: .english, locale: germanApp) == ["meal": "en-US"])
    }

    @Test func places_shoppingIsNeverStored() {
        let content = languages(dictation: "de-DE", places: ["notes": "en-US"])
        #expect(content.places(switching: .shopping, to: .english, locale: germanApp) == ["notes": "en-US"])
    }

    @Test func places_unknownStoredValue_isIgnored() {
        let content = languages(dictation: "en-US", places: ["notes": "xx-XX", "chat": ""])
        #expect(content.dictationLanguage(at: .notes, locale: germanApp) == .english)
        #expect(content.dictationLanguage(at: .chat, locale: germanApp) == .english)
    }

    @Test func placesData_roundTrips_andUnreadableDataIsEmpty() {
        let places = ["notes": "en-US", "meal": "de-DE"]
        #expect(ContentLanguages.decodePlaces(ContentLanguages.encodePlaces(places)) == places)
        #expect(ContentLanguages.encodePlaces([:]) == nil)
        #expect(ContentLanguages.decodePlaces(nil).isEmpty)
        #expect(ContentLanguages.decodePlaces(Data("no json".utf8)).isEmpty)
    }

    // MARK: Recipes and shopping

    @Test func shopping_likeRecipes_followsRecipeSetting() {
        let content = languages(recipe: "en-US", shopping: ContentLanguages.likeRecipes)
        #expect(content.shoppingLanguage(locale: germanApp) == .english)
        #expect(content.shoppingLanguageIfDifferent(locale: germanApp) == nil)
    }

    @Test func shopping_auto_followsAppLocale() {
        let content = languages(recipe: "de-DE", shopping: "auto")
        #expect(content.shoppingLanguage(locale: englishApp) == .english)
        #expect(content.shoppingLanguage(locale: germanApp) == .german)
    }

    @Test func shopping_fixed_isIndependentOfRecipes() {
        let content = languages(recipe: "en-US", shopping: "de-DE")
        #expect(content.shoppingLanguage(locale: englishApp) == .german)
        #expect(content.recipeLanguage(locale: germanApp) == .english)
        #expect(content.shoppingLanguageIfDifferent(locale: germanApp) == .german)
    }

    @Test func shopping_unknownStoredValue_followsRecipes() {
        let content = languages(recipe: "en-US", shopping: "xx-XX")
        #expect(content.shoppingLanguage(locale: germanApp) == .english)
    }

    @Test func shoppingIfDifferent_sameLanguage_isNil() {
        let content = languages(recipe: "de-DE", shopping: "auto")
        #expect(content.shoppingLanguageIfDifferent(locale: germanApp) == nil)
        #expect(content.shoppingLanguageIfDifferent(locale: englishApp) == .english)
    }

    // MARK: Read-aloud

    @Test func readAloudFallback_spoken_usesDictation() {
        let content = languages(dictation: "en-US", answer: ContentLanguages.spoken)
        #expect(content.readAloudFallback(locale: germanApp) == .english)
        #expect(languages(dictation: "auto", answer: nil).readAloudFallback(locale: englishApp) == .english)
    }

    @Test func readAloudFallback_fixedAnswer_winsOverDictation() {
        let content = languages(dictation: "de-DE", answer: "en-US")
        #expect(content.readAloudFallback(locale: germanApp) == .english)
    }
}
