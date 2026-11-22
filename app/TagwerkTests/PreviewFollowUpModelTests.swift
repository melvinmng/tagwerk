import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// The state around the follow-up of a preview sheet (plan ki-vorschlaege-anpassen, strand D).
@MainActor
struct PreviewFollowUpModelTests {
    struct Row: Identifiable, Equatable, Sendable {
        let id: String
        var value: String
    }

    typealias Model = PreviewFollowUpModel<Row>

    private func model() -> Model {
        Model(items: [Row(id: "a", value: "Mehl"), Row(id: "b", value: "Zucker"), Row(id: "c", value: "Eier")])
    }

    private func answer(_ rows: [(String, String)], _ message: String = "Geändert.") -> Model.Reply {
        .init(items: rows.map { Row(id: $0.0, value: $0.1) }, message: message)
    }

    private func send(_ model: Model, _ comment: String = "Mehr", reply: @escaping @MainActor (Model.Request) async throws -> Model.Reply) async {
        await model.send(comment, using: reply, failure: { _ in "Fehler" })
    }

    @Test func scopeAll_replacesTheSet_andKeepsUserRowsInTheRequest() async {
        let model = model()
        model.edit(Row(id: "b", value: "Honig"))
        var seen: Model.Request?

        await send(model) { request in
            seen = request
            return answer([("a", "Dinkelmehl"), ("b", "Honig"), ("c", "Eier"), ("d", "Butter")])
        }

        #expect(seen?.scope == .all && seen?.pinned == ["b"] && seen?.comment == "Mehr")
        #expect(model.items.map(\.value) == ["Dinkelmehl", "Honig", "Eier", "Butter"])
        #expect(model.mark(of: "a") == .byAssistant && model.mark(of: "b") == .byUser && model.mark(of: "d") == .byAssistant)
        #expect(model.reply == "Geändert." && model.state == .ready && model.overwritten.isEmpty)
    }

    @Test func scopeOne_changesOnlyThatRow() async {
        let model = model()
        model.focus = "c"

        await send(model) { request in
            #expect(request.scope == .one("c"))
            return answer([("a", "Dinkelmehl"), ("c", "Eigelb")])
        }

        #expect(model.items.map(\.value) == ["Mehl", "Zucker", "Eigelb"])
        #expect(model.mark(of: "a") == nil && model.mark(of: "c") == .byAssistant)
    }

    @Test func overwrittenRows_areReported_andUndoBringsThemBack() async {
        let model = model()
        model.edit(Row(id: "a", value: "Roggenmehl"))

        await send(model) { _ in answer([("a", "Dinkelmehl"), ("b", "Zucker"), ("c", "Eier")]) }
        #expect(model.overwritten == ["a"] && model.canUndo)

        model.undo()
        #expect(model.items.first?.value == "Roggenmehl" && model.mark(of: "a") == .byUser)
        #expect(model.overwritten.isEmpty && model.reply.isEmpty && !model.canUndo)
    }

    @Test func aChangeByHand_dropsTheUndoStepAndTheSentence() async {
        let model = model()
        await send(model) { _ in answer([("a", "Dinkelmehl"), ("b", "Zucker"), ("c", "Eier")]) }
        #expect(model.canUndo)

        model.syncByHand([Row(id: "a", value: "Dinkelmehl"), Row(id: "c", value: "Eier")])

        #expect(!model.canUndo && model.reply.isEmpty)
        #expect(model.items.map(\.id) == ["a", "c"])
    }

    @Test func failure_keepsTheItems_andCanBeRetried() async {
        let model = model()
        let before = model.items
        await send(model, "Mehr") { _ in throw CocoaError(.fileReadUnknown) }
        #expect(model.state == .failed("Fehler") && model.items == before && model.lastMessage == "Mehr")

        await send(model, model.lastMessage) { _ in answer([("a", "Mehl"), ("b", "Zucker"), ("c", "Eier")], "Nichts zu ändern.") }
        #expect(model.state == .ready && model.reply == "Nichts zu ändern." && !model.canUndo)
    }

    @Test func discard_dropsALateAnswer() async {
        let model = model()
        let gate = Gate()
        let sending = Task { await send(model) { _ in
            await gate.wait()
            return answer([("a", "Dinkelmehl")])
        } }
        while !model.isSending { await Task.yield() }

        model.discard()
        gate.open()
        await sending.value

        #expect(model.items.first?.value == "Mehl" && model.state == .ready && model.reply.isEmpty)
    }

    @Test func onlyOneRequestAtATime_andEmptyMessagesSendNothing() async {
        let model = model()
        let gate = Gate()
        var requests = 0
        let first = Task { await send(model) { _ in
            requests += 1
            await gate.wait()
            return answer([("a", "Mehl"), ("b", "Zucker"), ("c", "Eier")])
        } }
        while !model.isSending { await Task.yield() }
        await send(model, "Noch eins") { _ in requests += 1; return answer([]) }
        gate.open()
        await first.value
        await send(model, "   ") { _ in requests += 1; return answer([]) }
        #expect(requests == 1)
    }

    @Test func replaceItems_startsOver() async {
        let model = model()
        model.edit(Row(id: "a", value: "Roggenmehl"))
        await send(model) { _ in answer([("a", "Dinkelmehl"), ("b", "Zucker"), ("c", "Eier")]) }
        model.focus = "b"

        model.replaceItems([Row(id: "x", value: "Neu")])

        #expect(model.items.map(\.id) == ["x"] && model.mark(of: "x") == nil && !model.canUndo)
        #expect(model.reply.isEmpty && model.focus == nil && model.scope == .all)
    }

    @Test func focusOnARowThatIsGone_meansAllRows() {
        let model = model()
        model.focus = "zzz"
        #expect(model.scope == .all)
    }
}
