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
}
