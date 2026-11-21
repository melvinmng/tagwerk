import Foundation
import Synchronization
import Testing
@testable import AIKit

/// Scripted model: each call pops the next reply and records the input it was sent.
final class FakeResponder: ResponseStreaming {
    enum Reply: Sendable {
        case events([StreamEvent])
        case failure(ChatGPTError)
        /// Delivers the events and then ends without `response.completed`.
        case cut([StreamEvent])
    }

    private let state = Mutex<(replies: [Reply], inputs: [[InputItem]], instructions: [String])>(([], [], []))
    private let fallbackReply = Mutex<Reply>(.events([.textDelta("Fertig."), .completed(usage: nil)]))
    /// Used when the script is exhausted.
    var fallback: Reply {
        get { fallbackReply.withLock { $0 } }
        set { fallbackReply.withLock { $0 = newValue } }
    }

    func enqueue(_ reply: Reply) { state.withLock { $0.replies.append(reply) } }
    var inputs: [[InputItem]] { state.withLock { $0.inputs } }
    var instructions: [String] { state.withLock { $0.instructions } }

    func respond(model: String, instructions: String, input: [InputItem], tools: [ToolDefinition],
                 jsonSchema: (name: String, schema: Data)?) -> AsyncThrowingStream<StreamEvent, Error> {
        let fallback = self.fallback
        let reply = state.withLock { state -> Reply in
            state.inputs.append(input)
            state.instructions.append(instructions)
            return state.replies.isEmpty ? fallback : state.replies.removeFirst()
        }
        return AsyncThrowingStream { continuation in
            switch reply {
            case .events(let events):
                events.forEach { continuation.yield($0) }
                continuation.finish()
            case .failure(let error):
                continuation.finish(throwing: error)
            case .cut(let events):
                events.forEach { continuation.yield($0) }
                continuation.finish(throwing: ChatGPTError.incomplete)
            }
        }
    }
}

@MainActor
final class FakeToolHandler: ToolHandler {
    var outputs: [String: String] = [:]
    private(set) var ran: [ToolCall] = []
    let writeTools: Set<String>
    /// Replaces `storedForm` for the calls it returns a value for; `nil` keeps the protocol default.
    var storedFormOverride: ((ToolCall, String?) -> (arguments: String, output: String?)?)?
    var activityTools: Set<String> = []

    init(writeTools: Set<String> = ["create_task"]) {
        self.writeTools = writeTools
    }

    var definitions: [ToolDefinition] {
        [ToolDefinition(name: "list_tasks", description: "", parameters: Data("{}".utf8)),
         ToolDefinition(name: "create_task", description: "", parameters: Data("{}".utf8))]
    }

    func kind(of name: String) -> ToolKind { writeTools.contains(name) ? .write : .read }

    func run(_ call: ToolCall) async -> String {
        ran.append(call)
        return outputs[call.name] ?? #"{"ok":true}"#
    }

    func storedForm(of call: ToolCall, output: String?) -> (arguments: String, output: String?) {
        storedFormOverride?(call, output) ?? (String(decoding: call.arguments, as: UTF8.self), output)
    }

    func showsActivity(_ name: String) -> Bool { activityTools.contains(name) }
}

func call(_ id: String, _ name: String, _ arguments: String = "{}") -> StreamEvent {
    .functionCall(callID: id, name: name, arguments: arguments)
}

@MainActor
struct ConversationTests {
    let responder = FakeResponder()
    let handler = FakeToolHandler()

    func makeConversation(history: [InputItem] = []) -> Conversation {
        Conversation(responder: responder, tools: handler, model: { "gpt-test" },
                     instructions: { "Kontext: Planen" }, history: history)
    }

    @Test func send_textAnswer_appendsUserAndAssistant() async {
        responder.enqueue(.events([.textDelta("Hal"), .textDelta("lo"), .completed(usage: nil)]))
        let conversation = makeConversation()
        await conversation.send("Hi")
        #expect(conversation.history == [.user("Hi"), .assistant("Hallo")])
        #expect(conversation.messages.map(\.content) == [.user("Hi"), .assistant("Hallo")])
        #expect(conversation.state == .idle)
        #expect(responder.instructions == ["Kontext: Planen"])
    }

