import Foundation
import Testing
@testable import TagwerkCore

struct ChatMarkdownTests {
    // MARK: Helpers

    private func text(_ attributed: AttributedString) -> String { String(attributed.characters) }

    /// The runs of an inline text as "text|style" pairs, so a test reads like the rendered line.
    private func runs(_ attributed: AttributedString) -> [String] {
        attributed.runs.map { run in
            var parts = [String(attributed[run.range].characters)]
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) { parts.append("bold") }
                if intent.contains(.emphasized) { parts.append("italic") }
                if intent.contains(.code) { parts.append("code") }
                if intent.contains(.strikethrough) { parts.append("strike") }
            }
            if let link = run.link { parts.append("link:\(link.absoluteString)") }
            return parts.joined(separator: "|")
        }
    }

    private func paragraphs(_ blocks: [ChatBlock]) -> [String] {
        blocks.compactMap { if case .paragraph(let inline) = $0 { text(inline) } else { nil } }
    }

    // MARK: Blocks

    @Test func plainText_isOneParagraph() {
        let blocks = ChatMarkdown.blocks("Hallo Welt")
        #expect(paragraphs(blocks) == ["Hallo Welt"])
    }

    @Test func emptyText_hasNoBlocks() {
        #expect(ChatMarkdown.blocks("").isEmpty)
        #expect(ChatMarkdown.blocks("  \n\n ").isEmpty)
    }

    @Test func blankLine_splitsParagraphs() {
        #expect(paragraphs(ChatMarkdown.blocks("Eins\n\nZwei")) == ["Eins", "Zwei"])
    }

    @Test func singleLineBreak_staysALineBreak() {
        // The old chat showed answers as they came; a line break the model wrote must not collapse into a space.
        #expect(paragraphs(ChatMarkdown.blocks("Eins\nZwei")) == ["Eins\nZwei"])
    }

    @Test func headings_keepTheirLevel() {
        let blocks = ChatMarkdown.blocks("# Titel\n\n### Unter")
        guard case .heading(let first, let firstText) = blocks[0], case .heading(let second, let secondText) = blocks[1] else {
            Issue.record("expected two headings")
            return
        }
        #expect(first == 1 && text(firstText) == "Titel")
        #expect(second == 3 && text(secondText) == "Unter")
    }

    @Test func lists_keepOrderStartAndNesting() {
        let blocks = ChatMarkdown.blocks("3. drei\n4. vier\n   - innen\n")
        guard case .list(let list) = blocks[0] else { Issue.record("expected a list"); return }
        #expect(list.isOrdered)
        #expect(list.start == 3)
        #expect(list.items.count == 2)
        guard case .paragraph(let head) = list.items[1].blocks[0], case .list(let nested) = list.items[1].blocks[1] else {
            Issue.record("expected a paragraph and a nested list")
            return
        }
        #expect(text(head) == "vier")
        #expect(!nested.isOrdered)
        #expect(nested.items.count == 1)
    }

    @Test func taskList_keepsTheBoxState() {
        let blocks = ChatMarkdown.blocks("- [x] fertig\n- [ ] offen\n- normal")
        guard case .list(let list) = blocks[0] else { Issue.record("expected a list"); return }
        #expect(list.items.map(\.checkbox) == [true, false, nil])
    }

    @Test func fencedCode_keepsLanguageAndWhitespace() {
        let blocks = ChatMarkdown.blocks("```swift\nlet a = 1\n    let b = 2\n```")
        #expect(blocks == [.code(language: "swift", text: "let a = 1\n    let b = 2")])
    }

    @Test func unclosedFence_isACodeBlockToTheEnd() {
        // While an answer streams, the closing fence is not there yet.
        let blocks = ChatMarkdown.blocks("Text\n\n```\nlet a = 1\nlet b")
        #expect(blocks.count == 2)
        #expect(blocks[1] == .code(language: nil, text: "let a = 1\nlet b"))
    }

    @Test func quote_holdsBlocks() {
        let blocks = ChatMarkdown.blocks("> Zitat\n> weiter")
        guard case .quote(let inner) = blocks[0] else { Issue.record("expected a quote"); return }
        #expect(paragraphs(inner) == ["Zitat\nweiter"])
    }

    @Test func thematicBreak_isARule() {
        #expect(ChatMarkdown.blocks("a\n\n---\n\nb").contains(.rule))
    }

    @Test func table_hasHeadRowsAndAlignments() {
        let markdown = """
        | Name | Zahl |
        |:-----|-----:|
        | a | 1 |
        | b | 2 |
        """
        let blocks = ChatMarkdown.blocks(markdown)
        guard case .table(let table) = blocks[0] else { Issue.record("expected a table"); return }
        #expect(table.header.map(text) == ["Name", "Zahl"])
        #expect(table.rows.map { $0.map(text) } == [["a", "1"], ["b", "2"]])
        #expect(table.alignments == [.leading, .trailing])
    }

    @Test func table_padsShortRows() {
        let blocks = ChatMarkdown.blocks("| a | b |\n|---|---|\n| 1 |")
        guard case .table(let table) = blocks[0] else { Issue.record("expected a table"); return }
        #expect(table.rows[0].map(text) == ["1", ""])
    }

    // MARK: Inline

    @Test func inlineStyles() {
        let blocks = ChatMarkdown.blocks("a **fett** *kursiv* `code` ~~weg~~")
        guard case .paragraph(let inline) = blocks[0] else { Issue.record("expected a paragraph"); return }
        #expect(runs(inline) == ["a ", "fett|bold", " ", "kursiv|italic", " ", "code|code", " ", "weg|strike"])
    }

    @Test func nestedStyles_combine() {
        guard case .paragraph(let inline) = ChatMarkdown.blocks("***beides***")[0] else { Issue.record("expected a paragraph"); return }
        #expect(runs(inline) == ["beides|bold|italic"])
    }

    @Test func unclosedEmphasis_staysLiteral() {
        // A half-streamed "**fett" shows as typed until the closing marks arrive.
        #expect(paragraphs(ChatMarkdown.blocks("das ist **fett")) == ["das ist **fett"])
    }

    // MARK: Links

    @Test func httpLink_isALink() {
        guard case .paragraph(let inline) = ChatMarkdown.blocks("[Doku](https://example.com/a)")[0] else { Issue.record("expected a paragraph"); return }
        #expect(runs(inline) == ["Doku|link:https://example.com/a"])
    }

    @Test(arguments: ["javascript:alert(1)", "attachment:7A1F3C52-0000-4000-8000-000000000001", "file:///etc/passwd",
                      "tagwerk-toggle:0", "data:text/html,x", "/relative"])
    func unsafeLink_keepsTheLabelOnly(target: String) {
        guard case .paragraph(let inline) = ChatMarkdown.blocks("[Klick](\(target))")[0] else { Issue.record("expected a paragraph"); return }
        #expect(runs(inline) == ["Klick"])
    }

    @Test func mailAndTelLinks_areAllowed() {
        guard case .paragraph(let inline) = ChatMarkdown.blocks("[Mail](mailto:a@b.de) [Tel](tel:+4912345)")[0] else {
            Issue.record("expected a paragraph")
            return
        }
        #expect(runs(inline) == ["Mail|link:mailto:a@b.de", " ", "Tel|link:tel:+4912345"])
    }

    @Test func image_neverLoads() {
        #expect(paragraphs(ChatMarkdown.blocks("![Diagramm](https://example.com/x.png)")) == ["Diagramm"])
        #expect(paragraphs(ChatMarkdown.blocks("![](https://example.com/x.png)")) == ["[Bild]"])
    }

    // MARK: HTML

    @Test func scriptBlock_isDroppedWithItsContent() {
        let blocks = ChatMarkdown.blocks("Vorher\n\n<script>\nalert(1)\n</script>\n\nNachher")
        #expect(paragraphs(blocks) == ["Vorher", "Nachher"])
    }

    @Test func scriptInline_isDroppedWithItsContent() {
        let result = paragraphs(ChatMarkdown.blocks("a <script>alert(1)</script> b <iframe src=\"https://evil\"></iframe>c"))
        #expect(result.count == 1)
        #expect(!result[0].contains("alert"))
        #expect(!result[0].contains("evil"))
        #expect(result[0].contains("a") && result[0].contains("b") && result[0].hasSuffix("c"))
    }

    @Test func inlineHTMLStyles_areMapped() {
        guard case .paragraph(let inline) = ChatMarkdown.blocks("x <b>fett</b> <em>schief</em><br>neu")[0] else {
            Issue.record("expected a paragraph")
            return
        }
        #expect(runs(inline) == ["x ", "fett|bold", " ", "schief|italic", "\nneu"])
    }

    @Test func unknownInlineTag_isDroppedButItsTextStays() {
        #expect(paragraphs(ChatMarkdown.blocks("a <blink>b</blink> c")) == ["a b c"])
    }

    @Test func htmlLink_needsAnAllowedScheme() {
        guard case .paragraph(let good) = ChatMarkdown.blocks("<a href=\"https://example.com\">hier</a>")[0] else {
            Issue.record("expected a paragraph")
            return
        }
        #expect(runs(good) == ["hier|link:https://example.com"])
        guard case .paragraph(let bad) = ChatMarkdown.blocks("<a href=\"javascript:alert(1)\">hier</a>")[0] else {
            Issue.record("expected a paragraph")
            return
        }
        #expect(runs(bad) == ["hier"])
    }

    @Test func htmlBlock_becomesReadableText() {
        let html = "<div>\n<h2>Titel</h2>\n<p>Erster Absatz</p>\n<ul><li>eins</li><li>zwei</li></ul>\n</div>"
        let lines = paragraphs(ChatMarkdown.blocks(html)).joined(separator: "\n")
        #expect(lines.contains("Titel"))
        #expect(lines.contains("Erster Absatz"))
        #expect(lines.contains("• eins"))
        #expect(lines.contains("• zwei"))
        #expect(!lines.contains("<"))
    }

    @Test func htmlBlock_neverEchoesAttributesOrHandlers() {
        let blocks = ChatMarkdown.blocks("<div onclick=\"alert(1)\" style=\"x\"><img src=\"https://evil/x.png\" onerror=\"alert(1)\">sichtbar</div>")
        let all = paragraphs(blocks).joined(separator: "\n")
        #expect(all.contains("sichtbar"))
        #expect(!all.contains("onclick") && !all.contains("onerror") && !all.contains("evil"))
    }

    @Test func entities_areDecodedInText() {
        #expect(paragraphs(ChatMarkdown.blocks("Tom &amp; Jerry &lt;3")) == ["Tom & Jerry <3"])
    }

    // MARK: Robustness

    @Test func deepNesting_doesNotRecurseWithoutLimit() {
        let nested = String(repeating: "> ", count: 200) + "tief"
        let blocks = ChatMarkdown.blocks(nested)
        #expect(!blocks.isEmpty)
        #expect(ChatMarkdown.plainText(of: blocks).contains("tief"))
    }

    @Test func streamingPrefixes_alwaysParse() {
        let full = "# Titel\n\n- **eins**\n- [Link](https://example.com)\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n```\ncode\n```\n"
        for length in 0...full.count {
            _ = ChatMarkdown.blocks(String(full.prefix(length)))
        }
    }
}
