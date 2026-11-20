import Foundation
import Testing
@testable import TagwerkCore

/// Fake extension items, shaped like what Safari hands the share extension. All texts are invented.
struct ShareItemTextTests {
    private let page = URL(string: "https://www.example.com/artikel/1")!
    private let selection = "Ob du eine schnelle Antwort brauchst oder eine Reise planst, der Absatz erklärt die Möglichkeiten Schritt für Schritt."

    /// What the extractor does with one extension item: the parts of its providers first, then the item's own text.
    private func parts(providers: [SharePart], title: String? = nil, contentText: String? = nil) -> [SharePart] {
        var parts = providers
        ShareItemText.merge(attributedTitle: title, attributedContentText: contentText, into: &parts)
        return parts
    }

    // MARK: Selection shared from the selection menu

    @Test func selectionWithoutURL_isTitleOnceAndBodyOnce() throws {
        // The selection arrives twice: as a plain-text attachment (with a trailing line break) and as the item's text.
        let merged = parts(providers: [.text(selection + "\n")], contentText: selection)
        let payload = try #require(SharePayload.classify(merged))
        #expect(payload.kind == .text)
        #expect(payload.text == selection)
        #expect(payload.title == selection)
        #expect(payload.url == nil && payload.pageTitle == nil)
    }

    @Test func selectionWithTruncatedCopy_keepsTheFullTextOnly() throws {
        // The item's text is a shortened copy with an ellipsis; the attachment holds the full selection.
        let shortened = String(selection.prefix(40)) + "…"
        let merged = parts(providers: [.text(selection)], contentText: shortened)
        let payload = try #require(SharePayload.classify(merged))
        #expect(payload.text == selection)
        // The same when the shortened copy comes first.
        let reversed = try #require(SharePayload.classify([.text(shortened), .text(selection)]))
        #expect(reversed.text == selection)
    }

    @Test func selectionWithURLAttachment_linksThePage() throws {
        let merged = parts(providers: [.url(page), .text(selection)], title: "Ein guter Artikel", contentText: selection)
        let payload = try #require(SharePayload.classify(merged))
        #expect(payload.url == page)
        #expect(payload.pageTitle == "Ein guter Artikel")
        // The page title is the title; the selection is the body, once.
        #expect(payload.title == "Ein guter Artikel")
        #expect(payload.text == selection)
    }

    @Test func selectionWithURLAsItemText_linksThePage() throws {
        // No attachment for the address, but the item's text is the address itself.
        let merged = parts(providers: [.text(selection)], contentText: page.absoluteString)
        let payload = try #require(SharePayload.classify(merged))
        #expect(payload.url == page)
        #expect(payload.text == selection)
        #expect(payload.title == selection)
    }

    @Test func selectionWithoutPageTitle_titleIsTheFirstLineOnce() throws {
        let merged = parts(providers: [.url(page), .text("Erste Zeile\nZweite Zeile")], contentText: "Erste Zeile\nZweite Zeile")
        let payload = try #require(SharePayload.classify(merged))
        #expect(payload.title == "Erste Zeile")
        #expect(payload.text == "Erste Zeile\nZweite Zeile")
    }

    // MARK: Page shared with the share button

    @Test func pageShare_withPreprocessingResult() throws {
        let result = SafariPreprocessingResult(url: page, title: "Ein guter Artikel", selection: nil)
        // Safari adds the page title as the item's text and as its title as well.
        let merged = parts(providers: result.parts, title: "Ein guter Artikel", contentText: "Ein guter Artikel")
        let payload = try #require(SharePayload.classify(merged))
        #expect(payload.url == page && payload.title == "Ein guter Artikel")
        #expect(payload.text == nil && payload.pageTitle == "Ein guter Artikel")
    }

    @Test func pageShare_withURLAndTitleOnly() throws {
        let merged = parts(providers: [.url(page)], contentText: "Ein guter Artikel")
        let payload = try #require(SharePayload.classify(merged))
        #expect(payload.url == page)
        #expect(payload.title == "Ein guter Artikel")
        #expect(payload.text == "Ein guter Artikel")
    }

    // MARK: Merge rules

    @Test func merge_ignoresEmptyText() {
        var parts: [SharePart] = []
        ShareItemText.merge(attributedTitle: "  ", attributedContentText: "\n", into: &parts)
        #expect(parts.isEmpty)
    }

    @Test func merge_titleWithoutAddressIsDroppedByTheClassification() {
        #expect(SharePayload.classify(parts(providers: [], title: "Nur ein Titel")) == nil)
    }

    @Test func classify_dropsTextsThatAreContainedInAnotherText() throws {
        let payload = try #require(SharePayload.classify([.text("Erste Zeile"), .text("Erste Zeile\nZweite Zeile"), .text("Zweite Zeile")]))
        #expect(payload.text == "Erste Zeile\nZweite Zeile")
        // Two different texts both stay.
        let two = try #require(SharePayload.classify([.text("Alpha"), .text("Beta")]))
        #expect(two.text == "Alpha\nBeta")
    }
}
