import AIKit
import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// Translating a recipe note with one request. The note texts are invented; the responder is a fake.
@MainActor
struct RecipeTranslatorTests {
    private let responder = FakePlanResponder()
    private final class Counter { var models = 0 }
    private let modelCalls = Counter()
    private let photoID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    private var note: String {
        """
        # Red Lentil Curry

        Servings: 4

        ## Ingredients
        - 250 g red lentils
        - 2 tbsp curry paste

        ## Instructions
        1. Chop the onions.

        Tip: tastes better the next day.
        ![Dish](attachment:\(photoID.uuidString))

        Source: [chefkoch.de](https://www.chefkoch.de/rezepte/123)
        """
    }

    private func translator(consent: Bool = true, timeout: Duration = .seconds(30), responder custom: (any ResponseStreaming)? = nil) -> RecipeTranslator {
        let calls = modelCalls
        return RecipeTranslator(responder: custom ?? responder, model: { calls.models += 1; return "gpt-test" },
                                hasConsent: { consent }, timeout: timeout)
    }

    /// The answer of a model that translates every requested line, as JSON.
    private func answer(for text: String, replacing table: [String: String] = [:], dropping dropped: Set<Int> = []) -> String {
        let plan = RecipeTranslationPlan(markdown: text)
        let lines = plan.request.filter { !dropped.contains($0.index) }.map { ["i": $0.index, "text": table[$0.text] ?? $0.text] as [String: Any] }
        return String(decoding: try! JSONSerialization.data(withJSONObject: ["lines": lines]), as: UTF8.self)
    }

    private let table = [
        "Red Lentil Curry": "Rotes Linsencurry", "250 g red lentils": "250 g rote Linsen", "2 tbsp curry paste": "2 EL Currypaste",
        "Chop the onions.": "Zwiebeln würfeln.", "Tip: tastes better the next day.": "Tipp: schmeckt am nächsten Tag besser."
    ]

    private func sentText() -> String {
        responder.calls[0].input.map { item -> String in
            if case .user(let text) = item { text } else { "" }
        }.joined(separator: "\n")
    }

    // MARK: Sending

    @Test func translate_sendsOnlyTranslatableLines() async throws {
        responder.enqueue(answer(for: note, replacing: table))
        _ = try await translator().translate(note, to: .german)
        let sent = sentText()
        #expect(sent.contains("250 g red lentils") && sent.contains("Chop the onions.") && sent.contains("Tip: tastes better"))
        #expect(sent.contains(#""target":"Deutsch""#))
        #expect(!sent.contains("Ingredients") && !sent.contains("Instructions"))
        #expect(!sent.contains("attachment:") && !sent.contains(photoID.uuidString))
        #expect(!sent.contains("Servings") && !sent.contains("chefkoch") && !sent.contains("Source"))
        #expect(responder.calls.count == 1 && responder.calls[0].schema == "recipe_translation")
        #expect(responder.instructions[0].contains("Keep every number exactly"))
    }

    @Test func translate_withoutConsent_neverCallsTheResponder() async {
        await #expect(throws: RecipeTranslator.Failure.consentMissing) { try await translator(consent: false).translate(note, to: .german) }
        #expect(responder.calls.isEmpty && modelCalls.models == 0)
    }

