import Foundation
import Testing
@testable import AIKit

/// Adjusting a pending tool call before the user confirms it (plan ki-vorschlaege-anpassen, task A1).
@MainActor
struct ConversationAdjustTests {
    let responder = FakeResponder()
    let handler = FakeToolHandler()

    func makeConversation(history: [InputItem] = []) -> Conversation {
        Conversation(responder: responder, tools: handler, model: { "gpt-test" }, instructions: { "Kontext" }, history: history)
    }

    /// A conversation with one open `create_task` card (`c1`).
    private func pendingConversation(arguments: String = #"{"title":"A"}"#) async throws -> (Conversation, ToolCall) {
        responder.enqueue(.events([call("c1", "create_task", arguments), .completed(usage: nil)]))
        let conversation = makeConversation()
        await conversation.send("Lege A an")
        let pending = try #require(conversation.pendingActions.first)
        return (conversation, pending)
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func object(_ text: String) throws -> [String: Any] {
        try object(Data(text.utf8))
    }

    private func title(of arguments: Data) throws -> String? {
        try object(arguments)["title"] as? String
    }

    // MARK: adjust

    @Test func adjust_replacesArgumentsOfPendingCall() async throws {
        let (conversation, pending) = try await pendingConversation()

        let adjusted = try #require(conversation.adjust(pending, arguments: Data(#"{"title":"B"}"#.utf8)))

        #expect(adjusted.id == "c1")
        #expect(adjusted.name == "create_task")
        #expect(try title(of: adjusted.arguments) == "B")
        #expect(conversation.pendingActions == [adjusted])
        #expect(conversation.isAdjusted(adjusted))
        #expect(conversation.history.contains(.functionCall(callID: "c1", name: "create_task", arguments: #"{"title":"B"}"#)))
        #expect(!conversation.history.contains(.functionCall(callID: "c1", name: "create_task", arguments: #"{"title":"A"}"#)))
    }

    @Test func adjust_unknownOrRunningCall_doesNothing() async throws {
        let (conversation, pending) = try await pendingConversation()
        let before = conversation.history

        let unknown = ToolCall(id: "nope", name: "create_task", arguments: Data("{}".utf8))
        #expect(conversation.adjust(unknown, arguments: Data(#"{"title":"B"}"#.utf8)) == nil)
        // Arguments that are not a JSON object cannot be a call's arguments.
        #expect(conversation.adjust(pending, arguments: Data("nonsense".utf8)) == nil)
        #expect(conversation.adjust(pending, arguments: Data("[1]".utf8)) == nil)
        #expect(conversation.history == before)
        #expect(!conversation.isAdjusted(pending))

        // A call that already ran is no longer pending.
        await conversation.confirm(pending)
        #expect(conversation.adjust(pending, arguments: Data(#"{"title":"B"}"#.utf8)) == nil)
    }

    @Test func adjust_whileCallRuns_doesNothing() async throws {
        let gate = Gate()
        let gated = GatedToolHandler(gate: gate)
        responder.enqueue(.events([call("c1", "create_task", #"{"title":"A"}"#), .completed(usage: nil)]))
        let conversation = Conversation(responder: responder, tools: gated, model: { "gpt-test" }, instructions: { "" }, history: [])
        await conversation.send("Lege A an")
        let pending = try #require(conversation.pendingActions.first)

        let running = Task { await conversation.confirm(pending) }
        while conversation.state != .runningAction { await Task.yield() }
        #expect(conversation.adjust(pending, arguments: Data(#"{"title":"B"}"#.utf8)) == nil)
        gate.open()
        await running.value
    }

    @Test func adjust_keepsOriginalForReset() async throws {
        let (conversation, pending) = try await pendingConversation()
        let adjusted = try #require(conversation.adjust(pending, arguments: Data(#"{"title":"B"}"#.utf8)))
        let twice = try #require(conversation.adjust(adjusted, arguments: Data(#"{"title":"C"}"#.utf8)))

        // The second adjustment must not overwrite what the model proposed.
        #expect(conversation.originalArguments(of: twice) == Data(#"{"title":"A"}"#.utf8))
        #expect(conversation.isAdjusted(twice))
    }

    @Test func adjust_backToTheProposal_isNotAdjusted() async throws {
        let (conversation, pending) = try await pendingConversation()
        let adjusted = try #require(conversation.adjust(pending, arguments: Data(#"{"title":"B"}"#.utf8)))
        let back = try #require(conversation.adjust(adjusted, arguments: Data(#"{"title":"A"}"#.utf8)))
        #expect(!conversation.isAdjusted(back))
    }

    @Test func resetAdjustment_restoresModelArguments() async throws {
        let (conversation, pending) = try await pendingConversation()
        let adjusted = try #require(conversation.adjust(pending, arguments: Data(#"{"title":"B"}"#.utf8)))

        let reset = try #require(conversation.resetAdjustment(adjusted))

        #expect(reset == pending)
        #expect(conversation.pendingActions == [pending])
        #expect(!conversation.isAdjusted(reset))
        #expect(conversation.originalArguments(of: reset) == nil)
        #expect(conversation.history.contains(.functionCall(callID: "c1", name: "create_task", arguments: #"{"title":"A"}"#)))
    }

    @Test func resetAdjustment_withoutAdjustment_returnsNil() async throws {
        let (conversation, pending) = try await pendingConversation()
        #expect(conversation.resetAdjustment(pending) == nil)
    }

    // MARK: confirm

    @Test func confirm_afterAdjust_runsEditedArguments() async throws {
        let (conversation, pending) = try await pendingConversation()
        let adjusted = try #require(conversation.adjust(pending, arguments: Data(#"{"title":"B"}"#.utf8)))

        await conversation.confirm(adjusted)

        #expect(handler.ran == [adjusted])
        #expect(conversation.pendingActions.isEmpty)
    }

    @Test func confirm_withStaleCallValue_runsTheCurrentAdjustment() async throws {
        let (conversation, pending) = try await pendingConversation()
        let adjusted = try #require(conversation.adjust(pending, arguments: Data(#"{"title":"B"}"#.utf8)))

        // A view may still hold the call as the model proposed it.
        await conversation.confirm(pending)

        #expect(handler.ran == [adjusted])
    }

    @Test func confirm_afterAdjust_outputNamesAdjustmentAndOriginal() async throws {
        handler.outputs["create_task"] = #"{"ok":true,"title":"B"}"#
        let (conversation, pending) = try await pendingConversation()
        let adjusted = try #require(conversation.adjust(pending, arguments: Data(#"{"title":"B"}"#.utf8)))

        await conversation.confirm(adjusted)

        let output = try #require(conversation.history.compactMap { item -> String? in
            if case .functionOutput("c1", let output) = item { output } else { nil }
        }.first)
        let parsed = try object(output)
        #expect(parsed["ok"] as? Bool == true)
        #expect(parsed["title"] as? String == "B")
        #expect(parsed["adjusted_by_user"] as? Bool == true)
        let proposed = try #require(parsed["proposed"] as? [String: Any])
        #expect(proposed["title"] as? String == "A")
        // The model sees the same output the card gets.
        #expect(responder.inputs.last?.contains(.functionOutput(callID: "c1", output: output)) == true)
    }

    @Test func confirm_afterAdjust_errorStaysReadableOnTopLevel() async throws {
        handler.outputs["create_task"] = #"{"error":"Titel fehlt."}"#
        let (conversation, pending) = try await pendingConversation()
        let adjusted = try #require(conversation.adjust(pending, arguments: Data(#"{"title":""}"#.utf8)))

        await conversation.confirm(adjusted)

        let output = try #require(conversation.history.compactMap { item -> String? in
            if case .functionOutput("c1", let output) = item { output } else { nil }
        }.first)
        #expect(try object(output)["error"] as? String == "Titel fehlt.")
    }

    @Test func confirm_afterAdjust_plainTextOutput_getsASentence() async throws {
        handler.outputs["create_task"] = "Angelegt."
        let (conversation, pending) = try await pendingConversation()
        let adjusted = try #require(conversation.adjust(pending, arguments: Data(#"{"title":"B"}"#.utf8)))

        await conversation.confirm(adjusted)

        let output = try #require(conversation.history.compactMap { item -> String? in
            if case .functionOutput("c1", let output) = item { output } else { nil }
        }.first)
        #expect(output.hasPrefix("Angelegt."))
        #expect(output.contains(#"{"title":"A"}"#))
    }

    @Test func confirm_withoutAdjust_outputUnchanged() async throws {
        let (conversation, pending) = try await pendingConversation()

        await conversation.confirm(pending)

        #expect(conversation.history.contains(.functionOutput(callID: "c1", output: #"{"ok":true}"#)))
    }

    @Test func confirm_afterAdjustBackToProposal_outputUnchanged() async throws {
        let (conversation, pending) = try await pendingConversation()
        let adjusted = try #require(conversation.adjust(pending, arguments: Data(#"{"title":"B"}"#.utf8)))
        let back = try #require(conversation.adjust(adjusted, arguments: Data(#"{"title":"A"}"#.utf8)))

        await conversation.confirm(back)

        #expect(conversation.history.contains(.functionOutput(callID: "c1", output: #"{"ok":true}"#)))
    }

    @Test func decline_afterAdjust_outputIsDeclined_andOriginalIsForgotten() async throws {
        let (conversation, pending) = try await pendingConversation()
        let adjusted = try #require(conversation.adjust(pending, arguments: Data(#"{"title":"B"}"#.utf8)))

        await conversation.decline(adjusted)

        #expect(conversation.history.contains(.functionOutput(callID: "c1", output: Conversation.declinedOutput)))
        #expect(conversation.originalArguments(of: adjusted) == nil)
        #expect(!conversation.isAdjusted(adjusted))
    }

    // MARK: messages and stored form

    @Test func messages_showAdjustedArguments() async throws {
        let (conversation, pending) = try await pendingConversation()
        let adjusted = try #require(conversation.adjust(pending, arguments: Data(#"{"title":"B"}"#.utf8)))

        #expect(conversation.messages.last?.content == .action(adjusted, .pending))
    }

    @Test func storableHistory_usesStoredFormOfAdjustedCall() async throws {
        var seenArguments: [String] = []
        handler.storedFormOverride = { call, output in
            guard call.name == "create_task" else { return nil }
            seenArguments.append(String(decoding: call.arguments, as: UTF8.self))
            return (#"{"stored":true}"#, output)
        }
        let (conversation, pending) = try await pendingConversation()
        let adjusted = try #require(conversation.adjust(pending, arguments: Data(#"{"title":"B"}"#.utf8)))
        await conversation.confirm(adjusted)

        let stored = conversation.storableHistory

        #expect(seenArguments.allSatisfy { $0 == #"{"title":"B"}"# })
        #expect(stored.contains(.functionCall(callID: "c1", name: "create_task", arguments: #"{"stored":true}"#)))
    }

    @Test func restore_withOpenAdjustedCall_closesItAsInterrupted() async throws {
        // An open call that was adjusted is saved like any open call; the proposal of the model is not stored.
        let history: [InputItem] = [.user("Lege A an"),
                                    .functionCall(callID: "c1", name: "create_task", arguments: #"{"title":"B"}"#)]
        let conversation = makeConversation(history: history)

        #expect(conversation.pendingActions.isEmpty)
        #expect(conversation.history.last == .functionOutput(callID: "c1", output: Conversation.interruptedOutput))
        let restored = ToolCall(id: "c1", name: "create_task", arguments: Data(#"{"title":"B"}"#.utf8))
        #expect(!conversation.isAdjusted(restored))
    }

    @Test func send_withAdjustedCallOpen_declinesIt() async throws {
        let (conversation, pending) = try await pendingConversation()
        let adjusted = try #require(conversation.adjust(pending, arguments: Data(#"{"title":"B"}"#.utf8)))

        await conversation.send("Doch nicht")

        #expect(conversation.pendingActions.isEmpty)
        #expect(!conversation.isAdjusted(adjusted))
        #expect(handler.ran.isEmpty)
    }
}
