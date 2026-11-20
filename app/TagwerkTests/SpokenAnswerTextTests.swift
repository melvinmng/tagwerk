import SwiftUI
import Testing
@testable import Tagwerk

@MainActor
struct SpokenAnswerTextTests {
    private func highlightedText(_ attributed: AttributedString) -> String {
        attributed.runs.filter { $0.backgroundColor != nil }.map { String(attributed[$0.range].characters) }.joined()
    }

    @Test func highlightsTheSpokenSentenceInRenderedText() {
        let text = AttributedString("Das ist wichtig. Danach kommt der Rest.")
        let result = SpokenAnswerText.highlighted(text, sentence: "Das ist wichtig.")
        #expect(highlightedText(result) == "Das ist wichtig.")
    }

    @Test func highlightsOnlyUpToTheEndOfTheSentence() {
        let text = AttributedString("Eins. Zwei drei vier. Fünf.")
        #expect(highlightedText(SpokenAnswerText.highlighted(text, sentence: "Zwei drei vier.")) == "Zwei drei vier.")
    }

    @Test func leavesTextUnchanged_whenTheSentenceIsNotInIt() {
        let text = AttributedString("Ein ganz anderer Absatz.")
        #expect(SpokenAnswerText.highlighted(text, sentence: "Das steht nirgends.") == text)
    }

    @Test func findsTheSentenceInTextWithoutMarkdownSymbols() {
        // The view searches the shown characters, so the bold marks of the source do not get in the way.
        var text = AttributedString("Das ist ")
        var bold = AttributedString("sehr wichtig")
        bold.inlinePresentationIntent = .stronglyEmphasized
        text.append(bold)
        text.append(AttributedString(" heute."))
        let result = SpokenAnswerText.highlighted(text, sentence: "Das ist sehr wichtig heute.")
        #expect(highlightedText(result) == "Das ist sehr wichtig heute.")
    }
}
