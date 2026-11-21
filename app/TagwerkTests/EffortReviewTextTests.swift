import Testing
import TagwerkCore
@testable import Tagwerk

struct EffortReviewTextTests {
    private func group(_ kind: EffortGroupKind = .source(.reminders), count: Int = 7, deviation: Int?) -> EffortGroup {
        EffortGroup(kind: kind, count: count, medianRatio: deviation.map { 1 + Double($0) / 100 }, deviationPercent: deviation)
    }

    @Test func longerThanEstimated_german() {
        let detail = EffortReviewText.detail(of: group(deviation: 40), language: .german)
        #expect(detail.hasPrefix("Dauern im Schnitt 40") && detail.hasSuffix("länger als geschätzt"))
        #expect(EffortReviewText.name(of: .source(.reminders), language: .german) == "Erinnerungen")
        #expect(EffortReviewText.count(7, language: .german) == "7 Aufgaben")
        #expect(EffortReviewText.count(1, language: .german) == "1 Aufgabe")
    }

    @Test func shorterThanEstimated_german() {
        let detail = EffortReviewText.detail(of: group(deviation: -25), language: .german)
        #expect(detail.hasPrefix("Dauern im Schnitt 25") && detail.hasSuffix("kürzer als geschätzt"))
    }

    @Test func english_texts() {
        #expect(EffortReviewText.detail(of: group(deviation: 40), language: .english) == "Take 40% longer than estimated on average")
        #expect(EffortReviewText.detail(of: group(deviation: -25), language: .english) == "Take 25% less time than estimated on average")
        #expect(EffortReviewText.detail(of: group(deviation: 0), language: .english) == "Take about as long as estimated")
        #expect(EffortReviewText.name(of: .source(.github), language: .english) == "GitHub issues")
        #expect(EffortReviewText.name(of: .label("Schreiben"), language: .english) == "Schreiben")
        #expect(EffortReviewText.count(1, language: .english) == "1 task")
    }

    @Test func tooFewSamples() {
        #expect(EffortReviewText.detail(of: group(count: 2, deviation: nil), language: .german) == "Noch zu wenige Messungen.")
        #expect(EffortReviewText.detail(of: group(count: 2, deviation: nil), language: .english) == "Not enough measurements yet.")
    }

    @Test func withinFivePercent_saysAsEstimated() {
        for deviation in [-5, -2, 0, 3, 5] {
            #expect(EffortReviewText.detail(of: group(deviation: deviation), language: .german) == "Dauern etwa so lange wie geschätzt")
        }
        #expect(EffortReviewText.detail(of: group(deviation: 6), language: .german).hasSuffix("länger als geschätzt"))
    }

    /// The percent format of the language separates the number and the sign with a no-break space; the tests compare plain spaces.
    private func plain(_ text: String) -> String { text.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ") }

    @Test func position_centreIsAThird() {
        #expect(abs(EffortReviewText.position(deviationPercent: 0) - 1.0 / 3.0) < 0.0001)
        #expect(EffortReviewText.position(deviationPercent: -50) == 0)
        #expect(EffortReviewText.position(deviationPercent: 100) == 1)
        #expect(abs(EffortReviewText.position(deviationPercent: 25) - 0.5) < 0.0001)
    }

    @Test func position_clampsAtBothEnds() {
        #expect(EffortReviewText.position(deviationPercent: -90) == 0)
        #expect(EffortReviewText.position(deviationPercent: 250) == 1)
    }

    @Test func deviationLabel_signsAndTolerance() {
        #expect(plain(EffortReviewText.deviationLabel(40, language: .german)) == "+40 %")
        #expect(plain(EffortReviewText.deviationLabel(-15, language: .german)) == "−15 %")
        #expect(plain(EffortReviewText.deviationLabel(3, language: .german)) == "±0 %")
        #expect(plain(EffortReviewText.deviationLabel(-5, language: .german)) == "±0 %")
        #expect(plain(EffortReviewText.deviationLabel(6, language: .german)) == "+6 %")
        #expect(EffortReviewText.deviationLabel(40, language: .english) == "+40%")
    }

    @Test func pendingLabel_inBothLanguages() {
        #expect(EffortReviewText.pendingLabel(count: 2, language: .german) == "2 von 3 Messungen")
        #expect(EffortReviewText.pendingLabel(count: 2, language: .english) == "2 of 3 measurements")
    }
}