    @Test func readTool_runsWithoutConfirmation_andContinues() async {
        responder.enqueue(.events([call("c1", "list_tasks"), .completed(usage: nil)]))
        responder.enqueue(.events([.textDelta("Du hast 2 Aufgaben."), .completed(usage: nil)]))
        handler.outputs["list_tasks"] = #"[{"id":"a"},{"id":"b"}]"#
        let conversation = makeConversation()

        await conversation.send("Was steht an?")

        #expect(handler.ran.map(\.name) == ["list_tasks"])
        #expect(responder.inputs.count == 2)
        #expect(responder.inputs[1] == [
            .user("Was steht an?"),
            .functionCall(callID: "c1", name: "list_tasks", arguments: "{}"),
            .functionOutput(callID: "c1", output: #"[{"id":"a"},{"id":"b"}]"#),
        ])
        #expect(conversation.history.last == .assistant("Du hast 2 Aufgaben."))
        // Read calls are not shown as action cards.
        #expect(conversation.messages.map(\.content) == [.user("Was steht an?"), .assistant("Du hast 2 Aufgaben.")])
    }

    @Test func writeTool_waitsForConfirm_thenSendsOutput() async throws {
        responder.enqueue(.events([.textDelta("Ich lege sie an."), call("c1", "create_task", #"{"title":"A"}"#), .completed(usage: nil)]))
        responder.enqueue(.events([.textDelta("Angelegt."), .completed(usage: nil)]))
        let conversation = makeConversation()

        await conversation.send("Lege A an")
        #expect(handler.ran.isEmpty)
        #expect(conversation.state == .waitingForConfirmation)
        #expect(responder.inputs.count == 1)
        let pending = try #require(conversation.pendingActions.first)
        #expect(pending == ToolCall(id: "c1", name: "create_task", arguments: Data(#"{"title":"A"}"#.utf8)))
        #expect(conversation.messages.last?.content == .action(pending, .pending))

        await conversation.confirm(pending)

        #expect(handler.ran == [pending])
        #expect(conversation.pendingActions.isEmpty)
        #expect(responder.inputs.count == 2)
        #expect(responder.inputs[1].suffix(2) == [
            .functionCall(callID: "c1", name: "create_task", arguments: #"{"title":"A"}"#),
            .functionOutput(callID: "c1", output: #"{"ok":true}"#),
        ])
        #expect(conversation.messages.map(\.content) == [
            .user("Lege A an"), .assistant("Ich lege sie an."), .action(pending, .done(#"{"ok":true}"#)), .assistant("Angelegt."),
        ])
    }

    @Test func decline_sendsDeclinedOutput() async throws {
        responder.enqueue(.events([call("c1", "create_task"), .completed(usage: nil)]))
        let conversation = makeConversation()
        await conversation.send("Lege A an")
        let pending = try #require(conversation.pendingActions.first)

        await conversation.decline(pending)

        #expect(handler.ran.isEmpty)
        #expect(responder.inputs.last?.last == .functionOutput(callID: "c1", output: Conversation.declinedOutput))
        #expect(conversation.messages.contains { $0.content == .action(pending, .declined) })
    }

    @Test func writeToolError_isReportedAsOutput() async throws {
        handler.outputs["create_task"] = #"{"error":"Die Quelle ist offline."}"#
        responder.enqueue(.events([call("c1", "create_task"), .completed(usage: nil)]))
        let conversation = makeConversation()
        await conversation.send("Lege A an")
        let pending = try #require(conversation.pendingActions.first)

        await conversation.confirm(pending)

        #expect(responder.inputs.last?.last == .functionOutput(callID: "c1", output: #"{"error":"Die Quelle ist offline."}"#))
        #expect(conversation.messages.contains { $0.content == .action(pending, .done(#"{"error":"Die Quelle ist offline."}"#)) })
    }

    @Test func mixedReadWrite_parallel_waitsForAllOutputs() async throws {
        responder.enqueue(.events([call("r1", "list_tasks"), call("w1", "create_task"), call("w2", "create_task"),
                                   .completed(usage: nil)]))
        let conversation = makeConversation()
        await conversation.send("Mach beides")

        #expect(handler.ran.map(\.id) == ["r1"])
        #expect(conversation.pendingActions.map(\.id) == ["w1", "w2"])
        await conversation.confirm(conversation.pendingActions[0])
        // One write is still open: no follow-up call yet.
        #expect(responder.inputs.count == 1)
        await conversation.decline(conversation.pendingActions[0])
        #expect(responder.inputs.count == 2)
        let outputs = responder.inputs[1].compactMap { item -> String? in
            if case .functionOutput(let id, _) = item { return id } else { return nil }
        }
        #expect(Set(outputs) == ["r1", "w1", "w2"])
    }

    @Test func sendWhilePending_declinesOpenCalls() async throws {
        responder.enqueue(.events([call("c1", "create_task"), .completed(usage: nil)]))
        let conversation = makeConversation()
        await conversation.send("Lege A an")

        await conversation.send("Doch nicht, zeig mir lieber die Liste")

        #expect(conversation.pendingActions.isEmpty)
        #expect(handler.ran.isEmpty)
        #expect(responder.inputs[1] == [
            .user("Lege A an"),
            .functionCall(callID: "c1", name: "create_task", arguments: "{}"),
            .functionOutput(callID: "c1", output: Conversation.declinedOutput),
            .user("Doch nicht, zeig mir lieber die Liste"),
        ])
    }

    @Test func stopsAfterEightRounds() async {
        responder.fallback = .events([call(UUID().uuidString, "list_tasks"), .completed(usage: nil)])
        let conversation = makeConversation()
        await conversation.send("Endlosschleife")

        #expect(responder.inputs.count == 8)
        #expect(handler.ran.count == 7)
        #expect(conversation.roundLimitReached)
        #expect(conversation.state == .idle)
        // The calls of round 8 are closed with a fixed output, so the history has no open call.
        #expect(Conversation.openCallIDs(in: conversation.history).isEmpty)
        #expect(conversation.history.last == .functionOutput(callID: lastCallID(conversation.history), output: Conversation.roundLimitOutput))
    }

    private func lastCallID(_ history: [InputItem]) -> String {
        for item in history.reversed() { if case .functionCall(let id, _, _) = item { return id } }
        return ""
    }

    @Test func roundCounter_resetsWithEachUserMessage() async {
        responder.fallback = .events([call(UUID().uuidString, "list_tasks"), .completed(usage: nil)])
        let conversation = makeConversation()
        await conversation.send("Eins")
        responder.fallback = .events([.textDelta("ok"), .completed(usage: nil)])
        await conversation.send("Zwei")
        #expect(responder.inputs.count == 9)
        #expect(!conversation.roundLimitReached)
    }

    @Test func incompleteStream_marksErrorAndAllowsRetry() async {
        responder.enqueue(.cut([.textDelta("Halb"), call("c1", "create_task")]))
        responder.enqueue(.events([.textDelta("Ganz."), .completed(usage: nil)]))
        let conversation = makeConversation()

        await conversation.send("Hallo")
        #expect(conversation.state == .failed(.incomplete))
        #expect(conversation.history == [.user("Hallo")])
        #expect(conversation.pendingActions.isEmpty)
        #expect(conversation.streamingText.isEmpty)

        await conversation.retry()
        #expect(conversation.state == .idle)
        #expect(conversation.history == [.user("Hallo"), .assistant("Ganz.")])
        #expect(responder.inputs[1] == [.user("Hallo")])
    }

    @Test func modelSelectionFails_marksError() async {
        let conversation = Conversation(responder: responder, tools: handler, model: { throw ChatGPTError.notSignedIn },
                                        instructions: { "" }, history: [])
        await conversation.send("Hallo")
        #expect(conversation.state == .failed(.notSignedIn))
        #expect(responder.inputs.isEmpty)
    }

    @Test func historyBeyondForty_isTruncated_withNotice() async {
        var history: [InputItem] = []
        for index in 0..<30 {
            history.append(.user("Frage \(index)"))
            history.append(.assistant("Antwort \(index)"))
        }
        let short = makeConversation(history: Array(history.prefix(10)))
        #expect(!short.truncatedNotice)
        let conversation = makeConversation(history: history)

        await conversation.send("Neu")

        let sent = responder.inputs[0]
        #expect(sent.count <= Conversation.maxInputItems)
        #expect(sent.first.map { if case .user = $0 { true } else { false } } == true)
        #expect(sent.last == .user("Neu"))
        #expect(conversation.truncatedNotice)
        // The full history stays visible locally.
        #expect(conversation.history.count == 62)
    }

    @Test func truncation_keepsCallOutputPairs() {
        var history: [InputItem] = []
        for index in 0..<15 {
            history.append(.user("Frage \(index)"))
            history.append(.functionCall(callID: "c\(index)", name: "list_tasks", arguments: "{}"))
            history.append(.functionOutput(callID: "c\(index)", output: "[]"))
            history.append(.assistant("Antwort \(index)"))
        }
        let trimmed = Conversation.truncated(history)
        #expect(trimmed.count <= Conversation.maxInputItems)
        guard case .user = trimmed.first else {
            Issue.record("truncation must start at a user message")
            return
        }
        let calls = Set(trimmed.compactMap { if case .functionCall(let id, _, _) = $0 { id } else { nil } })
        let outputs = Set(trimmed.compactMap { if case .functionOutput(let id, _) = $0 { id } else { nil } })
        #expect(calls == outputs)
    }

    @Test func truncation_singleLongTurn_keepsFromLastUserMessage() {
        var history: [InputItem] = [.user("Alt"), .assistant("ok"), .user("Lang")]
        for index in 0..<30 {
            history.append(.functionCall(callID: "c\(index)", name: "list_tasks", arguments: "{}"))
            history.append(.functionOutput(callID: "c\(index)", output: "[]"))
        }
        let trimmed = Conversation.truncated(history)
        #expect(trimmed.first == .user("Lang"))
        #expect(trimmed.count == 61)
    }

    @Test func restore_withPendingCall_isClosed() async {
        let history: [InputItem] = [.user("Lege A an"), .functionCall(callID: "c1", name: "create_task", arguments: "{}")]
        let conversation = makeConversation(history: history)
        #expect(conversation.pendingActions.isEmpty)
        #expect(conversation.history.last == .functionOutput(callID: "c1", output: Conversation.interruptedOutput))
        #expect(responder.inputs.isEmpty)
    }

    @Test func longToolOutput_isClippedTo16KB_withNotice() async {
        handler.outputs["list_tasks"] = String(repeating: "ä", count: 20_000)
        responder.enqueue(.events([call("c1", "list_tasks"), .completed(usage: nil)]))
        let conversation = makeConversation()
        await conversation.send("Alles")
        let output = conversation.history.compactMap { if case .functionOutput(_, let text) = $0 { text } else { nil } }.first ?? ""
        #expect(output.utf8.count <= Conversation.maxOutputBytes + 100)
        #expect(output.hasSuffix(Conversation.clippedNotice))
    }

    @Test func send_whileStreaming_isIgnored() async {
        let gate = Gate()
        let slow = SlowResponder(gate: gate)
        let conversation = Conversation(responder: slow, tools: handler, model: { "gpt-test" },
                                        instructions: { "" }, history: [])
        let first = Task { await conversation.send("Eins") }
        while conversation.state != .streaming { await Task.yield() }
        await conversation.send("Zwei")
        gate.open()
        await first.value
        #expect(conversation.history == [.user("Eins"), .assistant("ok")])
        #expect(slow.callCount == 1)
    }

    @Test func decline_whileAnotherActionRuns_keepsRunningState() async throws {
        responder.enqueue(.events([call("w1", "create_task"), call("w2", "create_task"), .completed(usage: nil)]))
        let gate = Gate()
        let slowHandler = GatedToolHandler(gate: gate)
        let conversation = Conversation(responder: responder, tools: slowHandler, model: { "gpt-test" },
                                        instructions: { "" }, history: [])
        await conversation.send("Beides")
        let first = conversation.pendingActions[0], second = conversation.pendingActions[1]
        let confirming = Task { await conversation.confirm(first) }
        while conversation.state != .runningAction { await Task.yield() }
        await conversation.decline(second)
        #expect(conversation.state == .runningAction)
        #expect(responder.inputs.count == 1)
        gate.open()
        await confirming.value
        #expect(responder.inputs.count == 2)
        #expect(Conversation.openCallIDs(in: conversation.history).isEmpty)
    }

    @Test func clear_resetsEverything() async {
        responder.enqueue(.events([call("c1", "create_task"), .completed(usage: nil)]))
        let conversation = makeConversation()
        await conversation.send("Lege A an")
        conversation.clear()
        #expect(conversation.history.isEmpty)
        #expect(conversation.pendingActions.isEmpty)
        #expect(conversation.state == .idle)
    }
}

/// Streams "ok" once the gate opens and counts its calls.
final class SlowResponder: ResponseStreaming {
    let gate: Gate
    private let calls = Mutex(0)
    var callCount: Int { calls.withLock { $0 } }

    init(gate: Gate) { self.gate = gate }

    func respond(model: String, instructions: String, input: [InputItem], tools: [ToolDefinition],
                 jsonSchema: (name: String, schema: Data)?) -> AsyncThrowingStream<StreamEvent, Error> {
        calls.withLock { $0 += 1 }
        let gate = self.gate
        return AsyncThrowingStream { continuation in
            Task {
                await gate.wait()
                continuation.yield(.textDelta("ok"))
                continuation.yield(.completed(usage: nil))
                continuation.finish()
            }
        }
    }
}

/// A write tool that finishes only when the gate opens.
@MainActor
final class GatedToolHandler: ToolHandler {
    let gate: Gate
    init(gate: Gate) { self.gate = gate }
    var definitions: [ToolDefinition] { [] }
    func kind(of name: String) -> ToolKind { .write }
    func run(_ call: ToolCall) async -> String {
        await gate.wait()
        return #"{"ok":true}"#
    }
}

/// The stored form of a chat (issue #173, point 8): the history in memory stays complete, what is saved is reduced.
@MainActor
struct ConversationStoredFormTests {
    let responder = FakeResponder()
    let handler = FakeToolHandler()

    func makeConversation(history: [InputItem] = []) -> Conversation {
        Conversation(responder: responder, tools: handler, model: { "gpt-test" }, instructions: { "Kontext" }, history: history)
    }

    /// `list_tasks` keeps only a marker; the argument `secret` is dropped from every call.
    private func reducing() {
        handler.storedFormOverride = { call, output in
            guard call.name == "list_tasks" else { return nil }
            return (#"{"reduced":true}"#, output.map { _ in #"{"ok":true,"note":"gone"}"# })
        }
    }

    private func readTurn(_ conversation: Conversation) async {
        responder.enqueue(.events([call("c1", "list_tasks", #"{"secret":"x"}"#), .completed(usage: nil)]))
        responder.enqueue(.events([.textDelta("Zwei Aufgaben."), .completed(usage: nil)]))
        handler.outputs["list_tasks"] = #"{"text":"Notiztext"}"#
        await conversation.send("Was steht an?")
    }

    @Test func storableHistory_defaultEqualsHistory() async {
        let conversation = makeConversation()
        await readTurn(conversation)
        #expect(conversation.storableHistory == conversation.history)
    }

    @Test func storableHistory_usesStoredFormForCallAndOutput() async {
        reducing()
        let conversation = makeConversation()
        await readTurn(conversation)
        #expect(conversation.storableHistory == [
            .user("Was steht an?"),
            .functionCall(callID: "c1", name: "list_tasks", arguments: #"{"reduced":true}"#),
            .functionOutput(callID: "c1", output: #"{"ok":true,"note":"gone"}"#),
            .assistant("Zwei Aufgaben."),
        ])
        // The history in memory is untouched.
        #expect(conversation.history.contains(.functionOutput(callID: "c1", output: #"{"text":"Notiztext"}"#)))
    }

    @Test func storableHistory_keepsCallIDsAndOrder() async {
        reducing()
        let conversation = makeConversation()
        await readTurn(conversation)
        responder.enqueue(.events([call("c2", "list_tasks"), call("c3", "create_task", #"{"title":"A"}"#), .completed(usage: nil)]))
        await conversation.send("Noch mal")
        let kinds = conversation.storableHistory.map { item -> String in
            switch item {
            case .user: "user"
            case .assistant: "assistant"
            case .functionCall(let id, _, _): "call \(id)"
            case .functionOutput(let id, _): "output \(id)"
            default: "other"
            }
        }
        let original = conversation.history.map { item -> String in
            switch item {
            case .user: "user"
            case .assistant: "assistant"
            case .functionCall(let id, _, _): "call \(id)"
            case .functionOutput(let id, _): "output \(id)"
            default: "other"
            }
        }
        #expect(kinds == original)
    }

    @Test func storableHistory_openCall_passesNilOutput() async {
        var seen: [String?] = []
        handler.storedFormOverride = { call, output in
            if call.name == "create_task" { seen.append(output) }
            return nil
        }
        responder.enqueue(.events([call("c1", "create_task", #"{"title":"A"}"#), .completed(usage: nil)]))
        let conversation = makeConversation()
        await conversation.send("Lege A an")
        #expect(conversation.state == .waitingForConfirmation)
        _ = conversation.storableHistory
        #expect(seen == [nil])
    }

    @Test func history_keepsFullOutputAcrossTurns() async {
        reducing()
        let conversation = makeConversation()
        await readTurn(conversation)
        responder.enqueue(.events([.textDelta("Gern."), .completed(usage: nil)]))
        await conversation.send("Danke")
        let lastInput = responder.inputs.last ?? []
        #expect(lastInput.contains(.functionOutput(callID: "c1", output: #"{"text":"Notiztext"}"#)))
        #expect(lastInput.contains(.functionCall(callID: "c1", name: "list_tasks", arguments: #"{"secret":"x"}"#)))
    }

    @Test func reduceToStoredForm_replacesHistory() async {
        reducing()
        let conversation = makeConversation()
        await readTurn(conversation)
        conversation.reduceToStoredForm()
        #expect(conversation.history == conversation.storableHistory)
        #expect(!conversation.history.contains(.functionOutput(callID: "c1", output: #"{"text":"Notiztext"}"#)))
        responder.enqueue(.events([.textDelta("Gern."), .completed(usage: nil)]))
        await conversation.send("Danke")
        #expect(!(responder.inputs.last ?? []).contains(.functionOutput(callID: "c1", output: #"{"text":"Notiztext"}"#)))
    }

    @Test func reduceToStoredForm_whileBusy_doesNothing() async {
        reducing()
        let gate = Gate()
        let slow = SlowResponder(gate: gate)
        let conversation = Conversation(responder: slow, tools: handler, model: { "gpt-test" }, instructions: { "" },
                                        history: [.user("Alt"), .functionCall(callID: "c1", name: "list_tasks", arguments: "{}"),
                                                  .functionOutput(callID: "c1", output: #"{"text":"Notiztext"}"#)])
        let sending = Task { await conversation.send("Los") }
        while conversation.state != .streaming { await Task.yield() }
        let before = conversation.history
        conversation.reduceToStoredForm()
        #expect(conversation.history == before)
        gate.open()
        await sending.value
        conversation.reduceToStoredForm()
        #expect(!conversation.history.contains(.functionOutput(callID: "c1", output: #"{"text":"Notiztext"}"#)))
    }

    @Test func restoredFromStorableHistory_isValidInput() async {
        reducing()
        let conversation = makeConversation()
        await readTurn(conversation)
        let restored = makeConversation(history: conversation.storableHistory)
        #expect(Conversation.openCallIDs(in: restored.history).isEmpty)
        #expect(restored.pendingActions.isEmpty)
        #expect(restored.history == conversation.storableHistory)
    }

    @Test func messages_showActivityOnlyForOptedInReadTools() async {
        handler.activityTools = ["read_note"]
        responder.enqueue(.events([call("c1", "list_tasks"), call("c2", "read_note", #"{"note_ids":["note:1"]}"#), .completed(usage: nil)]))
        responder.enqueue(.events([.textDelta("Fertig."), .completed(usage: nil)]))
        handler.outputs["read_note"] = #"{"notes":[]}"#
        let conversation = makeConversation()
        await conversation.send("Lies")
        let activities = conversation.messages.compactMap { message -> String? in
            if case .activity(let call, let output) = message.content { return "\(call.name)|\(output ?? "nil")" }
            return nil
        }
        #expect(activities == [#"read_note|{"notes":[]}"#])
        #expect(conversation.messages.count == 3)   // user, activity, assistant
    }
}

