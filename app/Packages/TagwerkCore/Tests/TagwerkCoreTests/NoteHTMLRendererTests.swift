import Foundation
import Testing
@testable import TagwerkCore

struct NoteHTMLRendererTests {
    private let id = UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301")!

    private func html(_ markdown: String, names: [UUID: String] = [:]) -> String {
        NoteHTMLRenderer.html(markdown: markdown, attachmentNames: names)
    }

    @Test func renderer_headingListTableChecklist() {
        let markdown = """
        # Titel

        Absatz mit **fett**, *kursiv*, ~~weg~~ und `Code`.

        - eins
        - zwei

        1. a
        2. b

        - [ ] offen
        - [x] erledigt

        > Zitat

        | Name | Menge |
        |:--|--:|
        | Milch | 2 |

        ---
        """
        let output = html(markdown)
        #expect(output.contains("<h1>Titel</h1>"))
        #expect(output.contains("<strong>fett</strong>") && output.contains("<em>kursiv</em>") && output.contains("<del>weg</del>"))
        #expect(output.contains("<code>Code</code>"))
        #expect(output.contains("<ul>") && output.contains("<li>eins</li>") && output.contains("<ol>"))
        #expect(output.contains("<blockquote>"))
        #expect(output.contains("<th>Name</th><th class=\"right\">Menge</th>"))
        #expect(output.contains("<td>Milch</td><td class=\"right\">2</td>"))
        #expect(output.contains("<hr>"))
        #expect(output.contains("data-index=\"0\"") && output.contains("aria-checked=\"false\"") && output.contains("data-index=\"1\"") && output.contains("aria-checked=\"true\""))
    }

    @Test func renderer_codeIsEscaped() {
        let output = html("```\n<script>alert(1)</script> & x\n```\n\nInline `<b>` hier")
        #expect(output.contains("<pre><code>&lt;script&gt;alert(1)&lt;/script&gt; &amp; x\n</code></pre>"))
        #expect(output.contains("<code>&lt;b&gt;</code>"))
        #expect(!output.contains("<script>"))
    }

    @Test func renderer_textIsEscaped() {
        #expect(html("5 < 6 & \"x\"").contains("5 &lt; 6 &amp; &quot;x&quot;"))
    }

    @Test func renderer_javascriptLink_becomesText() {
        let output = html("[klick](javascript:alert(1)) und [ok](https://example.com) und [mail](mailto:a@example.com) und [rel](/pfad)")
        #expect(!output.contains("javascript"))
        #expect(output.contains("klick und "))
        #expect(output.contains("<a href=\"https://example.com\">ok</a>") && output.contains("<a href=\"mailto:a@example.com\">mail</a>"))
        #expect(output.contains("rel") && !output.contains("href=\"/pfad\""))
        #expect(!html("[x](data:text/html;base64,AAAA)").contains("href"))
        #expect(!html("[tg](\(NoteHTMLRenderer.toggleScheme):0)").contains("href"))
    }

    @Test func renderer_remoteImage_isNotLoaded() {
        for source in ["https://example.com/x.png", "http://example.com/x.png", "data:image/png;base64,AAAA", "file:///x.png", "//example.com/x.png"] {
            let output = html("![Alt](\(source))")
            #expect(!output.contains("<img") && !output.contains("example.com") && output.contains("[Bild]"), "\(source)")
        }
        #expect(!html("<img src=\"https://example.com/x.png\">").contains("<img"))
        // A reference-style image resolves to the same refusal.
        #expect(!html("![Alt][r]\n\n[r]: https://example.com/x.png").contains("<img"))
    }

    @Test func renderer_attachmentImage_usesCustomScheme() {
        let output = html("![Urlaub](attachment:\(id.uuidString))")
        #expect(output.contains("<img src=\"tagwerk-attachment://\(id.uuidString)\" alt=\"Urlaub\">"))
        #expect(html("<img src=\"attachment:\(id.uuidString)\" alt=\"A\">").contains("<img src=\"tagwerk-attachment://\(id.uuidString)\" alt=\"A\">"))
    }

    @Test func renderer_fileLink_withoutKnownAttachment_keepsPlainLink() {
        #expect(html("[Rechnung.pdf](attachment:\(id.uuidString))").contains("<a class=\"file\" href=\"attachment:\(id.uuidString)\">📎 Rechnung.pdf</a>"))
    }

    @Test func renderer_unknownAttachmentKeepsPlainLink() {
        var options = NoteHTMLRenderer.RenderOptions()
        options.attachments = [UUID(): NoteAttachmentDisplay(name: "Anderes.pdf", detail: "1 KB", kind: .file)]
        let output = NoteHTMLRenderer.html(markdown: "[](attachment:\(id.uuidString))", options: options)
        #expect(output.contains("<a class=\"file\" href=\"attachment:\(id.uuidString)\">📎 \(String(id.uuidString.prefix(8)))</a>"))
        #expect(!output.contains("class=\"chip\""))
    }

