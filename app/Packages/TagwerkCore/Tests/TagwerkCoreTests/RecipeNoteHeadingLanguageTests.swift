import Foundation
import Testing
@testable import TagwerkCore

struct RecipeNoteHeadingLanguageTests {
    @Test func germanHeading_isGerman() {
        #expect(RecipeNote.headingLanguage("# Suppe\n\n## Zutaten\n- Mehl\n") == .german)
        #expect(RecipeNote.headingLanguage("## zutaten:\n- Mehl") == .german)
    }

    @Test func englishHeading_isEnglish() {
        #expect(RecipeNote.headingLanguage("# Soup\n\n## Ingredients\n- flour\n") == .english)
    }

    @Test func noIngredientsHeading_isNil() {
        #expect(RecipeNote.headingLanguage("# Notes\n\nJust text.") == nil)
        #expect(RecipeNote.headingLanguage("## Zubereitung\n1. Kochen") == nil)
    }
}
