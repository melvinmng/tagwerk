import Foundation
import Testing
@testable import TagwerkCore

struct HTMLSanitizerTests {
    private let id = "3F2504E0-4F89-41D3-9A0C-0305E82C3301"

    @Test func sanitizer_dropsScriptWithContent() {
        #expect(HTMLSanitizer.clean("a<script>alert(1)</script>b") == "ab")
        #expect(HTMLSanitizer.clean("a<SCRIPT type=\"text/javascript\">if (x<y) {}</SCRIPT >b") == "ab")
        #expect(HTMLSanitizer.clean("<style>body{display:none}</style>Text") == "Text")
        #expect(HTMLSanitizer.clean("x<script src=https://evil.example/a.js></script>y") == "xy")
    }

    @Test func sanitizer_dropsEventHandlers() {
        #expect(HTMLSanitizer.clean("<b onclick=\"alert(1)\" onmouseover='x()'>fett</b>") == "<b>fett</b>")
        #expect(HTMLSanitizer.clean("<p style=\"background:url(https://evil)\" class=\"x\" id=\"y\">t</p>") == "<p>t</p>")
        #expect(HTMLSanitizer.clean("<img src=\"attachment:\(id)\" onerror=\"alert(1)\" srcset=\"https://evil 2x\">")
                == "<img src=\"tagwerk-attachment://\(id)\">")
        #expect(HTMLSanitizer.clean("<a href=\"https://example.com\" xlink:href=\"javascript:x\" onfocus=x>l</a>") == "<a href=\"https://example.com\">l</a>")
    }

    @Test func sanitizer_dropsIframeAndSvg() {
        for html in ["<iframe src=\"https://evil\">drin</iframe>", "<svg onload=alert(1)><circle/></svg>", "<object data=x>o</object>",
                     "<embed src=x>", "<form action=x><input name=a></form>", "<math><mi>x</mi></math>",
                     "<template><p>t</p></template>", "<noscript>n</noscript>"] {
            #expect(HTMLSanitizer.clean("[\(html)]") == "[]", "\(html)")
        }
        #expect(HTMLSanitizer.clean("<svg><svg></svg>innen</svg>außen") == "außen")
    }

    @Test func sanitizer_keepsAllowedFormatting() {
        let html = "<h2>Titel</h2><p>Ein <b>fetter</b>, <i>schräger</i> und <u>unterstrichener</u> Text<br>mit <mark>Marker</mark>.</p>"
            + "<ul><li>eins</li></ul><table><thead><tr><th colspan=\"2\">K</th></tr></thead><tbody><tr><td>a</td><td rowspan=2>b</td></tr></tbody></table>"
            + "<details><summary>mehr</summary>Inhalt</details><hr><pre><code>x &lt; y</code></pre>"
        #expect(HTMLSanitizer.clean(html) == html.replacingOccurrences(of: "rowspan=2", with: "rowspan=\"2\""))
    }

    @Test func sanitizer_unknownTagsKeepTheirText() {
        #expect(HTMLSanitizer.clean("<font color=red>rot</font> <center>mittig</center><blink>x</blink>") == "rot mittigx")
    }

    @Test func sanitizer_dataURLInImg_isDropped() {
        #expect(HTMLSanitizer.clean("a<img src=\"data:image/png;base64,AAAA\">b") == "ab")
        #expect(HTMLSanitizer.clean("a<img src=\"https://evil.example/x.png\" alt=x>b") == "ab")
        #expect(HTMLSanitizer.clean("a<img alt=x>b") == "ab")
        #expect(HTMLSanitizer.clean("a<img src=\"attachment:nicht-gueltig\">b") == "ab")
        #expect(HTMLSanitizer.clean("<img src=\"ATTACHMENT:\(id.lowercased())\" alt=\"Foto\">") == "<img src=\"tagwerk-attachment://\(id)\" alt=\"Foto\">")
    }

    @Test func sanitizer_unclosedTag_doesNotSwallowRest() {
        // A dropped element that stays open ends with the fragment; the next block is not affected.
        var sanitizer = HTMLSanitizer()
        #expect(sanitizer.feed("<script>alert(1)") == "")
        #expect(sanitizer.isSuppressing)
        sanitizer.reset()
        #expect(sanitizer.feed("Rest") == "Rest")
        #expect(HTMLSanitizer.clean("a<script>b") == "a")
        // A tag without its ">" is text, not the start of something that eats the rest.
        #expect(HTMLSanitizer.clean("<b>fett <i kursiv") == "<b>fett &lt;i kursiv")
        #expect(HTMLSanitizer.clean("a < b und c > d") == "a &lt; b und c > d")
        #expect(HTMLSanitizer.clean("<a href=\"https://example.com>link") == "&lt;a href=\"https://example.com>link")
    }

    @Test func sanitizer_pieceByPiece_dropsASplitScript() {
        var sanitizer = HTMLSanitizer()
        let output = sanitizer.feed("<script>") + (sanitizer.isSuppressing ? "" : "alert(1)") + sanitizer.feed("</script>") + sanitizer.feed("<b>")
        #expect(output == "<b>")
        #expect(!sanitizer.isSuppressing)
    }

    @Test func sanitizer_linkTargets_needAnAllowedScheme() {
        let allowed = ["https://example.com/a?b=1&c=2", "http://example.com", "mailto:a@example.com", "tel:+4930123", "HTTPS://EXAMPLE.COM"]
        for target in allowed { #expect(HTMLSanitizer.allowedLinkTarget(target) != nil, "\(target)") }
        let refused = ["javascript:alert(1)", "JaVaScRiPt:alert(1)", "java\tscript:alert(1)", "java&#9;script:alert(1)", " javascript:x",
                       "&#106;avascript:alert(1)", "&#x6A;avascript:alert(1)", "data:text/html,<script>alert(1)</script>", "vbscript:x",
                       "file:///etc/passwd", "ftp://example.com", "//example.com", "/pfad", "#anker", "relativ.html", "attachment:kaputt", "blob:https://x"]
        for target in refused { #expect(HTMLSanitizer.allowedLinkTarget(target) == nil, "\(target)") }
        #expect(HTMLSanitizer.clean("<a href=\"javascript:alert(1)\" title=\"t\">x</a>") == "<a title=\"t\">x</a>")
        // An entity trick that the decoder does not know ends up as harmless text after the re-escaping.
        #expect(HTMLSanitizer.clean("<a href=\"javascript&colon;alert(1)\">x</a>") == "<a>x</a>")
    }

    @Test func sanitizer_attributeValuesAreEscaped() {
        #expect(HTMLSanitizer.clean("<a href=\"https://example.com/?a=1&b=2\" title=\"a&quot;b<c\">x</a>")
                == "<a href=\"https://example.com/?a=1&amp;b=2\" title=\"a&quot;b&lt;c\">x</a>")
        // A quote cannot break out of the attribute.
        #expect(HTMLSanitizer.clean("<a title='x\" onclick=\"alert(1)'>t</a>") == "<a title=\"x&quot; onclick=&quot;alert(1)\">t</a>")
    }

    @Test func sanitizer_dropsCommentsAndDeclarations() {
        #expect(HTMLSanitizer.clean("a<!-- <script>x</script> -->b") == "ab")
        #expect(HTMLSanitizer.clean("a<!DOCTYPE html>b<?php x ?>c<![CDATA[y]]>d") == "abcd")
        #expect(HTMLSanitizer.clean("a<!-- offen") == "a")
        #expect(HTMLSanitizer.clean("a\u{0}<scr\u{0}ipt>x</script>b") == "ab")
    }

    @Test func sanitizer_neverEmitsADisallowedTag() {
        // Whatever the input, every tag in the output comes from the allowlist.
        let inputs = ["<scr<script>ipt>alert(1)</scr</script>ipt>", "<<b>script>x", "<a/href=javascript:x>y</a>", "<img/src=x onerror=alert(1)>",
                      "<b <script>x</script>>t", "<p x=\"<script>\">t</p>", "<svg/onload=alert(1)>", "<body onload=x>", "<link rel=stylesheet href=https://x>",
                      "<meta http-equiv=refresh content=\"0;url=https://x\">", "<base href=https://x>", "<input autofocus onfocus=alert(1)>"]
        let tagPattern = try! NSRegularExpression(pattern: "</?([A-Za-z][A-Za-z0-9]*)")
        for input in inputs {
            let output = HTMLSanitizer.clean(input)
            for match in tagPattern.matches(in: output, range: NSRange(output.startIndex..., in: output)) {
                let name = String(output[Range(match.range(at: 1), in: output)!]).lowercased()
                #expect(HTMLSanitizer.allowedTags.contains(name), "\(input) -> \(output)")
            }
            #expect(!output.lowercased().contains("onerror=") && !output.lowercased().contains("onload=") && !output.lowercased().contains("onfocus="), "\(input) -> \(output)")
        }
    }

    @Test func rawHTML_dropsAppSchemes() {
        // Only the renderer writes links of the app's own schemes; raw HTML of a note cannot.
        for scheme in ["tagwerk-edit:3", "tagwerk-edit:end", "tagwerk-toggle:0", "tagwerk-table:1", "TAGWERK-EDIT:3", "tagwerk-\u{200B}edit:3"] {
            let output = HTMLSanitizer.clean("<a href=\"\(scheme)\">x</a>")
            #expect(!output.lowercased().contains("tagwerk-") && !output.contains("href"), "\(scheme) -> \(output)")
            #expect(output.contains("x"))
        }
        #expect(!HTMLSanitizer.clean("<a class=\"e\" href=\"tagwerk-edit:3\">x</a>").contains("class"))
    }
}
