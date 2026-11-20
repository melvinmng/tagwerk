import Foundation
import Testing
@testable import TagwerkCore

struct SafariPreprocessingResultTests {
    private func results(_ values: [String: Any]) -> [String: Any] {
        [SafariPreprocessingResult.resultsKey: values]
    }

    @Test func parse_readsUrlTitleAndSelection() throws {
        let parsed = try #require(SafariPreprocessingResult.parse(results([
            "url": "https://www.example.com/artikel", "title": "  Ein guter Artikel ", "selection": "\nDer markierte Absatz.\n"
        ])))
        #expect(parsed.url?.absoluteString == "https://www.example.com/artikel")
        #expect(parsed.title == "Ein guter Artikel" && parsed.selection == "Der markierte Absatz.")
        #expect(parsed.parts == [.url(URL(string: "https://www.example.com/artikel")!), .pageTitle("Ein guter Artikel"), .text("Der markierte Absatz.")])
    }

    @Test func parse_leavesOutEmptyFields() throws {
        let parsed = try #require(SafariPreprocessingResult.parse(results(["url": "https://example.com", "title": "", "selection": "  "])))
        #expect(parsed.title == nil && parsed.selection == nil)
        #expect(parsed.parts == [.url(URL(string: "https://example.com")!)])
    }

    @Test func parse_onlyWebAddressesCount() {
        // A page that is no web page (a local file, a reader page) gives no address; with nothing else there is no result.
        #expect(SafariPreprocessingResult.parse(results(["url": "file:///private/page.html"])) == nil)
        #expect(SafariPreprocessingResult.parse(results(["url": "javascript:alert(1)", "title": "x"]))?.url == nil)
        #expect(SafariPreprocessingResult.parse(results(["url": "https://", "title": ""])) == nil)
    }

    @Test func parse_withoutResultsOrWithOtherTypes_isNil() {
        #expect(SafariPreprocessingResult.parse(nil) == nil)
        #expect(SafariPreprocessingResult.parse("text") == nil)
        #expect(SafariPreprocessingResult.parse([String: Any]()) == nil)
        #expect(SafariPreprocessingResult.parse(results(["url": 42, "title": 7])) == nil)
        // A property list without the wrapper key (a shared .plist file) is no result, even with a "title" key.
        #expect(SafariPreprocessingResult.parse(["title": "Nur Titel", "url": "https://example.com"]) == nil)
    }

    @Test func parse_cutsAVeryLongSelection() throws {
        let parsed = try #require(SafariPreprocessingResult.parse(results(["selection": String(repeating: "a", count: 150_000)])))
        #expect(parsed.selection?.count == SafariPreprocessingResult.maximumSelectionLength)
    }

    @Test func parts_feedTheClassification() throws {
        let parsed = try #require(SafariPreprocessingResult.parse(results(["url": "https://example.com/a", "title": "Titel", "selection": "Auswahl"])))
        let payload = SharePayload.classify(parsed.parts)
        #expect(payload?.kind == .url && payload?.text == "Auswahl" && payload?.pageTitle == "Titel")
    }
}
