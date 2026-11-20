import Foundation
import Testing
@testable import TagwerkCore

struct RecipeNoteTests {
    private let german = """
    # Linsencurry

    Portionen: 4

    ## Zutaten
    - 250 g rote Linsen
    - 1 Dose Kokosmilch (400 ml)
    - 2 Zwiebeln
    - Salz nach Geschmack

    ## Zubereitung
    1. Zwiebeln würfeln und andünsten.
    2. Linsen und Kokosmilch zugeben.

    Quelle: [chefkoch.de](https://www.chefkoch.de/rezepte/123)
    """

    @Test func parse_germanHeadings() throws {
        let note = try #require(RecipeNote.parse(german))
        #expect(note.title == "Linsencurry" && note.servings == 4)
        #expect(note.ingredients == ["250 g rote Linsen", "1 Dose Kokosmilch (400 ml)", "2 Zwiebeln", "Salz nach Geschmack"])
        #expect(note.steps == ["Zwiebeln würfeln und andünsten.", "Linsen und Kokosmilch zugeben."])
        #expect(note.sourceURL?.absoluteString == "https://www.chefkoch.de/rezepte/123")
    }

    @Test func parse_englishHeadings() throws {
        let note = try #require(RecipeNote.parse("""
        # Lentil curry
        Servings: 6
        ## INGREDIENTS
        * 250 g red lentils
        ## Directions
        1) Chop the onions.
        ## Source
        Source: https://example.com/curry
        """))
        #expect(note.title == "Lentil curry" && note.servings == 6)
        #expect(note.ingredients == ["250 g red lentils"] && note.steps == ["Chop the onions."])
        #expect(note.sourceURL?.absoluteString == "https://example.com/curry")
        let alternative = try #require(RecipeNote.parse("# Suppe\nPersonen: 2\n## Zutaten\n- Wasser\n## Anleitung\n- kochen"))
        #expect(alternative.servings == 2 && alternative.steps == ["kochen"])
    }

    @Test func parse_numberedIngredients() throws {
        let note = try #require(RecipeNote.parse("# X\n## Zutaten\n1. 2 Eier\n2. 100 g Mehl\n\n- [ ] 1 Prise Salz\n"))
        #expect(note.ingredients == ["2 Eier", "100 g Mehl", "1 Prise Salz"])
        // A number that belongs to the amount stays.
        #expect(RecipeNote.parse("## Zutaten\n2 Eier")?.ingredients == ["2 Eier"])
        #expect(RecipeNote.parse("## Zutaten\n2.5 kg Mehl")?.ingredients == ["2.5 kg Mehl"])
    }

    @Test func parse_missingServings() throws {
        let note = try #require(RecipeNote.parse("# Brot\n\n## Zutaten\n- 500 g Mehl"))
        #expect(note.servings == nil && note.steps.isEmpty && note.sourceURL == nil)
        // A title without "# ": the first line, as in `NoteText.title`.
        let plain = try #require(RecipeNote.parse("Pfannkuchen\n\n## Zutaten\n- Mehl"))
        #expect(plain.title == "Pfannkuchen")
    }

    @Test func parse_noIngredientsSection_isNil() {
        #expect(RecipeNote.parse("# Einkauf\n- Milch\n- Brot") == nil)
        #expect(RecipeNote.parse("# Brot\n## Zubereitung\n1. Backen") == nil)
        // The section exists but is empty.
        #expect(RecipeNote.parse("# Brot\n## Zutaten\n\n## Zubereitung\n1. Backen") == nil)
        #expect(RecipeNote.parse("") == nil)
    }

    @Test func parse_stopsAtNextHeading() throws {
        let note = try #require(RecipeNote.parse("""
        # Salat
        ## Zutaten
        - Gurke
        ## Tipps
        - Kalt servieren
        ## Notizen
        Mehr Dill.
        """))
        #expect(note.ingredients == ["Gurke"] && note.steps.isEmpty)
    }

    @Test func markdown_roundTrip() throws {
        let note = try #require(RecipeNote.parse(german))
        let written = note.markdown(language: .german)
        #expect(written == """
        # Linsencurry

        Portionen: 4

        ## Zutaten
        - 250 g rote Linsen
        - 1 Dose Kokosmilch (400 ml)
        - 2 Zwiebeln
        - Salz nach Geschmack

        ## Zubereitung
        1. Zwiebeln würfeln und andünsten.
        2. Linsen und Kokosmilch zugeben.

        Quelle: [chefkoch.de](https://www.chefkoch.de/rezepte/123)

        """)
        #expect(RecipeNote.parse(written) == note)
        // The headings follow the language that is asked for, and both languages read back.
        let english = note.markdown(language: .english)
        #expect(english.contains("Servings: 4") && english.contains("## Ingredients") && english.contains("## Instructions")
                && english.contains("Source: [chefkoch.de]"))
        #expect(RecipeNote.parse(english) == note)
    }

    @Test func markdown_sourceLinkOnlyWhenURL() {
        let withoutURL = RecipeNote(title: "Brot", ingredients: ["500 g Mehl"]).markdown(language: .german)
        #expect(!withoutURL.contains("Quelle") && !withoutURL.contains("Portionen") && !withoutURL.contains("Zubereitung"))
        #expect(withoutURL == "# Brot\n\n## Zutaten\n- 500 g Mehl\n")
        let withURL = RecipeNote(title: "Brot", ingredients: ["500 g Mehl"], sourceURL: URL(string: "https://www.example.com/brot"))
        #expect(withURL.markdown(language: .german).hasSuffix("Quelle: [example.com](https://www.example.com/brot)\n"))
        // Line breaks inside a step or ingredient do not break the layout.
        let multiline = RecipeNote(title: "A\nB", ingredients: ["1 Ei\n2 Eier"], steps: ["erst\nzweitens"]).markdown(language: .german)
        #expect(multiline.contains("# A B") && multiline.contains("- 1 Ei 2 Eier") && multiline.contains("1. erst zweitens"))
    }
}
