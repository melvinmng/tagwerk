import Foundation
import Testing
@testable import TagwerkCore

struct RecipeTextTests {
    @Test func ingredients_fromJsonLd() {
        let html = """
        <html><head><title>Spaghetti</title>
        <script type="application/ld+json">
        {"@context": "https://schema.org", "@type": "Recipe", "name": "Spaghetti",
         "recipeIngredient": ["500 g Spaghetti", "2 Dosen Tomaten &amp; Basilikum", "  1 Zwiebel\\n"]}
        </script></head><body>Text</body></html>
        """
        #expect(RecipeText.ingredients(fromHTML: html) == ["500 g Spaghetti", "2 Dosen Tomaten & Basilikum", "1 Zwiebel"])
    }

    @Test func ingredients_fromGraph() {
        let html = """
        <script type='application/ld+json'>{"@graph": [{"@type": "WebSite", "name": "x"},
          {"@type": ["Article", "Recipe"], "recipeIngredient": ["1 Ei", "Salz"]}]}</script>
        """
        #expect(RecipeText.ingredients(fromHTML: html) == ["1 Ei", "Salz"])
        // A top-level array, a later block and a recipe in the main entity.
        let array = "<script type=\"application/ld+json\">[{\"@type\":\"Organization\"},{\"@type\":\"Recipe\",\"recipeIngredient\":[\"Mehl\"]}]</script>"
        #expect(RecipeText.ingredients(fromHTML: array) == ["Mehl"])
        let second = "<script type=\"application/ld+json\">{\"@type\":\"Person\"}</script><SCRIPT TYPE=\"application/ld+json\">{\"@type\":\"Recipe\",\"recipeIngredient\":[\"Öl\"]}</SCRIPT>"
        #expect(RecipeText.ingredients(fromHTML: second) == ["Öl"])
        let nested = "<script type=\"application/ld+json\">{\"@type\":\"WebPage\",\"mainEntity\":{\"@type\":\"Recipe\",\"recipeIngredient\":\"Butter\"}}</script>"
        #expect(RecipeText.ingredients(fromHTML: nested) == ["Butter"])
    }

    @Test func ingredients_missing_returnsNil() {
        #expect(RecipeText.ingredients(fromHTML: "<html><body>Kein Rezept</body></html>") == nil)
        #expect(RecipeText.ingredients(fromHTML: "<script type=\"application/ld+json\">{kaputt</script>") == nil)
        #expect(RecipeText.ingredients(fromHTML: "<script type=\"application/ld+json\">{\"@type\":\"Recipe\",\"name\":\"ohne Zutaten\"}</script>") == nil)
        #expect(RecipeText.ingredients(fromHTML: "<script type=\"application/ld+json\">{\"@type\":\"Recipe\",\"recipeIngredient\":[]}</script>") == nil)
        #expect(RecipeText.ingredients(fromHTML: "<script>{\"@type\":\"Recipe\",\"recipeIngredient\":[\"x\"]}</script>") == nil)
    }

    @Test func plainText_dropsScriptsAndNav() {
        let html = """
        <html><head><style>p { color: red }</style><script>var tracking = 1;</script></head><body>
        <header>Seitenkopf</header><nav><a href="/">Start</a><a href="/x">Rezepte</a></nav>
        <main><h1>Linsensuppe</h1><p>Für 4 Personen &amp; mehr.</p>
        <ul><li>200 g Linsen</li><li>1 L Br&uuml;he</li></ul><!-- Kommentar --></main>
        <footer>Impressum</footer><script>more()</script></body></html>
        """
        #expect(RecipeText.plainText(fromHTML: html) == "Linsensuppe\nFür 4 Personen & mehr.\n200 g Linsen\n1 L Brühe")
    }

    @Test func plainText_keepsInlineWordsTogether_andCollapsesSpace() {
        #expect(RecipeText.plainText(fromHTML: "<p>Ein  <b>fetter</b>\n\n   Text&nbsp;hier</p>") == "Ein fetter Text hier")
        #expect(RecipeText.plainText(fromHTML: "") == "")
    }

    @Test func limited_cutsAt8000() {
        let text = String(repeating: "ä", count: 9000)
        #expect(RecipeText.limited(text).count == 8000)
        #expect(RecipeText.limited("kurz") == "kurz")
        #expect(RecipeText.maximumLength == 8000)
    }
}
