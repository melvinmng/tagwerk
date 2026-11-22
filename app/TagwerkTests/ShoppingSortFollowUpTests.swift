import AIKit
import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// Adjusting and following up on the proposal of "Mit ChatGPT sortieren" (plan ki-vorschlaege-anpassen, task D4).
@MainActor
struct ShoppingSortFollowUpTests {
    let responder = FakePlanResponder()
    final class Counter { var models = 0; var consent = true }
    let counter = Counter()

    private let request = ShoppingSorter.Request(itemNames: ["Feta", "Milch", "Brot"], categoryNames: ["Kühlregal", "Backwaren", "Sonstiges"])
    private let current = ["feta": "Sonstiges", "milch": "Sonstiges", "brot": "Sonstiges"]

    private func sorter() -> ShoppingSorter {
        let counter = self.counter
        return ShoppingSorter(responder: responder, model: { counter.models += 1; return "gpt-test" }, hasConsent: { counter.consent })
    }

    private func change(_ item: String, to category: String) -> ShoppingSorter.Change {
        ShoppingSorter.Change(itemName: item, fromCategory: "Sonstiges", toCategory: category)
    }

    private func answer(_ assignments: [(String, String)], new: [String] = []) -> String {
        let object: [String: Any] = ["assignments": assignments.map { ["item": $0.0, "category": $0.1] }, "new_categories": new]
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private func sentText() -> String {
        responder.calls[0].input.compactMap { item -> String? in if case .user(let text) = item { text } else { nil } }.joined()
    }

    private func proposal() -> ShoppingSorter.Proposal {
        ShoppingSorter.Proposal(newCategories: ["Molkerei"], changes: [change("Feta", to: "Molkerei"), change("Milch", to: "Kühlregal")])
    }

    // MARK: Sorter

    @Test func revise_requiresCurrentSortConsent() async {
        counter.consent = false
        await #expect(throws: ShoppingSorter.Failure.consentMissing) {
            _ = try await sorter().revise(request, current: current, proposal: proposal(), pinned: [], focus: nil, comment: "Gröber")
        }
        #expect(counter.models == 0 && responder.calls.isEmpty)
    }

    @Test func revise_sendsItemNamesCategoriesProposalAndComment() async throws {
        responder.enqueue(answer([("Feta", "Kühlregal")]))
        let pinnedID = proposal().changes[1].id

        _ = try await sorter().revise(request, current: current, proposal: proposal(), pinned: [pinnedID], focus: proposal().changes[0].id, comment: "Gröber einteilen")

        let sent = try #require(try JSONSerialization.jsonObject(with: Data(sentText().utf8)) as? [String: Any])
        #expect(sent["items"] as? [String] == ["Feta", "Milch", "Brot"] && sent["categories"] as? [String] == ["Kühlregal", "Backwaren", "Sonstiges"])
        #expect(sent["about"] as? String == "Feta" && sent["message"] as? String == "Gröber einteilen")
        let entries = try #require(sent["proposal"] as? [[String: Any]])
        #expect(entries.map { $0["item"] as? String } == ["Feta", "Milch"] && entries.map { $0["fixed_by_user"] as? Bool } == [false, true])
        // Only names: no quantity, no key besides these.
        #expect(Set(sent.keys) == ["items", "categories", "proposal", "new_categories", "about", "message"])
        #expect(responder.calls[0].schema == "shopping_sort" && responder.schemas[0] == ShoppingSorter.schema)
        #expect(responder.instructions[0].hasPrefix(ShoppingSorter.instructions) && responder.instructions[0].contains("fixed_by_user"))
    }

    @Test func revise_unknownItemsInAnswer_dropped() async throws {
        responder.enqueue(answer([("Feta", "Kühlregal"), ("Zauberbohne", "Kühlregal"), ("Milch", "Erfundene Kategorie")]))
        let revised = try await sorter().revise(request, current: current, proposal: proposal(), pinned: [], focus: nil, comment: "Gröber")
        #expect(revised.changes.map(\.itemName) == ["Feta"] && revised.changes[0].toCategory == "Kühlregal")
    }

    // MARK: Draft

