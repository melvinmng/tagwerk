import Foundation
import Testing
@testable import TagwerkCore

struct MarkdownTextTests {
    @Test func plainText_stripsHeadingsListsAndEmphasis() {
        let markdown = """
        # Einkauf
        ## Unterpunkt
        > Zitat
        - Milch
        * **Brot** und __Butter__
        + ~~Käse~~
        1. Erstens
        2) Zweitens
        - [ ] offen
        - [x] erledigt
        Das ist *kursiv* und _auch kursiv_ und `Code`.
        """
        #expect(MarkdownText.plainText(markdown).split(separator: "\n", omittingEmptySubsequences: false).map(String.init) == [
            "Einkauf", "Unterpunkt", "Zitat", "Milch", "Brot und Butter", "Käse", "Erstens", "Zweitens", "offen", "erledigt",
            "Das ist kursiv und auch kursiv und Code."
        ])
    }

    @Test func plainText_keepsWordsThatOnlyLookLikeMarkup() {
        #expect(MarkdownText.plainText("snake_case_name und 2 * 3 * 4") == "snake_case_name und 2 * 3 * 4")
        #expect(MarkdownText.plainText("#Hashtag bleibt") == "#Hashtag bleibt")
        #expect(MarkdownText.plainText("-5 Grad") == "-5 Grad")
    }

    @Test func plainText_linkKeepsText_imageVanishes() {
        #expect(MarkdownText.plainText("Siehe [die Seite](https://example.com/x?a=1) hier") == "Siehe die Seite hier")
        #expect(MarkdownText.plainText("Vorher ![Bild](attachment:3F2504E0-4F89-41D3-9A0C-0305E82C3301) nachher") == "Vorher  nachher")
        #expect(MarkdownText.plainText("[Rechnung.pdf](attachment:3F2504E0-4F89-41D3-9A0C-0305E82C3301)") == "Rechnung.pdf")
        #expect(MarkdownText.plainText("![nur ein Bild](attachment:3F2504E0-4F89-41D3-9A0C-0305E82C3301)").isEmpty)
    }

    @Test func plainText_stripsHtmlTagsAndDecodesEntities() {
        #expect(MarkdownText.plainText("<b>Fett</b> &amp; <i>schräg</i> &lt;ok&gt; &#65;&#x42;") == "Fett & schräg <ok> AB")
        #expect(MarkdownText.plainText("<script>alert(1)</script>Text") == "alert(1)Text")
        #expect(MarkdownText.plainText("a<!-- Kommentar -->b") == "ab")
        #expect(MarkdownText.plainText("&unbekannt; bleibt") == "&unbekannt; bleibt")
    }

    @Test func plainText_tableRowsBecomeWords() {
        let table = "| Name | Menge |\n|---|---|\n| Milch | 2 |"
        #expect(MarkdownText.plainText(table) == "Name Menge\n\nMilch 2")
        #expect(MarkdownText.plainText("| a | b |") == "a b")
    }

    @Test func plainText_codeBlockKeepsItsLines_andHorizontalRulesVanish() {
        let markdown = "Vorher\n```swift\nlet x = *a*\n- kein Punkt\n```\n---\nNachher"
        #expect(MarkdownText.plainText(markdown) == "Vorher\n\nlet x = *a*\n- kein Punkt\n\n\nNachher")
    }

    @Test func plainText_keepsTheLineCount() {
        let markdown = "a\n\n# b\n![x](y)\n"
        #expect(MarkdownText.plainText(markdown).split(separator: "\n", omittingEmptySubsequences: false).count
                == markdown.split(separator: "\n", omittingEmptySubsequences: false).count)
    }

    // MARK: Attachments

    private let first = UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301")!
    private let second = UUID(uuidString: "A1B2C3D4-0000-4000-8000-000000000002")!

    @Test func attachmentIDs_findsImagesAndLinks() {
        let markdown = """
        ![Bild](attachment:3F2504E0-4F89-41D3-9A0C-0305E82C3301)
        und [Datei.pdf](ATTACHMENT:a1b2c3d4-0000-4000-8000-000000000002)
        <img src="attachment:3F2504E0-4F89-41D3-9A0C-0305E82C3301">
        """
        #expect(MarkdownText.attachmentIDs(in: markdown) == [first, second])
    }

    @Test func attachmentIDs_ignoresOtherSchemes() {
        let markdown = """
        [x](https://example.com/attachment:3F2504E0-4F89-41D3-9A0C-0305E82C3301)
        [y](file:attachment:3F2504E0-4F89-41D3-9A0C-0305E82C3301)
        ![z](attachment:kein-uuid)
        3F2504E0-4F89-41D3-9A0C-0305E82C3301
        """
        #expect(MarkdownText.attachmentIDs(in: markdown).isEmpty)
    }

    @Test func reference_buildsImageAndFileReferences_andEscapesBrackets() {
        #expect(MarkdownText.reference(for: first, name: "Bild", isImage: true) == "![Bild](attachment:3F2504E0-4F89-41D3-9A0C-0305E82C3301)")
        let file = MarkdownText.reference(for: first, name: "Plan [v2] (neu).pdf", isImage: false)
        #expect(file == "[Plan \\[v2\\] \\(neu\\).pdf](attachment:3F2504E0-4F89-41D3-9A0C-0305E82C3301)")
        // The reference is found again.
        #expect(MarkdownText.attachmentIDs(in: file) == [first])
    }

    // MARK: Checkboxes

    @Test func togglingCheckbox_secondBoxFlips() {
        let markdown = "- [ ] eins\n- [x] zwei\n  * [ ] drei"
        #expect(MarkdownText.togglingCheckbox(at: 1, in: markdown) == "- [ ] eins\n- [ ] zwei\n  * [ ] drei")
        #expect(MarkdownText.togglingCheckbox(at: 2, in: markdown) == "- [ ] eins\n- [x] zwei\n  * [x] drei")
        #expect(MarkdownText.togglingCheckbox(at: 0, in: "+ [X] groß") == "+ [ ] groß")
        #expect(MarkdownText.togglingCheckbox(at: 0, in: "> - [ ] im Zitat") == "> - [x] im Zitat")
        #expect(MarkdownText.checkboxCount(in: markdown) == 3)
    }

    @Test func togglingCheckbox_skipsCodeBlocks() {
        let markdown = "- [ ] vorher\n```\n- [ ] im Code\n```\n- [ ] nachher"
        #expect(MarkdownText.checkboxCount(in: markdown) == 2)
        #expect(MarkdownText.togglingCheckbox(at: 1, in: markdown) == "- [ ] vorher\n```\n- [ ] im Code\n```\n- [x] nachher")
    }

    @Test func togglingCheckbox_outOfRange_returnsTextUnchanged() {
        let markdown = "- [ ] eins\nText [ ] kein Punkt\n-[ ] kein Leerzeichen"
        #expect(MarkdownText.togglingCheckbox(at: 1, in: markdown) == markdown)
        #expect(MarkdownText.togglingCheckbox(at: -1, in: markdown) == markdown)
        #expect(MarkdownText.togglingCheckbox(at: 0, in: "") == "")
    }

    @Test func togglingCheckbox_keepsWindowsLineEndings() {
        #expect(MarkdownText.togglingCheckbox(at: 0, in: "- [ ] a\r\n- [ ] b") == "- [x] a\r\n- [ ] b")
    }
}