    @Test func translate_noteWithoutIngredients_neverCallsTheResponder() async {
        await #expect(throws: RecipeTranslator.Failure.notARecipe) {
            try await translator().translate("# Einkaufsideen\n\nMehl kaufen.\n", to: .english)
        }
        // Not a recipe is reported before the consent, so a missing consent does not hide it.
        await #expect(throws: RecipeTranslator.Failure.notARecipe) {
            try await translator(consent: false).translate("Nur ein Satz", to: .english)
        }
        #expect(responder.calls.isEmpty && modelCalls.models == 0)
    }

    @Test func translate_returnsAssembledText() async throws {
        responder.enqueue(answer(for: note, replacing: table))
        let result = try await translator().translate(note, to: .german)
        #expect(result == """
        # Rotes Linsencurry

        Portionen: 4

        ## Zutaten
        - 250 g rote Linsen
        - 2 EL Currypaste

        ## Zubereitung
        1. Zwiebeln würfeln.

        Tipp: schmeckt am nächsten Tag besser.
        ![Dish](attachment:\(photoID.uuidString))

        Quelle: [chefkoch.de](https://www.chefkoch.de/rezepte/123)
        """)
    }

    // MARK: Checking the answer

    @Test func translate_answerWithMissingLine_throwsMismatch() async {
        let plan = RecipeTranslationPlan(markdown: note)
        responder.enqueue(answer(for: note, replacing: table, dropping: [plan.request[1].index]))
        await #expect(throws: RecipeTranslator.Failure.mismatch) { try await translator().translate(note, to: .german) }
    }

    @Test func translate_answerWithRepeatedIndex_throwsMismatch() async {
        let plan = RecipeTranslationPlan(markdown: note)
        let first = plan.request[0].index
        responder.enqueue(#"{"lines":[{"i":\#(first),"text":"A"},{"i":\#(first),"text":"B"}]}"#)
        await #expect(throws: RecipeTranslator.Failure.mismatch) { try await translator().translate(note, to: .german) }
    }

    @Test func translate_answerWithChangedAmount_throwsMismatch() async {
        responder.enqueue(answer(for: note, replacing: table.merging(["250 g red lentils": "255 g rote Linsen"]) { $1 }))
        await #expect(throws: RecipeTranslator.Failure.mismatch) { try await translator().translate(note, to: .german) }
    }

    @Test func translate_answerThatIsNoJSON_throwsFailed() async {
        responder.enqueue("Hier ist die Übersetzung: …")
        await #expect(throws: RecipeTranslator.Failure.failed) { try await translator().translate(note, to: .german) }
    }

    // MARK: Transport

    @Test func translate_cutStream_throwsFailed() async {
        responder.enqueueEvents([.textDelta(#"{"lines":["#)])
        await #expect(throws: RecipeTranslator.Failure.failed) { try await translator().translate(note, to: .german) }
    }

    @Test func translate_chatGPTErrors_mapToFailures() async {
        responder.enqueueFailure(.network)
        await #expect(throws: RecipeTranslator.Failure.network) { try await translator().translate(note, to: .german) }
        responder.enqueueFailure(.notSignedIn)
        await #expect(throws: RecipeTranslator.Failure.signedOut) { try await translator().translate(note, to: .german) }
        responder.enqueueFailure(.usageLimit)
        await #expect(throws: RecipeTranslator.Failure.usageLimit) { try await translator().translate(note, to: .german) }
    }

    @Test func translate_stalledAnswer_throwsFailed() async {
        final class Stalling: ResponseStreaming, @unchecked Sendable {
            func respond(model: String, instructions: String, input: [InputItem], tools: [ToolDefinition],
                         jsonSchema: (name: String, schema: Data)?) -> AsyncThrowingStream<StreamEvent, Error> {
                AsyncThrowingStream { continuation in
                    Task {
                        try? await Task.sleep(for: .seconds(5))
                        continuation.finish()
                    }
                }
            }
        }
        await #expect(throws: RecipeTranslator.Failure.failed) {
            try await translator(timeout: .milliseconds(100), responder: Stalling()).translate(note, to: .german)
        }
    }

    @Test func translate_tooLong_throwsBeforeSending() async {
        let long = "## Zutaten\n" + (0..<(RecipeTranslationPlan.maximumLines + 1)).map { "- Zutat \($0)" }.joined(separator: "\n")
        await #expect(throws: RecipeTranslator.Failure.tooLong) { try await translator().translate(long, to: .english) }
        #expect(responder.calls.isEmpty && modelCalls.models == 0)
    }

    // MARK: Privacy

    @Test func failureMessages_neverContainNoteText() async {
        let secret = "Geheimzutat Zimtstern"
        let text = "# Plätzchen\n\n## Zutaten\n- 100 g \(secret)\n"
        let failures: [RecipeTranslator.Failure] = [.consentMissing, .network, .signedOut, .usageLimit, .failed, .tooLong, .notARecipe, .mismatch]
        #expect(failures.allSatisfy { !$0.message.contains(secret) && !$0.message.isEmpty })
        responder.enqueue(#"{"lines":[]}"#)
        do {
            _ = try await translator().translate(text, to: .english)
            Issue.record("An answer without lines must not be accepted")
        } catch {
            #expect(!"\(error)".contains(secret) && !"\(error)".contains("Plätzchen"))
        }
    }

    @Test func instructionsAndSchema_areFixedTexts() {
        #expect(RecipeTranslator.instructions.contains("attachment:"))
        #expect((try? JSONSerialization.jsonObject(with: RecipeTranslator.schema)) != nil)
    }
}
