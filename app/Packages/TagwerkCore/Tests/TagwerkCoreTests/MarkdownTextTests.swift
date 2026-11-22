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

    @Test func attachmentReferences_keepDocumentOrderWithoutRepeats() {
        let markdown = "[b](attachment:A1B2C3D4-0000-4000-8000-000000000002) ![a](attachment:3F2504E0-4F89-41D3-9A0C-0305E82C3301) ![a](attachment:3F2504E0-4F89-41D3-9A0C-0305E82C3301)"
        #expect(MarkdownText.attachmentReferences(in: markdown) == [second, first])
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
        #expect(MarkdownText.togglingCheckbox(at: 0, in: "1. [ ] numeriert") == "1. [x] numeriert")
        #expect(MarkdownText.checkboxCount(in: markdown) == 3)
    }

    @Test func togglingCheckbox_skipsCodeBlocks() {
        let markdown = "- [ ] vorher\n```\n- [ ] im Code\n```\n- [ ] nachher"
        #expect(MarkdownText.checkboxCount(in: markdown) == 2)
        #expect(MarkdownText.togglingCheckbox(at: 1, in: markdown) == "- [ ] vorher\n```\n- [ ] im Code\n```\n- [x] nachher")
    }

    @Test func togglingCheckbox_outOfRange_returnsTextUnchanged() {
        let markdown = "- [ ] eins\nText [ ] kein Punkt\n-[ ] kein Leerzeichen\n- [ ]\n> - [ ] im Zitat"
        #expect(MarkdownText.togglingCheckbox(at: 1, in: markdown) == markdown)
        #expect(MarkdownText.togglingCheckbox(at: -1, in: markdown) == markdown)
        #expect(MarkdownText.togglingCheckbox(at: 0, in: "") == "")
    }

    @Test func togglingCheckbox_keepsWindowsLineEndings() {
        #expect(MarkdownText.togglingCheckbox(at: 0, in: "- [ ] a\r\n- [ ] b") == "- [x] a\r\n- [ ] b")
    }

    // MARK: Replacing attachment IDs

    @Test func replacingAttachmentIDs_imageAndFileReference() {
        let oldImage = UUID(), oldFile = UUID(), newImage = UUID(), newFile = UUID()
        let text = "Foto\n![Dish](attachment:\(oldImage.uuidString))\nSiehe [Rechnung.pdf](attachment:\(oldFile.uuidString.lowercased())) und noch einmal ![Dish](attachment:\(oldImage.uuidString))"
        let result = MarkdownText.replacingAttachmentIDs(in: text, with: [oldImage: newImage, oldFile: newFile])
        #expect(result == "Foto\n![Dish](attachment:\(newImage.uuidString))\nSiehe [Rechnung.pdf](attachment:\(newFile.uuidString)) und noch einmal ![Dish](attachment:\(newImage.uuidString))")
        #expect(MarkdownText.attachmentIDs(in: result) == [newImage, newFile])
    }

    @Test func replacingAttachmentIDs_unknownIDStays() {
        let known = UUID(), unknown = UUID(), replacement = UUID()
        let text = "[a](attachment:\(known.uuidString)) [b](attachment:\(unknown.uuidString)) https://example.com/attachment:\(known.uuidString)"
        let result = MarkdownText.replacingAttachmentIDs(in: text, with: [known: replacement])
        #expect(result == "[a](attachment:\(replacement.uuidString)) [b](attachment:\(unknown.uuidString)) https://example.com/attachment:\(known.uuidString)")
        #expect(MarkdownText.replacingAttachmentIDs(in: text, with: [:]) == text)
    }

    @Test func renamingReference_replacesTheLabelOfOneAttachment() {
        let scan = UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301")!
        let other = UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3302")!
        let text = "Vor\n[Scan 20.11.2026](attachment:3F2504E0-4F89-41D3-9A0C-0305E82C3301)\n![Bild](attachment:3F2504E0-4F89-41D3-9A0C-0305E82C3302)\n"
            + "Nochmal [Scan 20.11.2026](ATTACHMENT:3f2504e0-4f89-41d3-9a0c-0305e82c3301) und [Link](https://example.com)"
        let renamed = MarkdownText.renamingReference(of: scan, to: "Mietvertrag [neu]", in: text)
        #expect(renamed == "Vor\n[Mietvertrag \\[neu\\]](attachment:3F2504E0-4F89-41D3-9A0C-0305E82C3301)\n![Bild](attachment:3F2504E0-4F89-41D3-9A0C-0305E82C3302)\n"
            + "Nochmal [Mietvertrag \\[neu\\]](ATTACHMENT:3f2504e0-4f89-41d3-9a0c-0305e82c3301) und [Link](https://example.com)")
        #expect(MarkdownText.attachmentIDs(in: renamed) == [scan, other])
        // Nothing to rename: the text stays as it is.
        #expect(MarkdownText.renamingReference(of: UUID(), to: "X", in: text) == text)
    }

    @Test func renamingReference_keepsPictureReferencesAndEscapedLabels() {
        let id = UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301")!
        let original = MarkdownText.reference(for: id, name: "Plan [v2] (neu).pdf", isImage: false)
        let renamed = MarkdownText.renamingReference(of: id, to: "Anlage", in: "a " + original + " b")
        #expect(renamed == "a [Anlage](attachment:3F2504E0-4F89-41D3-9A0C-0305E82C3301) b")
        let picture = MarkdownText.reference(for: id, name: "Zeichnung", isImage: true)
        #expect(MarkdownText.renamingReference(of: id, to: "Skizze", in: picture) == "![Skizze](attachment:3F2504E0-4F89-41D3-9A0C-0305E82C3301)")
    }

    @Test func insertRecognizedText_putsParagraphBelowReference() {
        let id = UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301")!
        let reference = "[Scan](attachment:3F2504E0-4F89-41D3-9A0C-0305E82C3301)"
        // Between two lines: the paragraph gets blank lines on both sides.
        #expect(MarkdownText.insertingParagraph("Erkannt\nin zwei Zeilen", belowReferenceTo: id, in: "Vor\n\(reference)\nNach")
            == "Vor\n\(reference)\n\nErkannt\nin zwei Zeilen\n\nNach")
        // At the end of the text.
        #expect(MarkdownText.insertingParagraph("Erkannt", belowReferenceTo: id, in: reference) == "\(reference)\n\nErkannt")
        // With a blank line below the reference already.
        #expect(MarkdownText.insertingParagraph("Erkannt", belowReferenceTo: id, in: "\(reference)\n\nNach") == "\(reference)\n\nErkannt\n\nNach")
        // Surrounding whitespace of the paragraph goes.
        #expect(MarkdownText.insertingParagraph("  Erkannt \n\n", belowReferenceTo: id, in: reference) == "\(reference)\n\nErkannt")
        // No reference, another attachment or no text: nothing changes.
        #expect(MarkdownText.insertingParagraph("Erkannt", belowReferenceTo: UUID(), in: reference) == reference)
        #expect(MarkdownText.insertingParagraph("  ", belowReferenceTo: id, in: reference) == reference)
    }

    @Test func removingReference_dropsTheLineOfAPictureReference() {
        let id = UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301")!
        let reference = MarkdownText.reference(for: id, name: "Zeichnung", isImage: true)
        #expect(MarkdownText.removingReference(to: id, in: "Vor\n\(reference)\nNach") == "Vor\nNach")
        #expect(MarkdownText.removingReference(to: id, in: reference) == "")
        #expect(MarkdownText.removingReference(to: id, in: "Vor\n\(reference)") == "Vor")
        // Text in the same line stays; other attachments and links stay.
        let other = MarkdownText.reference(for: UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3302")!, name: "Foto", isImage: true)
        #expect(MarkdownText.removingReference(to: id, in: "Skizze: \(reference) fertig\n\(other)") == "Skizze:  fertig\n\(other)")
        #expect(MarkdownText.removingReference(to: UUID(), in: "Vor\n\(reference)") == "Vor\n\(reference)")
    }
}
