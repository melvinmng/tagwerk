import AIKit
import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// Adjusting and following up on the translation of shopping items (plan ki-vorschlaege-anpassen, task D5).
@MainActor
struct ShoppingTranslationFollowUpTests {
    let responder = FakePlanResponder()
    final class Counter { var models = 0; var consent = true }
    let counter = Counter()
    private let plan = ShoppingTranslationPlan(openItems: [
        ShoppingItem(id: "r1", name: "Äpfel", quantity: "6 Stück"),
        ShoppingItem(id: "r2", name: "Karotten", quantity: "1 kg"),
        ShoppingItem(id: "r3", name: "Milch 1,5%", quantity: nil),
    ])

    private func translator() -> ShoppingTranslator {
        let counter = self.counter
        return ShoppingTranslator(responder: responder, model: { counter.models += 1; return "gpt-test" }, hasConsent: { counter.consent })
    }

    private func answer(_ texts: [(Int, String)]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: ["items": texts.map { ["i": $0.0, "text": $0.1] }]), as: UTF8.self)
    }

    private func sent() throws -> [String: Any] {
        let text = responder.calls[0].input.compactMap { item -> String? in if case .user(let text) = item { text } else { nil } }.joined()
        return try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func firstChanges() throws -> [ShoppingTranslationPlan.Change] {
        try plan.changes(translations: [(0, "Apples"), (1, "Carrots"), (2, "Milk 1,5%")])
    }

    // MARK: Translator

    @Test func revise_requiresCurrentSortConsent() async throws {
        counter.consent = false
        let changes = try firstChanges()
        await #expect(throws: ShoppingTranslator.Failure.consentMissing) {
            _ = try await translator().revise(plan, to: .english, current: changes, pinned: [], focus: nil, comment: "Britisch")
        }
        #expect(counter.models == 0 && responder.calls.isEmpty)
    }

    @Test func revise_sendsNamesCurrentNamesAndMessage_butNoQuantity() async throws {
        responder.enqueue(answer([(0, "Apples"), (1, "Carrots"), (2, "Milk 1,5%")]))
        let changes = try firstChanges()

        _ = try await translator().revise(plan, to: .english, current: changes, pinned: ["r2"], focus: "r1", comment: "Britisches Englisch")

        let object = try sent()
        #expect(object["message"] as? String == "Britisches Englisch" && object["about"] as? Int == 0 && object["target"] as? String == "English")
        let current = try #require(object["current"] as? [[String: Any]])
        #expect(current.map { $0["text"] as? String } == ["Apples", "Carrots", "Milk 1,5%"])
        #expect(current.map { $0["fixed_by_user"] as? Bool } == [false, true, false])
        let everything = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        #expect(!everything.contains("Stück") && !everything.contains("kg") && !everything.contains("r1"), "no quantity and no identifier")
        #expect(responder.calls[0].schema == "shopping_translation" && responder.schemas[0] == ShoppingTranslator.schema)
        #expect(responder.instructions[0].hasPrefix(ShoppingTranslator.instructions) && responder.instructions[0].contains("fixed_by_user"))
    }

    @Test func revise_keepsQuantities_andChecksTheAnswerLikeTheFirstOne() async throws {
        responder.enqueue(answer([(0, "Apples"), (1, "Carrots"), (2, "Milk 3,5%")]))
        let revised = try await translator().revise(plan, to: .english, current: firstChanges(), pinned: [], focus: nil, comment: "Fett")
        // The digits of "Milch 1,5%" changed: that entry is dropped, the others keep their quantity.
        #expect(revised.map(\.itemID) == ["r1", "r2"] && revised.map(\.quantity) == ["6 Stück", "1 kg"])

        responder.enqueue(answer([(0, "Apples")]))
        await #expect(throws: ShoppingTranslator.Failure.mismatch) {
            _ = try await translator().revise(plan, to: .english, current: firstChanges(), pinned: [], focus: nil, comment: "x")
        }
    }

    // MARK: Draft

    private func draft(reviser: ShoppingTranslationDraft.Reviser? = nil, openNames: [String] = ["Äpfel", "Karotten", "Milch 1,5%"]) throws -> ShoppingTranslationDraft {
        ShoppingTranslationDraft(changes: try firstChanges(), plan: plan, language: .english,
                                 openKeys: Set(openNames.map(ShoppingName.key)), reviser: reviser)
    }

    @Test func row_editName_trimmedAndNotEmpty() throws {
        let draft = try draft()
        #expect(draft.rename("r1", to: "  Red apples "))
        #expect(draft.changes[0].newName == "Red apples" && draft.followUp.mark(of: "r1") == .byUser)
        #expect(!draft.rename("r1", to: "   "))
        #expect(!draft.rename("r1", to: "Two\nlines"))
        #expect(!draft.rename("r1", to: "Äpfel"))                       // the old name: no change
        #expect(!draft.rename("r1", to: String(repeating: "a", count: ShoppingInputParser.maxNameLength + 1)))
        #expect(!draft.rename("fehlt", to: "x"))
        #expect(draft.changes[0].newName == "Red apples")
    }

    @Test func row_editName_ontoAnotherOpenItem_blocksTheRow() throws {
        let draft = try draft()
        #expect(draft.rename("r1", to: "karotten"))
        #expect(draft.changes[0].blocked == .alreadyOnList && !draft.selected.contains { $0.id == "r1" })
        #expect(draft.rename("r2", to: "Red apples") && draft.rename("r1", to: "Red apples"))
        #expect(draft.changes[0].blocked == .sameTranslationTwice)
    }

    @Test func blockedRows_notEditable() async throws {
        // An answer that gives two items the same name blocks the second one; ChatGPT's block cannot be typed over.
        let blockedPlan = try plan.changes(translations: [(0, "Apples"), (1, "Apples"), (2, "Milk 1,5%")])
        #expect(blockedPlan[1].blocked == .sameTranslationTwice)
        let draft = ShoppingTranslationDraft(changes: blockedPlan, plan: plan, language: .english, openKeys: [], reviser: nil)
        #expect(!draft.rename("r2", to: "Carrots"))
        #expect(draft.selected.map(\.id) == ["r1", "r3"])
    }

    @Test func apply_renamesWithEditedNames_andRespectsCheckmarks() throws {
        let draft = try draft()
        draft.rename("r1", to: "Red apples")
        draft.toggle("r2")
        #expect(draft.selected.map(\.newName) == ["Red apples", "Milk 1,5%"])
    }

    @Test func revise_scopeRow_changesOnlyThatRow() async throws {
        var focusSeen: String?
        var changes = try firstChanges()
        changes[0].newName = "British apples"
        changes[1].newName = "Sweet carrots"
        let answer = changes
        let draft = try draft { _, _, _, _, focus, _ in focusSeen = focus; return answer }
        draft.followUp.focus = "r1"

        await draft.send("Britisch")

        #expect(focusSeen == "r1")
        #expect(draft.changes.map(\.newName) == ["British apples", "Carrots", "Milk 1,5%"])
        #expect(draft.followUp.mark(of: "r1") == .byAssistant && draft.followUp.mark(of: "r2") == nil)
    }

    @Test func revise_scopeAll_namesTypedRowsAsPinned_reportsOverwrittenOnes_andUndoes() async throws {
        var pinnedSeen: Set<String> = []
        var changes = try firstChanges()
        changes[0].newName = "British apples"
        let answer = changes
        let draft = try draft { _, _, _, pinned, _, _ in pinnedSeen = pinned; return answer }
        draft.rename("r1", to: "Red apples")

        await draft.send("Britisch")

        #expect(pinnedSeen == ["r1"] && draft.followUp.overwritten == ["r1"] && draft.changes[0].newName == "British apples")
        draft.followUp.undo()
        #expect(draft.changes[0].newName == "Red apples" && draft.followUp.mark(of: "r1") == .byUser)
    }

    @Test func revise_failure_keepsTheRows() async throws {
        let draft = try draft { _, _, _, _, _, _ in throw ShoppingTranslator.Failure.network }
        await draft.send("x")
        #expect(draft.followUp.state == .failed(ShoppingTranslator.Failure.network.message) && draft.changes.count == 3)
    }
}
