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
        #expect(output.contains("data-index=\"0\"") && output.contains("☐") && output.contains("data-index=\"1\"") && output.contains("☑"))
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

    @Test func renderer_fileLink_becomesAChip() {
        #expect(html("[Rechnung.pdf](attachment:\(id.uuidString))").contains("<a class=\"file\" href=\"attachment:\(id.uuidString)\">📎 Rechnung.pdf</a>"))
        #expect(html("[](attachment:\(id.uuidString))", names: [id: "Plan <1>.pdf"]).contains("📎 Plan &lt;1&gt;.pdf</a>"))
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

    // MARK: Page

    @Test func page_containsCSP() {
        let page = NoteHTMLRenderer.page(body: "<p>x</p>")
        #expect(page.contains("http-equiv=\"Content-Security-Policy\""))
        #expect(page.contains("default-src 'none'; img-src tagwerk-attachment:; style-src 'unsafe-inline'"))
        #expect(!page.contains("<script"))
        #expect(page.contains("<p>x</p>"))
    }

    @Test func page_followsSchemeAndTextSize() {
        #expect(NoteHTMLRenderer.page(body: "", colorScheme: .system).contains("prefers-color-scheme: dark"))
        #expect(!NoteHTMLRenderer.page(body: "", colorScheme: .light).contains("prefers-color-scheme: dark"))
        #expect(NoteHTMLRenderer.page(body: "", textScale: 2).contains("34.00px"))
        #expect(NoteHTMLRenderer.page(body: "", textScale: 100).contains("68.00px"))
    }
}