    @Test func renderer_fileReferenceBecomesChipWithNameAndSize() {
        var options = NoteHTMLRenderer.RenderOptions()
        options.attachments = [id: NoteAttachmentDisplay(name: "Plan <1>.pdf", detail: "1,2 MB", kind: .file)]
        // Without a label the chip names the file; a label of the link wins.
        let unlabeled = NoteHTMLRenderer.html(markdown: "[](attachment:\(id.uuidString))", options: options)
        #expect(unlabeled.contains("<a class=\"chip\" href=\"attachment:\(id.uuidString)\"><span class=\"name\">Plan &lt;1&gt;.pdf</span><span class=\"detail\">1,2 MB</span></a>"))
        let labeled = NoteHTMLRenderer.html(markdown: "[Mietvertrag](attachment:\(id.uuidString))", options: options)
        #expect(labeled.contains("<span class=\"name\">Mietvertrag</span><span class=\"detail\">1,2 MB</span>"))
    }

    @Test func renderer_chipWithoutDetail_omitsTheDetailSpan() {
        var options = NoteHTMLRenderer.RenderOptions()
        options.attachments = [id: NoteAttachmentDisplay(name: "a.pdf", detail: "", kind: .file)]
        let output = NoteHTMLRenderer.html(markdown: "[](attachment:\(id.uuidString))", options: options)
        #expect(output.contains("<span class=\"name\">a.pdf</span></a>") && !output.contains("class=\"detail\""))
    }

    @Test func renderer_imageKeepsImgTag() {
        var options = NoteHTMLRenderer.RenderOptions()
        options.attachments = [id: NoteAttachmentDisplay(name: "Foto.jpg", detail: "300 KB", kind: .image)]
        let output = NoteHTMLRenderer.html(markdown: "![Urlaub](attachment:\(id.uuidString))", options: options)
        #expect(output.contains("<img src=\"tagwerk-attachment://\(id.uuidString)\" alt=\"Urlaub\">"))
        // A link to a picture is not turned into a file chip.
        #expect(!NoteHTMLRenderer.html(markdown: "[Foto](attachment:\(id.uuidString))", options: options).contains("class=\"chip\""))
    }

    @Test func renderer_checkedItemGetsDoneClass() {
        let output = html("- [ ] offen\n- [x] erledigt\n- Punkt")
        #expect(output.contains("<li class=\"task\">") && output.contains("<li class=\"task done\">"))
        #expect(output.components(separatedBy: "class=\"task done\"").count - 1 == 1)
        #expect(output.contains("<li>Punkt</li>"))
    }

    @Test func legacyHtmlSignature_matchesOptionsVariant() {
        let markdown = "# Titel\n\n[](attachment:\(id.uuidString))\n\n- [x] a"
        var options = NoteHTMLRenderer.RenderOptions()
        options.attachments = [id: NoteAttachmentDisplay(name: "Plan.pdf")]
        #expect(NoteHTMLRenderer.html(markdown: markdown, attachmentNames: [id: "Plan.pdf"]) == NoteHTMLRenderer.html(markdown: markdown, options: options))
    }

    @Test func renderer_checkboxIndicesMatchToggling() {
        let documents = [
            "- [ ] a\n- [x] b\n  - [ ] c\n",
            "Text\n\n```\n- [ ] im Code\n```\n\n- [ ] davor\n* [x] danach\n",
            "> - [ ] im Zitat\n\n1. [ ] numeriert\n2. [x] auch\n- [ ]\n",
            "- kein Punkt\n- [ ] ja\n- [link](https://example.com) [ ] nein\n",
        ]
        for document in documents {
            let output = html(document)
            let rendered = output.components(separatedBy: "data-index=\"").count - 1
            #expect(rendered == MarkdownText.checkboxCount(in: document), "count in \(document)")
            for index in 0..<rendered {
                // Toggling a box changes exactly the box with that number in the rendered page.
                let toggled = html(MarkdownText.togglingCheckbox(at: index, in: document))
                let before = checkedFlags(in: output)
                let after = checkedFlags(in: toggled)
                #expect(zip(before, after).enumerated().allSatisfy { ($0.offset == index) == ($0.element.0 != $0.element.1) }, "box \(index) in \(document)")
            }
        }
    }

    private func checkedFlags(in html: String) -> [Bool] {
        html.components(separatedBy: "aria-checked=\"").dropFirst().map { $0.hasPrefix("true") }
    }

