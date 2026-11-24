import Foundation
import Testing
@testable import TagwerkCore

struct ProductSearchRulesTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    // MARK: Limiter

    @Test func limits_areTheOperatorsRules() {
        #expect(ProductSearchRules.searchLimit == 10)
        #expect(ProductSearchRules.productLimit == 15)
        #expect(ProductSearchRules.window == 60)
        #expect(ProductSearchRules.minimumQueryLength == 3)
    }

    @Test func limiter_blocksAboveLimit_andReportsWaitTime() {
        var limiter = ProductSearchRules.makeSearchLimiter()
        for second in 0..<10 { #expect(limiter.attempt(at: at(Double(second))) == .allowed) }
        // The 11th within the minute waits until the first one is 60 s old: 60 − 10 = 50 s.
        #expect(limiter.attempt(at: at(10)) == .wait(50))
        #expect(limiter.attempt(at: at(10.5)) == .wait(50), "49.5 s are rounded up")
    }

    @Test func limiter_refusedRequestUsesNoSlot() {
        var limiter = RequestLimiter(limit: 2, window: 60)
        #expect(limiter.attempt(at: at(0)) == .allowed)
        #expect(limiter.attempt(at: at(1)) == .allowed)
        for second in 2..<30 { _ = limiter.attempt(at: at(Double(second))) }
        // Had the refusals counted, the window would still be full at 60 s.
        #expect(limiter.attempt(at: at(60)) == .allowed, "the first slot is free after 60 s")
        #expect(limiter.attempt(at: at(61)) == .allowed, "the second slot too: refusals did not take one")
        #expect(limiter.attempt(at: at(62)) != .allowed)
    }

    @Test func limiter_decisionDoesNotUseASlot() {
        var limiter = RequestLimiter(limit: 1, window: 60)
        #expect(limiter.decision(at: at(0)) == .allowed)
        #expect(limiter.decision(at: at(0)) == .allowed)
        #expect(limiter.attempt(at: at(0)) == .allowed)
        #expect(limiter.decision(at: at(1)) == .wait(59))
    }

    @Test func limiter_windowSlides() {
        var limiter = RequestLimiter(limit: 3, window: 60)
        _ = limiter.attempt(at: at(0))
        _ = limiter.attempt(at: at(30))
        _ = limiter.attempt(at: at(40))
        #expect(limiter.attempt(at: at(50)) == .wait(10))
        #expect(limiter.attempt(at: at(60)) == .allowed, "the request of second 0 left the window")
        #expect(limiter.attempt(at: at(61)) == .wait(29), "now 30, 40 and 60 are inside")
    }

    @Test func limiter_productLimitIsIndependentAndHigher() {
        var search = ProductSearchRules.makeSearchLimiter()
        var product = ProductSearchRules.makeProductLimiter()
        for _ in 0..<10 { _ = search.attempt(at: at(0)) }
        #expect(search.attempt(at: at(1)) != .allowed)
        for _ in 0..<15 { #expect(product.attempt(at: at(0)) == .allowed) }
        #expect(product.attempt(at: at(1)) != .allowed)
    }

    // MARK: Contact address

    @Test func contact_acceptsPlainAddresses_andTrims() {
        #expect(ProductSearchRules.validContact("test@example.org") == "test@example.org")
        #expect(ProductSearchRules.validContact("  first.last+tag@mail.example.org \n") == "first.last+tag@mail.example.org")
    }

    @Test func contactAddress_invalid_notAccepted() {
        let invalid = ["", "   ", "plain", "a@b", "a@@b.org", "@example.org", "a@.org", "a b@example.org", "<a@example.org>",
                       "(a@example.org)", "\"a\"@example.org", "a@example.org, b@example.org", "ä@example.org", "a@exämple.org",
                       // Header injection: nothing after a line break may get through.
                       "a@example.org\r\nX-Evil: 1", "a@example.org\nBcc: b@example.org", "a\r\n@example.org"]
        for text in invalid { #expect(ProductSearchRules.validContact(text) == nil, "\(text.debugDescription) is not an address") }
        #expect(ProductSearchRules.validContact(nil) == nil)
    }

    @Test func contact_aTrailingLineBreakIsOnlyWhitespace() {
        #expect(ProductSearchRules.validContact("a@example.org\r\n") == "a@example.org")
    }

    @Test func contactChange_clearedAcceptedInvalid() {
        #expect(ProductSearchRules.contactChange(entered: "") == .cleared)
        #expect(ProductSearchRules.contactChange(entered: "  \n ") == .cleared)
        #expect(ProductSearchRules.contactChange(entered: " me@example.org ") == .accepted("me@example.org"))
        #expect(ProductSearchRules.contactChange(entered: "me@") == .invalid)
    }

    // MARK: User agent

    @Test func userAgent_hasTheExactFormat() {
        #expect(ProductSearchRules.userAgent(version: "9.9", contact: "test@example.org") == "Tagwerk/9.9 (test@example.org)")
        #expect(ProductSearchRules.userAgent(version: "1.2.3", contact: " test@example.org ") == "Tagwerk/1.2.3 (test@example.org)")
    }

    @Test func userAgent_needsAValidAddress() {
        #expect(ProductSearchRules.userAgent(version: "1.0", contact: nil) == nil)
        #expect(ProductSearchRules.userAgent(version: "1.0", contact: "") == nil)
        #expect(ProductSearchRules.userAgent(version: "1.0", contact: "no address") == nil)
    }

    @Test func userAgent_versionCannotSmuggleCharacters() {
        #expect(ProductSearchRules.userAgent(version: "1.0 (x)\r\nEvil: 1", contact: "t@example.org") == "Tagwerk/1.0xEvil1 (t@example.org)")
        #expect(ProductSearchRules.userAgent(version: "", contact: "t@example.org") == "Tagwerk/0 (t@example.org)")
    }
}
