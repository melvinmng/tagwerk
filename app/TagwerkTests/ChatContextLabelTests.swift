import Foundation
import Testing
@testable import Tagwerk

/// VoiceOver label of the context chip in the assistant sheet.
struct ChatContextLabelTests {
    @Test func textThatStartsWithTheContextPrefixIsNotPrefixedAgain() {
        #expect(ChatView.contextAccessibilityLabel(for: "Kontext: Aufgaben") == "Kontext: Aufgaben")
        #expect(ChatView.contextAccessibilityLabel(for: "Kontext: Notizen · ohne Privat") == "Kontext: Notizen · ohne Privat")
    }

    @Test func textWithoutThePrefixGetsItOnce() {
        // The planning context shows only the plain word when no days are loaded yet.
        #expect(ChatView.contextAccessibilityLabel(for: "Planen") == "Kontext: Planen")
    }
}
