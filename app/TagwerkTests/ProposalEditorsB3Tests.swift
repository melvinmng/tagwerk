import AIKit
import Foundation
import GitHubKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The editors of shopping, comment and hand-over proposals (plan ki-vorschlaege-anpassen, task B3).
@MainActor
struct ProposalEditorsB3Tests {
    let directory = FakeGitHubDirectory.single()

    private func context(current: [String] = ["octo"], names: [String: String] = [:]) -> ProposalEditorContext {
        let directory = directory
        return ProposalEditorContext(calendar: testCalendar(), now: testNow, gitHubDirectory: { directory },
                                     shoppingItemName: { names[$0] },
                                     assignment: { $0 == "github:ISSUE_1" ? ProposalAssignment(repository: "beispiel/app", current: current) : nil })
    }

    private func call(_ name: String, _ json: String) -> ToolCall { ToolCall(id: "c1", name: name, arguments: Data(json.utf8)) }
    private func object(_ data: Data) throws -> [String: Any] { try #require(ProposalArguments.decode(data)) }

    // MARK: Shopping

    private let shopping = #"{"add":[{"name":"Milch","quantity":"2"},{"name":"Brot","quantity":null,"note":"x"}],"check_off":["item-1","item-2"]}"#

    @Test func shoppingEditor_untouched_roundTrips() throws {
        let editor = try #require(ShoppingProposalEditor(call: call("update_shopping", shopping), context: context()))
        #expect(NSDictionary(dictionary: try object(editor.arguments())).isEqual(to: try object(Data(shopping.utf8))))
    }

    @Test func shoppingEditor_renameAndQuantity() throws {
        let editor = try #require(ShoppingProposalEditor(call: call("update_shopping", shopping),
                                                         context: context(names: ["item-1": "Eier", "item-2": "Butter"])))
        #expect(editor.checkOffs.map(\.name) == ["Eier", "Butter"])

        editor.additions[0].name = "Hafermilch"
        editor.additions[0].quantity = "500 ml"
        editor.additions[1].quantity = ""
        editor.checkOffs[1].isOn = false
        let result = try object(editor.arguments())

        let add = try #require(result["add"] as? [[String: Any]])
        #expect(add.map { $0["name"] as? String } == ["Hafermilch", "Brot"])
        #expect(add[0]["quantity"] as? String == "500 ml")
        #expect(add[1]["quantity"] is NSNull)
        // Fields of the entry the editor does not know are kept.
        #expect(add[1]["note"] as? String == "x")
        #expect(result["check_off"] as? [String] == ["item-1"])
    }

    @Test func shoppingEditor_addAndRemoveRows_andLimit() throws {
        let editor = try #require(ShoppingProposalEditor(call: call("update_shopping", #"{"add":[{"name":"Milch","quantity":null}],"check_off":[]}"#), context: context()))
        editor.addItem()
        editor.additions[1].name = "  Käse "
        editor.additions[1].quantity = " 200 g "
        editor.removeAdditions(at: [0])
        let add = try #require(try object(editor.arguments())["add"] as? [[String: Any]])
        #expect(add.map { $0["name"] as? String } == ["Käse"])
        #expect(add.first?["quantity"] as? String == "200 g")

        for _ in 0..<40 { editor.addItem() }
        #expect(editor.additions.count == ShoppingProposalEditor.maximum)
    }

    @Test func shoppingEditor_needsSomethingToDo() throws {
        let editor = try #require(ShoppingProposalEditor(call: call("update_shopping", #"{"add":[{"name":"Milch","quantity":null}],"check_off":[]}"#), context: context()))
        #expect(editor.isValid)
        editor.additions[0].name = " "
        #expect(!editor.isValid)
    }

    // MARK: Comment

    @Test func commentEditor_text() throws {
        let editor = try #require(CommentProposalEditor(call: call("add_comment", #"{"id":"github:ISSUE_1","body":"Erledigt","extra":1}"#), context: context()))
        #expect(editor.isValid)
        #expect(try object(editor.arguments())["body"] as? String == "Erledigt")

        editor.body = "  Fast erledigt \n"
        let result = try object(editor.arguments())
        #expect(result["body"] as? String == "Fast erledigt")
        #expect(result["id"] as? String == "github:ISSUE_1")
        #expect(result["extra"] as? Int == 1)

        editor.body = " "
        #expect(!editor.isValid)
    }

    // MARK: Hand-over

    private let assign = #"{"id":"github:ISSUE_1","add":["lea-m"],"remove":["octo"]}"#

    @Test func assignEditor_changesPeople() async throws {
        let editor = try #require(AssignProposalEditor(call: call("assign_task", assign), context: context()))
        #expect(editor.selection == ["lea-m"])
        #expect(NSDictionary(dictionary: try object(editor.arguments())).isEqual(to: try object(Data(assign.utf8))))

        await editor.load()
        editor.choose(["octo", "jonas-k"])
        let result = try object(editor.arguments())
        #expect(result["add"] as? [String] == ["jonas-k"])
        #expect(result["remove"] as? [String] == [])
        #expect(result["id"] as? String == "github:ISSUE_1")
    }

    @Test func assignEditor_onlyAssignablePeople() async throws {
        let editor = try #require(AssignProposalEditor(call: call("assign_task", assign), context: context(current: ["octo", "old-timer"])))
        // Before the list loads: the people of the call and the people assigned now.
        #expect(Set(editor.candidates) == ["octo", "old-timer", "lea-m"])

        await editor.load()
        // Afterwards: the assignable people, plus the people assigned now (so they can be taken off).
        #expect(Set(editor.candidates) == ["octo", "lea-m", "jonas-k", "old-timer"])
        #expect(!editor.candidates.contains("ghost"))
        #expect(directory.assignableRequests == ["beispiel/app"])

        editor.choose(Set((1...11).map { "p\($0)" }))
        // More than ten people are refused.
        #expect(editor.selection == ["old-timer", "lea-m"])
    }

    @Test func assignEditor_unknownIssue_hasNoEditor() {
        let editor = AssignProposalEditor(call: call("assign_task", #"{"id":"github:GONE","add":["lea-m"],"remove":[]}"#), context: context())
        #expect(editor == nil)
    }

    @Test func registry_coversTheNewFunctions() {
        for name in ["update_shopping", "add_comment", "assign_task"] {
            #expect(AssistantModel.adjustableToolNames.contains(name), "\(name)")
        }
    }
}