    @Test func renderer_rawHtml_isSanitized() {
        let output = html("Vor <b onclick=\"x()\">fett</b> <script>alert(1)</script> nach\n\n<script>\nalert(2)\n</script>\n\n<div onmouseover=\"x\">Block</div>\n\n<iframe src=\"https://evil\"></iframe>")
        #expect(output.contains("<b>fett</b>"))
        #expect(!output.contains("script") && !output.contains("alert") && !output.contains("onclick") && !output.contains("onmouseover"))
        #expect(!output.contains("iframe") && !output.contains("evil"))
        #expect(output.contains("<div>Block</div>"))
    }

    @Test func renderer_unclosedScriptDoesNotSwallowTheNextBlock() {
        let output = html("Erste <script>alert(1) Zeile\n\nZweiter Absatz bleibt")
        #expect(!output.contains("alert") && output.contains("Zweiter Absatz bleibt"))
    }

    @Test func renderer_softBreakIsALineBreak() {
        #expect(html("eins\nzwei").contains("eins<br>\nzwei"))
    }

    // MARK: Edit links

    private func editHTML(_ markdown: String) -> String {
        NoteHTMLRenderer.html(markdown: markdown, options: NoteHTMLRenderer.RenderOptions(editLinks: true))
    }

    private func edit(_ line: Int, _ text: String) -> String { "<a class=\"e\" href=\"tagwerk-edit:\(line)\">\(text)</a>" }

    @Test func editLinks_wrapEveryTextRunWithItsLine() {
        let output = editHTML("# Titel\n\nZeile drei\nZeile vier\n\n- Punkt\n")
        #expect(output.contains("<h1>\(edit(1, "Titel"))</h1>"))
        #expect(output.contains("<p>\(edit(3, "Zeile drei"))<br>\n\(edit(4, "Zeile vier"))</p>"))
        #expect(output.contains("<li>\(edit(6, "Punkt"))</li>"))
    }

    @Test func editLinks_nestedListItemKeepsOwnLine() {
        let output = editHTML("- a\n  - b\n- c\n")
        #expect(output.contains(edit(1, "a")) && output.contains(edit(2, "b")) && output.contains(edit(3, "c")))
    }