    private func draft(reviser: ShoppingSortDraft.Reviser? = nil) -> ShoppingSortDraft {
        ShoppingSortDraft(proposal: proposal(), request: request, current: current, reviser: reviser)
    }

    @Test func row_pickCategory_existingOrProposedNew() {
        let draft = draft()
        let feta = draft.changes[0].id
        draft.pick("Backwaren", for: feta)
        #expect(draft.changes[0].toCategory == "Backwaren" && draft.followUp.mark(of: feta) == .byUser)
        draft.pick("Molkerei", for: feta)      // proposed new
        #expect(draft.changes[0].toCategory == "Molkerei")
        draft.pick("Erfunden", for: feta)      // neither: ignored
        #expect(draft.changes[0].toCategory == "Molkerei")
        #expect(draft.categoryChoices == ["Kühlregal", "Backwaren", "Sonstiges", "Molkerei"])
    }

    @Test func newCategory_onlyCreatedWhenStillUsed() {
        let draft = draft()
        #expect(draft.selection.newCategories == ["Molkerei"])
        draft.pick("Kühlregal", for: draft.changes[0].id)
        #expect(draft.newCategories.isEmpty && draft.selection.newCategories.isEmpty)
    }

    @Test func apply_usesEditedProposal_andRespectsCheckmarks() {
        let draft = draft()
        draft.pick("Backwaren", for: draft.changes[1].id)
        draft.toggleItem(draft.changes[0].id)
        let selection = draft.selection
        #expect(selection.changes.map(\.itemName) == ["Milch"] && selection.changes[0].toCategory == "Backwaren")
        // The new category of an unchecked change is not needed any more.
        #expect(selection.newCategories.isEmpty)
    }

    @Test func revise_scopeRow_changesOnlyThatRow() async {
        var focusSeen: String?
        let draft = draft { _, _, proposal, _, focus, _ in
            focusSeen = focus
            return ShoppingSorter.Proposal(newCategories: ["Molkerei"], changes: [
                ShoppingSorter.Change(itemName: "Feta", fromCategory: "Sonstiges", toCategory: "Kühlregal"),
                ShoppingSorter.Change(itemName: "Milch", fromCategory: "Sonstiges", toCategory: "Backwaren"),
                ShoppingSorter.Change(itemName: "Brot", fromCategory: "Sonstiges", toCategory: "Backwaren")])
        }
        draft.followUp.focus = draft.changes[0].id

        await draft.send("Feta ins Kühlregal")

        #expect(focusSeen == "feta")
        #expect(draft.changes.map(\.toCategory) == ["Kühlregal", "Kühlregal"] && draft.changes.count == 2)
        #expect(draft.followUp.mark(of: draft.changes[0].id) == .byAssistant && draft.followUp.mark(of: draft.changes[1].id) == nil)
    }

    @Test func revise_scopeAll_replacesTheProposal_reportsOverwrittenRows_andUndoes() async {
        var pinnedSeen: Set<String> = []
        let draft = draft { _, _, _, pinned, _, _ in
            pinnedSeen = pinned
            return ShoppingSorter.Proposal(newCategories: [], changes: [
                ShoppingSorter.Change(itemName: "Feta", fromCategory: "Sonstiges", toCategory: "Kühlregal")])
        }
        draft.pick("Backwaren", for: draft.changes[1].id)

        await draft.send("Keine neuen Kategorien")

        #expect(pinnedSeen == ["milch"])
        #expect(draft.changes.map(\.itemName) == ["Feta"] && draft.followUp.overwritten == ["milch"])
        #expect(draft.newCategories.isEmpty)
        draft.followUp.undo()
        #expect(draft.changes.map(\.toCategory) == ["Molkerei", "Backwaren"] && draft.newCategories == ["Molkerei"])
    }

    @Test func revise_failure_keepsTheProposal() async {
        let draft = draft { _, _, _, _, _, _ in throw ShoppingSorter.Failure.network }
        await draft.send("Gröber")
        #expect(draft.followUp.state == .failed(ShoppingSorter.Failure.network.message) && draft.changes.count == 2)
    }

    @Test func draft_withoutReviser_hasNoFollowUp() {
        #expect(!draft().hasFollowUp)
    }
}
