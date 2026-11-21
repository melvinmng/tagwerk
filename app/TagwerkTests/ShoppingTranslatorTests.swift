import AIKit
import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// A responder that never answers within the test's timeout.
private final class HangingResponder: ResponseStreaming, @unchecked Sendable {
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

@MainActor
struct ShoppingTranslatorTests {
    let responder = FakePlanResponder()
    final class Counter { var models = 0 }
    let modelCalls = Counter()
    private let plan = ShoppingTranslationPlan(openItems: [
        ShoppingItem(id: "reminder-1", name: "Äpfel", quantity: "6 Stück"),
        ShoppingItem(id: "reminder-2", name: "Karotten", quantity: "1 kg"),
    ])

    private func translator(_ responder: (any ResponseStreaming)? = nil, consent: Bool = true,
                            timeout: Duration = .seconds(30)) -> ShoppingTranslator {
        let calls = modelCalls
        return ShoppingTranslator(responder: responder ?? self.responder, model: { calls.models += 1; return "gpt-test" },
                                  hasConsent: { consent }, timeout: timeout)
    }

    private func answer(_ texts: [(Int, String)]) -> String {
        let object: [String: Any] = ["items": texts.map { ["i": $0.0, "text": $0.1] }]
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private func sentText() -> String {
        responder.calls[0].input.map { item -> String in
            if case .user(let text) = item { return text }
            return ""
        }.joined(separator: "\n")
    }

    @Test func translate_withoutConsent_neverCallsTheResponderOrTheModelList() async {
        await #expect(throws: ShoppingTranslator.Failure.consentMissing) { try await translator(consent: false).translate(plan, to: .english) }
        #expect(responder.calls.isEmpty && modelCalls.models == 0)
    }

    @Test func translate_sendsNamesAndTargetOnly() async throws {
        responder.enqueue(answer([(0, "Apples"), (1, "Carrots")]))
        _ = try await translator().translate(plan, to: .english)
        let text = sentText()
        #expect(text == #"{"items":[{"i":0,"text":"Äpfel"},{"i":1,"text":"Karotten"}],"target":"English"}"#)
        #expect(!text.contains("Stück") && !text.contains("kg") && !text.contains("reminder"), "no quantity and no identifier")
        #expect(responder.calls[0].schema == "shopping_translation" && responder.calls.count == 1)
    }

    @Test func translate_returnsCheckedChanges() async throws {
        responder.enqueue(answer([(0, "Apples"), (1, "Carrots")]))
        let changes = try await translator().translate(plan, to: .english)
        #expect(changes.map(\.newName) == ["Apples", "Carrots"] && changes.map(\.itemID) == ["reminder-1", "reminder-2"])
        #expect(changes.map(\.quantity) == ["6 Stück", "1 kg"])
    }

    @Test func translate_answerWithMissingItem_throwsMismatch() async {
        responder.enqueue(answer([(0, "Apples")]))
        await #expect(throws: ShoppingTranslator.Failure.mismatch) { try await translator().translate(plan, to: .english) }
    }

    @Test func translate_unreadableAnswer_throwsFailed() async {
        responder.enqueue("not json")
        await #expect(throws: ShoppingTranslator.Failure.failed) { try await translator().translate(plan, to: .english) }
    }

    @Test func translate_cutStream_throwsFailed() async {
        responder.enqueueEvents([.textDelta(answer([(0, "Apples"), (1, "Carrots")]))])
        await #expect(throws: ShoppingTranslator.Failure.failed) { try await translator().translate(plan, to: .english) }
    }

    @Test func translate_networkError_mapsToNetwork() async {
        for (error, expected) in [(ChatGPTError.network, ShoppingTranslator.Failure.network), (.notSignedIn, .signedOut),
                                  (.usageLimit, .usageLimit), (.incomplete, .failed)] {
            responder.enqueueFailure(error)
            await #expect(throws: expected) { try await translator().translate(plan, to: .english) }
        }
    }

    @Test func translate_timeout_mapsToFailed() async {
        await #expect(throws: ShoppingTranslator.Failure.failed) {
            try await translator(HangingResponder(), timeout: .milliseconds(50)).translate(plan, to: .english)
        }
    }

    @Test func translate_cancelled_rethrowsCancellation() async {
        let task = Task { @MainActor in try await translator(HangingResponder()).translate(plan, to: .english) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func translate_emptyPlan_sendsNothing() async throws {
        let changes = try await translator().translate(ShoppingTranslationPlan(openItems: []), to: .english)
        #expect(changes.isEmpty && responder.calls.isEmpty && modelCalls.models == 0)
    }

    @Test func failureMessages_neverContainItemNames() {
        let all: [ShoppingTranslator.Failure] = [.consentMissing, .network, .signedOut, .usageLimit, .failed, .mismatch]
        for failure in all {
            #expect(!failure.message.contains("Äpfel") && !failure.message.isEmpty)
        }
    }
}
