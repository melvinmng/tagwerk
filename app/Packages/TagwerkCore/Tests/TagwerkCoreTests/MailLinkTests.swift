import Foundation
import Testing
@testable import TagwerkCore

struct MailLinkTests {
    @Test func messageLink_wrapsAndEncodes() {
        #expect(MailLink.url(messageID: "abc123@mail.example.com")?.absoluteString == "message://%3Cabc123@mail.example.com%3E")
        // Brackets of the header are removed and set again, characters outside the safe set are encoded.
        #expect(MailLink.url(messageID: "<a b+c@example.com>")?.absoluteString == "message://%3Ca%20b%2Bc@example.com%3E")
    }

    @Test func emptyMessageID_hasNoLink() {
        #expect(MailLink.url(messageID: "") == nil)
        #expect(MailLink.url(messageID: "   ") == nil)
        #expect(MailLink.url(messageID: "<>") == nil)
    }
}
