import AIKit
import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// The follow-up about the suggestions of a thoughts note (plan ki-vorschlaege-anpassen, task C2).
@MainActor
struct NoteSuggestionRevisionTests {
    let fixture: NoteSuggestionFixture

    init() async throws { fixture = try await NoteSuggestionFixture() }

    private let task = #"{"title":"Zahnarzt anrufen","due":"2026-11-27","priority":null,"minutes":null,"notes":null,"source":"local","repository":null,"project_ids":null,"assignees":null}"#
    private let other = #"{"title":"Export prüfen","due":null,"priority":null,"minutes":null,"notes":null,"source":"local","repository":null,"project_ids":null,"assignees":null}"#
    private let issue = #"{"title":"Export prüfen","due":null,"priority":null,"minutes":null,"notes":null,"source":"github","repository":"tagwerk","project_ids":null,"assignees":null}"#

    private func calls(_ entries: [(String, String)]) -> [(String, String)] { entries }

    private func revise(_ model: NoteSuggestionModel, _ record: NoteRecord, kind: NoteKind = .evening, _ comment: String = "Lieber Montag") async {
        await model.revise(noteID: record.id, text: record.text, kind: kind, comment: comment)
    }

    // MARK: Consent and private notes

    @Test func revise_privateKinds_sendNothing() async throws {
        let (model, record) = await fixture.fetched([("c1", "create_task", task)])
        for kind in [NoteKind.journal, .bibleStudy, .dream, .free] {
            await revise(model, record, kind: kind)
        }
        // The stored kind counts as well as the one the caller names.
        let journal = fixture.notes.create(text: "Geheim", kind: .journal, dayKey: "2026-11-18")!
        await model.revise(noteID: journal.id, text: journal.text, kind: .evening, comment: "Lieber Montag")
        #expect(fixture.responder.calls == 1)
        #expect(model.followUpState == .ready)
    }

    @Test func revise_withoutConsent_sendsNothing() async throws {
        let (model, record) = await fixture.fetched([("c1", "create_task", task)])
        fixture.flags.consent = false
        let models = fixture.flags.models
        await revise(model, record)
        #expect(fixture.responder.calls == 1 && fixture.flags.models == models)
        #expect(!model.cardFollowUpHasConsent)
    }

    @Test func revise_withoutOpenCards_sendsNothing() async throws {
        let (model, record) = await fixture.fetched([("c1", "create_task", task)])
        model.decline("c1")
        await revise(model, record)
        #expect(fixture.responder.calls == 1)
    }

    // MARK: Request

    @Test func revise_sendsNoteOpenCardsMarksAndComment() async throws {
        let (model, record) = await fixture.fetched([("c1", "create_task", task), ("c2", "create_task", other)])
        model.adjust(model.cards[0].call, arguments: Data(task.replacingOccurrences(of: "2026-11-27", with: "2026-11-30").utf8))
        fixture.responder.enqueue([])

        await revise(model, record, "Mach beides später")

        #expect(fixture.responder.calls == 2)
        let text = fixture.requestText(1)
        #expect(text.contains(record.text) && text.contains("Mach beides später"))
        #expect(text.contains("Current suggestions as JSON"))
        #expect(text.contains(#""function":"create_task""#) && text.contains("2026-11-30"))
        // The adjusted card is marked as fixed by the user, the other one is not.
        #expect(text.contains(#""fixed_by_user":true"#) && text.contains(#""fixed_by_user":false"#))
        let sent = fixture.responder.sent[1]
        #expect(sent.instructions.contains("fixed_by_user"))
        #expect(Set(sent.tools.map(\.name)) == Set(NoteSuggestionRules.allowedTools.subtracting(["create_task"]).union(["create_task"])))
    }