    @Test func editLinks_notInsideRealLink() {
        let output = editHTML("Vor [Link](https://example.com) nach\n\n[](attachment:\(id.uuidString))")
        #expect(output.contains("<a href=\"https://example.com\">Link</a>"))
        #expect(output.contains(edit(1, "Vor ")) && output.contains(edit(1, " nach")))
        // No anchor inside an anchor: every opening tag is closed before the next one opens.
        for chunk in output.components(separatedBy: "<a ").dropFirst() { #expect(!chunk.prefix(while: { $0 != "/" }).contains("<a")) }
        #expect(!output.contains("<a class=\"e\" href=\"tagwerk-edit:1\"><a"))
    }

    @Test func editLinks_notInsideCheckboxLink() {
        let output = editHTML("- [ ] offen\n- [x] fertig\n")
        #expect(output.contains(edit(1, "offen")) && output.contains(edit(2, "fertig")))
        let boxes = output.components(separatedBy: "<a class=\"task-box\"").dropFirst().map { $0.components(separatedBy: "</a>")[0] }
        #expect(boxes.count == 2 && boxes.allSatisfy { !$0.contains("tagwerk-edit") })
    }

    @Test func editLinks_emphasisWrapsAnchorNotViceVersa() {
        let output = editHTML("Text **fett** und *kursiv*")
        #expect(output.contains("<strong>\(edit(1, "fett"))</strong>") && output.contains("<em>\(edit(1, "kursiv"))</em>"))
    }

    @Test func editLinks_inlineCodeIsLinked() {
        #expect(editHTML("A `b` C").contains(edit(1, "<code>b</code>")))
    }

    @Test func editLinks_codeBlockPointsToFirstLine() {
        // Fenced: the fence is line 3, the first content line 4. Indented: the block starts on its first content line.
        let fenced = editHTML("Text\n\n```\ncode\nmehr\n```\n")
        #expect(fenced.contains("<a class=\"e block\" href=\"tagwerk-edit:4\"><pre><code>code\nmehr\n</code></pre></a>"))
        let indented = editHTML("Text\n\n    code\n    mehr\n")
        #expect(indented.contains("href=\"tagwerk-edit:3\"><pre>"))
        let unclosed = editHTML("```\nnur\n")
        #expect(unclosed.contains("href=\"tagwerk-edit:2\"><pre>"))
    }

    @Test func editLinks_tableHasNone() {
        let output = editHTML("Davor\n\n| A | B |\n|--|--|\n| 1 | 2 |\n")
        let table = output.components(separatedBy: "<table>")[1].components(separatedBy: "</table>")[0]
        #expect(!table.contains("tagwerk-edit") && table.contains("<td>1</td>"))
    }

    @Test func editLinks_tailLinkPresent() {
        let output = editHTML("Text")
        #expect(output.hasSuffix("<a class=\"e tail\" href=\"tagwerk-edit:end\"></a>\n"))
        #expect(NoteHTMLRenderer.page(body: output).contains("a.e.tail"))
    }

    @Test func editLinks_off_htmlIsUnchanged() {
        let markdown = "# Titel\n\nText **fett**\n\n- [ ] a\n\n```\ncode\n```\n"
        let plain = NoteHTMLRenderer.html(markdown: markdown, options: NoteHTMLRenderer.RenderOptions())
        #expect(plain == NoteHTMLRenderer.html(markdown: markdown))
        #expect(!plain.contains("tagwerk-edit") && !plain.contains("class=\"e"))
        #expect(plain.contains("<h1>Titel</h1>") && plain.contains("<pre><code>code\n</code></pre>"))
    }

    @Test func editLinks_crlfText_linesMatch() {
        let output = editHTML("# Titel\r\n\r\nZeile drei\r\nZeile vier\r\n")
        #expect(output.contains(edit(1, "Titel")) && output.contains(edit(3, "Zeile drei")) && output.contains(edit(4, "Zeile vier")))
    }

    @Test func editLinks_rawHtmlGetsNoLink() {
        let output = editHTML("<div>Roh</div>\n\nText")
        #expect(output.contains("<div>Roh</div>") && output.contains(edit(3, "Text")))
    }

    @Test func editLinks_escapesTextInsideTheAnchor() {
        #expect(editHTML("a < b & c").contains(edit(1, "a &lt; b &amp; c")))
    }

    @Test func image_isALinkToItsAttachment() {
        let output = NoteHTMLRenderer.html(markdown: "![Urlaub](attachment:\(id.uuidString))")
        #expect(output.contains("<a class=\"img\" href=\"attachment:\(id.uuidString)\"><img src=\"tagwerk-attachment://\(id.uuidString)\" alt=\"Urlaub\"></a>"))
    }

    @Test func page_editLinkStyle() {
        let page = NoteHTMLRenderer.page(body: "")
        #expect(page.contains("a.e { color: inherit; text-decoration: none; -webkit-touch-callout: none; }"))
    }

    // MARK: Page

    @Test func page_containsCSP() {
        let page = NoteHTMLRenderer.page(body: "<p>x</p>")
        #expect(page.contains("http-equiv=\"Content-Security-Policy\""))
        #expect(page.contains("default-src 'none'; img-src tagwerk-attachment:; style-src 'unsafe-inline'"))
        #expect(!page.contains("<script"))
        #expect(page.contains("<p>x</p>"))
    }

    @Test func page_limitsImageHeight() {
        let page = NoteHTMLRenderer.page(body: "")
        #expect(page.contains("max-height:40vh") && page.contains("object-fit:contain") && page.contains("max-width:100%"))
    }

    @Test func page_headingSizes() {
        let page = NoteHTMLRenderer.page(body: "")
        // 24 pt and 17 pt over the 17 pt body text, so both follow the text size.
        #expect(page.contains("h1 { font-size: 1.41em; font-weight: 700; }"))
        #expect(page.contains("h2 { font-size: 1em; font-weight: 600; }"))
        #expect(page.contains("line-height") && page.contains("/1.45"))
    }

    @Test func page_checkboxHitAreaIs44Points() {
        let page = NoteHTMLRenderer.page(body: "")
        #expect(page.contains("min-width:44px") && page.contains("min-height:44px"))
        #expect(page.contains("li.done") && !page.contains("line-through"))
    }

    @Test func page_chipTextUsesNormalTextColorOnTintedBackground() {
        let page = NoteHTMLRenderer.page(body: "")
        let rule = page.components(separatedBy: "a.chip {").dropFirst().first?.components(separatedBy: "}").first ?? ""
        #expect(rule.contains("var(--code)") && rule.contains("color: var(--text)"))
    }

    @Test func page_followsSchemeAndTextSize() {
        #expect(NoteHTMLRenderer.page(body: "", colorScheme: .system).contains("prefers-color-scheme: dark) { :root { --text: #f2f2f7"))
        #expect(NoteHTMLRenderer.page(body: "", colorScheme: .dark).contains(":root { --text: #f2f2f7"))
        #expect(!NoteHTMLRenderer.page(body: "", colorScheme: .light).contains("prefers-color-scheme: dark"))
        #expect(NoteHTMLRenderer.page(body: "", textScale: 2).contains("34.00px"))
        #expect(NoteHTMLRenderer.page(body: "", textScale: 100).contains("68.00px"))
    }
}
