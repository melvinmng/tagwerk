import AIKit
import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// "Anpassen" on the cards of a thoughts note (plan ki-vorschlaege-anpassen, task C1).
@MainActor
struct NoteSuggestionAdjustTests {
    let fixture: NoteSuggestionFixture

    init() async throws { fixture = try await NoteSuggestionFixture() }

    private let task = #"{"title":"Zahnarzt anrufen","due":"2026-11-27","priority":null,"minutes":null,"notes":null,"source":"local","repository":null,"project_ids":null,"assignees":null}"#
    private let issue = #"{"title":"Export prüfen","due":null,"priority":null,"minutes":null,"notes":null,"source":"github","repository":"tagwerk","project_ids":null,"assignees":null}"#

    private func edited(_ json: String, _ replacements: [String: String]) -> Data {
        var text = json
        for (old, new) in replacements { text = text.replacingOccurrences(of: old, with: new) }
        return Data(text.utf8)
    }

    // MARK: Rewriting a call

    @Test func adjust_rewritesCallLikeSetTarget() async throws {
        let (model, _) = await fixture.fetched([("c1", "create_task", task), ("c2", "create_task", #"{"title":"Andere"}"#)])
        let proposed = model.cards[0].call
        let data = edited(task, ["Zahnarzt anrufen": "Zahnarzt Dr. Weber anrufen"])

        let adjusted = try #require(model.adjust(proposed, arguments: data))

        #expect(adjusted.id == "c1" && adjusted.name == "create_task")
        let card = model.cards[0]
        #expect(card.call == adjusted && fixture.arguments(of: card.call)["title"] as? String == "Zahnarzt Dr. Weber anrufen")
        #expect(card.text.title == "Zahnarzt Dr. Weber anrufen")
        #expect(card.mark == .byUser && card.text.mark == .byUser)
        #expect(card.proposed == proposed && model.isAdjusted(adjusted))
        #expect(card.status == .pending)
        // The other card stays as it was.
        #expect(model.cards[1].mark == nil && model.cards[1].proposed == nil)
    }

    @Test func adjust_showsOldAndNewInTheCardText() async throws {
        let (model, _) = await fixture.fetched([("c1", "create_task", task)])
        let call = model.cards[0].call
        model.adjust(call, arguments: edited(task, ["2026-11-27": "2026-11-30"]))
        let text = model.cards[0].text
        #expect(text.proposedChange != nil && text.proposedChange != text.change)
    }

    @Test func adjust_assistantMark_isKept() async throws {
        let (model, _) = await fixture.fetched([("c1", "create_task", task)])
        model.adjust(model.cards[0].call, arguments: edited(task, ["Zahnarzt anrufen": "Zahnarzt"]), mark: .byAssistant)
        #expect(model.cards[0].mark == .byAssistant && model.cards[0].text.mark == .byAssistant)
    }

    @Test func adjust_backToTheProposal_isNoAdjustment() async throws {
        let (model, _) = await fixture.fetched([("c1", "create_task", task)])
        let call = model.cards[0].call
        model.adjust(call, arguments: edited(task, ["Zahnarzt anrufen": "Zahnarzt"]))
        model.adjust(call, arguments: call.arguments)
        #expect(model.cards[0].mark == nil && model.cards[0].proposed == nil && !model.isAdjusted(call))
    }

    @Test func adjust_ignoresDoneDeclinedAndUnknownCards() async throws {
        let (model, _) = await fixture.fetched([("c1", "create_task", task), ("c2", "create_task", #"{"title":"B"}"#)])
        await model.confirm("c1")
        model.decline("c2")
        let before = model.cards
        #expect(model.adjust(before[0].call, arguments: Data(#"{"title":"X"}"#.utf8)) == nil)
        #expect(model.adjust(before[1].call, arguments: Data(#"{"title":"X"}"#.utf8)) == nil)
        #expect(model.adjust(ToolCall(id: "fehlt", name: "create_task", arguments: Data("{}".utf8)), arguments: Data("{}".utf8)) == nil)
        #expect(model.cards == before)
    }

    @Test func adjust_argumentsThatAreNoObject_changeNothing() async throws {
        let (model, _) = await fixture.fetched([("c1", "create_task", task)])
        let before = model.cards
        #expect(model.adjust(before[0].call, arguments: Data("[1]".utf8)) == nil)
        #expect(model.cards == before)
    }

    // MARK: Issue cards

    @Test func adjust_keepsResolvedIssueTarget() async throws {
        let (model, _) = await fixture.fetched([("c1", "create_task", issue)], directory: fixture.directory())
        let target = AppTools.GitHubTarget(repository: "melvinmng/tagwerk", projectIDs: ["PVT_T"])
        #expect(model.cards[0].target == target)

        // The editor writes the resolved repository back; a changed title keeps the target.
        let resolved = fixture.arguments(of: model.cards[0].call)
        var arguments = resolved
        arguments["title"] = "Export prüfen und melden"
        model.adjust(model.cards[0].call, arguments: ProposalArguments.encode(arguments))
        #expect(model.cards[0].target == target && !model.cards[0].needsTarget)
        #expect(model.cards[0].isIssue)

        // A repository the user chose in the sheet is resolved against the catalog.
        arguments["repository"] = "melvinmng/app"
        arguments["project_ids"] = [String]()
        model.adjust(model.cards[0].call, arguments: ProposalArguments.encode(arguments))
        #expect(model.cards[0].target == AppTools.GitHubTarget(repository: "melvinmng/app", projectIDs: []))

        // Without a repository the card waits for a target again.
        arguments["repository"] = NSNull()
        model.adjust(model.cards[0].call, arguments: ProposalArguments.encode(arguments))
        #expect(model.cards[0].needsTarget)
    }

    @Test func adjust_issueForOthers_leavesBatch() async throws {
        let (model, _) = await fixture.fetched([("c1", "create_task", task), ("c2", "create_task", issue)], directory: fixture.directory())
        #expect(model.confirmableCount == 2 && !model.hasSingleConfirmationCards)

        var arguments = fixture.arguments(of: model.cards[1].call)
        arguments["assignees"] = ["lea-m"]
        model.adjust(model.cards[1].call, arguments: ProposalArguments.encode(arguments))

        #expect(model.confirmableCount == 1 && model.hasSingleConfirmationCards)
        await model.confirmAll()
        #expect(fixture.tools.runs.map(\.id) == ["c1"])
        #expect(model.cards[1].status == .pending)
        #expect(model.cards[1].text.change.contains("lea-m"))
    }

    // MARK: Confirming and resetting

    @Test func adjustedCard_confirmRunsEditedCall() async throws {
        let (model, _) = await fixture.fetched([("c1", "create_task", task)])
        model.adjust(model.cards[0].call, arguments: edited(task, ["Zahnarzt anrufen": "Zahnarzt Dr. Weber anrufen"]))

        await model.confirm("c1")

        #expect(fixture.tools.runs.count == 1)
        #expect(fixture.arguments(of: fixture.tools.runs[0])["title"] as? String == "Zahnarzt Dr. Weber anrufen")
        #expect(fixture.responder.calls == 1)      // only the request for the suggestions
    }

    @Test func resetAdjustment_putsTheProposalBack() async throws {
        let (model, _) = await fixture.fetched([("c1", "create_task", task)])
        let proposed = model.cards[0].call
        model.adjust(proposed, arguments: edited(task, ["Zahnarzt anrufen": "Zahnarzt"]))

        let restored = model.resetAdjustment(proposed)

        #expect(restored == proposed && model.cards[0].call == proposed)
        #expect(model.cards[0].mark == nil && model.cards[0].proposed == nil && model.cards[0].text.mark == nil)
        #expect(model.resetAdjustment(proposed) == nil)       // not adjusted any more
    }

    @Test func reset_dropsAdjustments() async throws {
        let (model, _) = await fixture.fetched([("c1", "create_task", task)])
        model.adjust(model.cards[0].call, arguments: edited(task, ["Zahnarzt anrufen": "Zahnarzt"]))
        model.reset()
        #expect(model.cards.isEmpty && model.phase == .idle)
    }

    // MARK: Editors

    @Test func card_offersAdjustWithAnEditor_andNotWithout() async throws {
        let (withEditors, _) = await fixture.fetched([("c1", "create_task", task)])
        #expect(withEditors.cards[0].text.canAdjust)
        #expect(withEditors.proposalEditor(for: withEditors.cards[0].call) != nil)

        let (without, _) = await fixture.fetched([("c1", "create_task", task)], withEditors: false)
        #expect(!without.cards[0].text.canAdjust)
        #expect(without.proposalEditor(for: without.cards[0].call) == nil)
    }

    @Test func editor_isOnlyOfferedForOpenCards() async throws {
        let (model, _) = await fixture.fetched([("c1", "create_task", task)])
        let call = model.cards[0].call
        await model.confirm("c1")
        #expect(model.proposalEditor(for: call) == nil && model.proposalEditor(for: call, arguments: call.arguments) == nil)
    }

    @Test func editor_roundTripsTheCardAndWritesBack() async throws {
        let (model, _) = await fixture.fetched([("c1", "create_task", task)])
        let call = model.cards[0].call
        let editor = try #require(model.proposalEditor(for: call))
        // An editor that is not changed writes the arguments of the card back unchanged: no adjustment.
        model.adjust(call, arguments: editor.arguments())
        #expect(model.cards[0].mark == nil && model.cards[0].proposed == nil)
    }
}