    @Test func revise_doneAndDeclinedCards_notSent() async throws {
        let (model, record) = await fixture.fetched([("c1", "create_task", task), ("c2", "create_task", other),
                                                     ("c3", "create_task", #"{"title":"Dritte Karte"}"#)])
        await model.confirm("c1")
        model.decline("c2")
        fixture.responder.enqueue([])

        await revise(model, record)

        let text = fixture.requestText(1)
        let suggestions = text.components(separatedBy: "Current suggestions as JSON:").last ?? ""
        #expect(suggestions.contains("Dritte Karte"))
        #expect(!suggestions.contains("Zahnarzt anrufen") && !suggestions.contains("Export prüfen"))
    }

    @Test func revise_issueTarget_isNotSentAndStaysOnTheCard() async throws {
        let directory = fixture.directory()
        let (model, record) = await fixture.fetched([("c1", "create_task", issue)], directory: directory)
        let target = model.cards[0].target
        #expect(target != nil)
        fixture.responder.enqueue([("n1", "create_task|" + issue.replacingOccurrences(of: "Export prüfen", with: "Export prüfen und melden"))],
                                  text: "Titel ergänzt.")

        await revise(model, record, "Titel ergänzen")

        let suggestions = fixture.requestText(1).components(separatedBy: "Current suggestions as JSON:").last ?? ""
        for name in ["melvinmng", "firma/app", "PVT_T", "tagwerk"] { #expect(!suggestions.contains(name), "\(name) was sent") }
        #expect(model.cards.count == 1)
        let card = model.cards[0]
        #expect(card.text.title == "Export prüfen und melden" && card.target == target && !card.needsTarget)
        #expect(fixture.arguments(of: card.call)["repository"] as? String == "melvinmng/tagwerk")
    }

    // MARK: Answer

    @Test func revise_answerReplacesOpenCardsOnly() async throws {
        let (model, record) = await fixture.fetched([("c1", "create_task", task), ("c2", "create_task", other),
                                                     ("c3", "create_task", #"{"title":"Dritte Karte"}"#)])
        await model.confirm("c1")
        fixture.responder.enqueue([("n2", "create_task|" + other.replacingOccurrences(of: "null,\"priority\"", with: "\"2026-12-01\",\"priority\"")),
                                   ("n3", "create_task|" + #"{"title":"Neue Karte"}"#)],
                                  text: "Export auf den 1. Dezember gelegt.")

        await revise(model, record)

        // The confirmed card stays in front, the open cards are the answer.
        #expect(model.cards.map(\.id) == ["c1", "n2", "n3"])
        #expect(model.cards[0].status != .pending)
        #expect(model.cards[1].mark == .byAssistant && model.cards[1].proposed?.id == "c2")
        #expect(model.cards[2].mark == .byAssistant && model.cards[2].proposed == nil)
        #expect(model.followUpReply == "Export auf den 1. Dezember gelegt.")
        #expect(model.followUpState == .ready && model.phase == .loaded)
        // Only the cards of the answer are open, nothing was run by the follow-up.
        #expect(fixture.tools.runs.count == 1)
    }

    @Test func revise_repeatedCard_keepsItsMark() async throws {
        let (model, record) = await fixture.fetched([("c1", "create_task", task), ("c2", "create_task", other)])
        let edited = Data(task.replacingOccurrences(of: "2026-11-27", with: "2026-11-30").utf8)
        model.adjust(model.cards[0].call, arguments: edited)
        let before = model.cards[0]
        fixture.responder.enqueue([("n1", "create_task|" + String(decoding: edited, as: UTF8.self)),
                                   ("n2", "create_task|" + other.replacingOccurrences(of: "Export prüfen", with: "Export melden"))])

        await revise(model, record)

        #expect(model.cards[0] == before && model.cards[0].mark == .byUser)
        #expect(model.cards[1].mark == .byAssistant)
    }

    @Test func revise_answerWithoutCalls_changesNothingAndShowsTheSentence() async throws {
        let (model, record) = await fixture.fetched([("c1", "create_task", task)])
        let before = model.cards
        fixture.responder.enqueue([], text: "Dafür müsste ich nachschlagen.")

        await revise(model, record)

        #expect(model.cards == before && !model.canUndoRevision)
        #expect(model.followUpReply == "Dafür müsste ich nachschlagen.")
    }

    @Test func revise_dropsIdsOutsideTheContext() async throws {
        let (model, record) = await fixture.fetched([("c1", "create_task", task)])
        fixture.responder.enqueue([("n1", "reschedule_task|" + #"{"id":"fremd","due":"2026-11-30"}"#)])
        await revise(model, record)
        // The only call named an unknown task: no card of the answer, so nothing is replaced by it.
        #expect(model.cards.map(\.id) == ["c1"])
    }

    // MARK: Undo

    @Test func undo_restoresPreviousCards() async throws {
        let (model, record) = await fixture.fetched([("c1", "create_task", task), ("c2", "create_task", other)])
        let before = model.cards
        fixture.responder.enqueue([("n1", "create_task|" + other)], text: "Nur noch eine.")
        await revise(model, record)
        // The answer repeats the second card unchanged: it is kept as it is, the first one is gone.
        #expect(model.cards.map(\.id) == ["c2"] && model.canUndoRevision)

        model.undoRevision()

        #expect(model.cards == before && !model.canUndoRevision && model.followUpReply.isEmpty)
    }

    @Test func undo_isDroppedByAnyChangeToACard() async throws {
        let (model, record) = await fixture.fetched([("c1", "create_task", task), ("c2", "create_task", other)])
        fixture.responder.enqueue([("n1", "create_task|" + task), ("n2", "create_task|" + #"{"title":"Neue Karte"}"#)])
        await revise(model, record)
        #expect(model.canUndoRevision)
        await model.confirm("c1")
        // Undoing would open the card that was confirmed in between again.
        #expect(!model.canUndoRevision)
    }

    // MARK: Errors and late answers

    @Test func revise_failure_keepsTheCards_andNeverNamesTheNote() async throws {
        let (model, record) = await fixture.fetched([("c1", "create_task", task)], directory: nil)
        let before = model.cards
        fixture.responder.fail(.network)

        await revise(model, record)

        guard case .failed(let message) = model.followUpState else { Issue.record("expected a failure"); return }
        #expect(!message.contains(record.text) && !message.contains("Zahnarzt"))
        #expect(model.cards == before)
        // The same message can be sent again.
        fixture.responder.clearFailure()
        fixture.responder.enqueue([])
        await revise(model, record, model.followUpLastMessage)
        #expect(model.followUpState == .ready)
    }

    @Test func revise_dropsLateAnswerAfterReset() async throws {
        let (model, record) = await fixture.fetched([("c1", "create_task", task)])
        let gate = Gate()
        fixture.responder.holdBack = { await gate.wait() }
        fixture.responder.enqueue([("n1", "create_task|" + other)])
        let revising = Task { await revise(model, record) }
        while fixture.responder.calls < 2 { await Task.yield() }
        #expect(model.isRevising)
        model.reset()
        gate.open()
        await revising.value
        #expect(model.cards.isEmpty && model.phase == .idle && model.followUpState == .ready)
    }

    @Test func whileRevising_cardsCannotBeConfirmedDeclinedOrAdjusted() async throws {
        let (model, record) = await fixture.fetched([("c1", "create_task", task)])
        let gate = Gate()
        fixture.responder.holdBack = { await gate.wait() }
        fixture.responder.enqueue([])
        let revising = Task { await revise(model, record) }
        while fixture.responder.calls < 2 { await Task.yield() }

        await model.confirm("c1")
        model.decline("c1")
        #expect(model.adjust(model.cards[0].call, arguments: Data(#"{"title":"X"}"#.utf8)) == nil)
        #expect(fixture.tools.runs.isEmpty && model.cards[0].status == .pending)
        gate.open()
        await revising.value
    }

    // MARK: One card

    private func cardAnswer(_ arguments: String, message: String = "Frist verschoben.", changed: Bool = true) -> String {
        #"{"arguments":\#(arguments),"message":"\#(message)","changed":\#(changed)}"#
    }

    @Test func singleCardFollowUp_usesCardReviser() async throws {
        let (model, record) = await fixture.fetched([("c1", "create_task", task), ("c2", "create_task", other)])
        let revised = task.replacingOccurrences(of: "2026-11-27", with: "2026-12-01")
        fixture.responder.enqueue(text: cardAnswer(revised))

        let answer = try await model.reviseCard(model.cards[0].call, current: Data(task.utf8), comment: "Lieber Dezember")

        #expect(answer.changed && fixture.arguments(of: ToolCall(id: "x", name: "create_task", arguments: answer.arguments))["due"] as? String == "2026-12-01")
        // One request about this card: no note text, no other card, the tools are none.
        let text = fixture.requestText(1)
        #expect(!text.contains(record.text) && !text.contains("Export prüfen") && text.contains("Lieber Dezember"))
        #expect(fixture.responder.sent[1].tools.isEmpty)
        // Nothing changed on the card until the sheet writes it back.
        #expect(model.cards[0].call.arguments == Data(task.utf8) || model.cards[0].mark == nil)
    }

    @Test func singleCardFollowUp_withoutConsent_orForAPrivateNote_sendsNothing() async throws {
        let (model, _) = await fixture.fetched([("c1", "create_task", task)])
        fixture.flags.consent = false
        await #expect(throws: CardReviser.Failure.consentMissing) {
            _ = try await model.reviseCard(model.cards[0].call, current: Data(task.utf8), comment: "Später")
        }
        #expect(fixture.responder.calls == 1)
    }

    @Test func singleCardFollowUp_issue_doesNotSendOrLoseTheTarget() async throws {
        let (model, _) = await fixture.fetched([("c1", "create_task", issue)], directory: fixture.directory())
        let current = model.cards[0].call.arguments
        var revisedArguments = fixture.arguments(of: model.cards[0].call)
        for key in ["repository", "project_ids", "assignees"] { revisedArguments[key] = NSNull() }
        revisedArguments["title"] = "Export prüfen und melden"
        fixture.responder.enqueue(text: cardAnswer(String(decoding: ProposalArguments.encode(revisedArguments), as: UTF8.self)))

        let answer = try await model.reviseCard(model.cards[0].call, current: current, comment: "Titel ergänzen")

        let text = fixture.requestText(1)
        for name in ["melvinmng", "PVT_T", "tagwerk"] { #expect(!text.contains(name), "\(name) was sent") }
        let arguments = fixture.arguments(of: ToolCall(id: "x", name: "create_task", arguments: answer.arguments))
        #expect(arguments["title"] as? String == "Export prüfen und melden")
        #expect(arguments["repository"] as? String == "melvinmng/tagwerk" && arguments["project_ids"] as? [String] == ["PVT_T"])
    }
}
