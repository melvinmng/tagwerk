import Foundation
import Testing
@testable import AIKit

/// Revising all open cards with one message (plan ki-vorschlaege-anpassen, task B5).
@MainActor
struct ConversationReviseTests {
    let responder = FakeResponder()
    let handler = FakeToolHandler(writeTools: ["create_task", "create_note"])

    private func makeConversation(history: [InputItem] = []) -> Conversation {
        Conversation(responder: responder, tools: handler, model: { "gpt-test" }, instructions: { "Kontext" }, history: history)
    }

    /// Two open `create_task` cards, `c1` and `c2`.
    private func twoCards() async -> Conversation {
        responder.enqueue(.events([call("c1", "create_task", #"{"title":"A"}"#), call("c2", "create_task", #"{"title":"B"}"#),
                                   .completed(usage: nil)]))
        let conversation = makeConversation()
        await conversation.send("Leg A und B an")
        return conversation
    }

    private func output(_ id: String, in conversation: Conversation) throws -> String {
        try #require(conversation.history.compactMap { item -> String? in
            if case .functionOutput(let callID, let output) = item, callID == id { output } else { nil }
        }.first)
    }

    private func object(_ text: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    @Test func revise_closesOpenCallsWithCurrentArgumentsAndMarks() async throws {
        let conversation = await twoCards()
        let first = try #require(conversation.pendingActions.first)
        conversation.adjust(first, arguments: Data(#"{"title":"A neu"}"#.utf8))
        responder.enqueue(.events([.textDelta("Neu vorgelegt."), .completed(usage: nil)]))

        await conversation.revise(comment: "Alles eine Woche später")

        let adjusted = try object(try output("c1", in: conversation))
        #expect(adjusted["status"] as? String == "revision_requested")
        #expect((adjusted["current"] as? [String: Any])?["title"] as? String == "A neu")
        #expect(adjusted["adjusted_by_user"] as? Bool == true)
        let untouched = try object(try output("c2", in: conversation))
        #expect((untouched["current"] as? [String: Any])?["title"] as? String == "B")
        #expect(untouched["adjusted_by_user"] as? Bool == false)
        // The message follows the outputs and goes out with the whole set; nothing ran.
        #expect(conversation.history.contains(.user("Alles eine Woche später")))
        #expect(handler.ran.isEmpty)
        #expect(conversation.pendingActions.isEmpty)
        let sent = try #require(responder.inputs.last)
        #expect(sent.last == .user("Alles eine Woche später"))
    }

    @Test func revise_outputIsNotTheDeclinedOutput() async throws {
        let conversation = await twoCards()
        responder.enqueue(.events([.textDelta("ok"), .completed(usage: nil)]))

        await conversation.revise(comment: "Später")

        for id in ["c1", "c2"] {
            #expect(try output(id, in: conversation) != Conversation.declinedOutput)
        }
    }

    @Test func oldCards_showRevisedStatus() async throws {
        let conversation = await twoCards()
        responder.enqueue(.events([call("c3", "create_task", #"{"title":"A später"}"#), .completed(usage: nil)]))

        await conversation.revise(comment: "Später")

        let statuses = conversation.messages.compactMap { message -> (String, ChatMessage.ActionStatus)? in
            if case .action(let call, let status) = message.content { (call.id, status) } else { nil }
        }
        #expect(statuses.map(\.0) == ["c1", "c2", "c3"])
        #expect(statuses.map(\.1) == [.revised, .revised, .pending])
        #expect(conversation.pendingActions.map(\.id) == ["c3"])
    }

    @Test func send_withoutScope_behavesAsToday() async throws {
        let conversation = await twoCards()
        responder.enqueue(.events([.textDelta("ok"), .completed(usage: nil)]))

        await conversation.send("Doch nicht")

        #expect(try output("c1", in: conversation) == Conversation.declinedOutput)
        #expect(try output("c2", in: conversation) == Conversation.declinedOutput)
        #expect(conversation.messages.compactMap { message -> ChatMessage.ActionStatus? in
            if case .action(_, let status) = message.content { status } else { nil }
        } == [.declined, .declined])
    }

    @Test func revise_whileBusyOrWithoutCards_isLikeSend() async throws {
        let conversation = makeConversation()
        responder.enqueue(.events([.textDelta("Antwort"), .completed(usage: nil)]))

        await conversation.revise(comment: "Hallo")

        #expect(conversation.history == [.user("Hallo"), .assistant("Antwort")])
    }

    @Test func revise_roundLimitStillApplies() async throws {
        let conversation = await twoCards()
        responder.fallback = .events([call(UUID().uuidString, "list_tasks"), .completed(usage: nil)])

        await conversation.revise(comment: "Endlosschleife")

        #expect(conversation.roundLimitReached)
        #expect(Conversation.openCallIDs(in: conversation.history).isEmpty)
        // The revision itself used one round budget of its own: 8 rounds, not 8 plus the first send.
        #expect(responder.inputs.count == 1 + 8)
    }

    @Test func storedHistory_keepsRevisionOutputs_withoutNoteText() async throws {
        handler.storedFormOverride = { call, output in
            call.name == "create_note" ? (#"{"title":"Kurz","text":"[gekürzt]"}"#, output) : nil
        }
        responder.enqueue(.events([call("n1", "create_note", #"{"title":"Kurz","text":"GEHEIMER VOLLTEXT"}"#),
                                   call("c1", "create_task", #"{"title":"A"}"#), .completed(usage: nil)]))
        let conversation = makeConversation()
        await conversation.send("Notiz und Aufgabe")
        responder.enqueue(.events([.textDelta("ok"), .completed(usage: nil)]))

        await conversation.revise(comment: "Anders")

        // Live, the model gets the full arguments: a note text shortened for storage would be proposed again as it is.
        let note = try output("n1", in: conversation)
        #expect(note.contains("GEHEIMER VOLLTEXT"))
        #expect(!note.contains("[gekürzt]"))
        // Stored, the revision output carries the stored form of the call and no note text.
        let stored = conversation.storableHistory
        let storedNote = try #require(stored.compactMap { item -> String? in
            if case .functionOutput("n1", let output) = item { output } else { nil }
        }.first)
        #expect(!storedNote.contains("GEHEIMER VOLLTEXT"))
        #expect(storedNote.contains("[gekürzt]"))
        #expect(storedNote.contains("revision_requested"))
        // The task card has nothing to reduce and keeps its output.
        #expect(stored.contains(.functionOutput(callID: "c1", output: try output("c1", in: conversation))))
        #expect(!stored.contains { item in
            switch item {
            case .functionCall(_, _, let arguments): arguments.contains("GEHEIMER VOLLTEXT")
            case .functionOutput(_, let output): output.contains("GEHEIMER VOLLTEXT")
            default: false
            }
        })
        // `history` itself still holds the full text (the stored form is made only for saving).
        #expect(conversation.history.contains { if case .functionOutput("n1", let o) = $0 { o.contains("GEHEIMER VOLLTEXT") } else { false } })
    }
}
