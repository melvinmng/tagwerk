import AIKit
import Foundation
import GitHubKit
import Testing
import TagwerkCore
@testable import Tagwerk

/// The editor of task proposals (plan ki-vorschlaege-anpassen, task B1): the arguments of a call go in, the user's
/// values come out, and everything the user did not touch stays as the model wrote it.
@MainActor
struct TaskProposalEditorTests {
    let directory = FakeGitHubDirectory.single()

    private func context(_ directory: FakeGitHubDirectory? = nil) -> ProposalEditorContext {
        let directory = directory ?? self.directory
        return ProposalEditorContext(calendar: testCalendar(), now: testNow, gitHubDirectory: { directory })
    }

    private func call(_ name: String, _ json: String) -> ToolCall {
        ToolCall(id: "c1", name: name, arguments: Data(json.utf8))
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(ProposalArguments.decode(data))
    }

    private func editor(_ name: String, _ json: String, directory: FakeGitHubDirectory? = nil) throws -> TaskProposalEditor {
        try #require(TaskProposalEditor(call: call(name, json), context: context(directory)))
    }

    private let localTask = #"{"title":"Zahnarzt anrufen","due":"2026-11-27","priority":"P3","minutes":30,"notes":"Kontrolltermin","source":"local","repository":null,"project_ids":null,"assignees":null,"extra":{"keep":1}}"#
    private let issue = #"{"title":"Export","due":null,"priority":null,"minutes":null,"notes":null,"source":"github","repository":"beispiel/app","project_ids":["PVT_1"],"assignees":["octo","lea-m"]}"#

    // MARK: Round trip

    @Test func taskEditor_roundTripsArguments() throws {
        let editor = try editor("create_task", localTask)

        let result = try object(editor.arguments())

        #expect(NSDictionary(dictionary: result).isEqual(to: try object(Data(localTask.utf8))))
        // The unknown field is kept.
        #expect((result["extra"] as? [String: Any])?["keep"] as? Int == 1)
    }

    @Test func taskEditor_untouchedUpdateFields_stayNull() throws {
        let json = #"{"id":"github:ISSUE_1","title":null,"notes":null,"due":"2026-11-30T09:15","priority":null,"minutes":null}"#
        let editor = try editor("update_task", json)

        editor.title = "Neuer Titel"
        let result = try object(editor.arguments())

        #expect(result["title"] as? String == "Neuer Titel")
        #expect(result["notes"] is NSNull)
        #expect(result["priority"] is NSNull)
        #expect(result["minutes"] is NSNull)
        // The due date with its time is not rewritten.
        #expect(result["due"] as? String == "2026-11-30T09:15")
        #expect(result["id"] as? String == "github:ISSUE_1")
    }

    @Test func dueWithTime_roundTripsAndChanges() throws {
        let editor = try editor("create_task", #"{"title":"A","due":"2026-11-30T09:15","source":"local"}"#)
        #expect(editor.due == ProposalDue(day: PlanDay(year: 2026, month: 11, day: 30), minutes: 9 * 60 + 15))

        editor.due = ProposalDue(day: PlanDay(year: 2026, month: 12, day: 1), minutes: 14 * 60)
        #expect(try object(editor.arguments())["due"] as? String == "2026-12-01T14:00")

        editor.due = ProposalDue(day: PlanDay(year: 2026, month: 12, day: 1), minutes: nil)
        #expect(try object(editor.arguments())["due"] as? String == "2026-12-01")

        editor.due = nil
        #expect(try object(editor.arguments())["due"] is NSNull)
    }

    @Test func editingOneField_changesOnlyThatField() throws {
        let editor = try editor("create_task", localTask)

        editor.notes = "  "
        editor.minutes = 45
        let result = try object(editor.arguments())

        #expect(result["notes"] is NSNull)
        #expect(result["minutes"] as? Int == 45)
        #expect(result["title"] as? String == "Zahnarzt anrufen")
        #expect(result["priority"] as? String == "P3")
        #expect(result["due"] as? String == "2026-11-27")
    }

    @Test func rescheduleEditor_date() throws {
        let editor = try editor("reschedule_task", #"{"id":"t1","due":"2026-11-27"}"#)
        #expect(editor.due?.day == PlanDay(year: 2026, month: 11, day: 27))

        editor.due = ProposalDue(day: PlanDay(year: 2026, month: 11, day: 23), minutes: nil)
        #expect(try object(editor.arguments())["due"] as? String == "2026-11-23")

        // For this function an empty due date removes the date: `null`, as the function documents.
        editor.due = nil
        #expect(try object(editor.arguments())["due"] is NSNull)
    }

    @Test func assignToDayEditor_day() throws {
        let editor = try editor("assign_to_day", #"{"id":"t1","day":"2026-11-27"}"#)
        #expect(try object(editor.arguments())["day"] as? String == "2026-11-27")

        editor.day = PlanDay(year: 2026, month: 11, day: 30)

        let result = try object(editor.arguments())
        #expect(result["day"] as? String == "2026-11-30")
        #expect(result["id"] as? String == "t1")
    }

    // MARK: Validity and offered values

    @Test func createEditor_needsATitle() throws {
        let editor = try editor("create_task", localTask)
        #expect(editor.isValid)
        editor.title = "   "
        #expect(!editor.isValid)
    }

    @Test func updateEditor_acceptsEmptyFields() throws {
        let editor = try editor("update_task", #"{"id":"t1","title":null,"notes":null,"due":null,"priority":null,"minutes":null}"#)
        #expect(editor.isValid)
    }

    @Test func taskEditor_onlyOffersValuesTheToolAccepts() throws {
        let reminder = try editor("create_task", #"{"title":"A","source":"reminders","priority":"P2"}"#)
        #expect(reminder.priorityChoices == [.p1, .p2, .p3, .p4])
        let local = try editor("create_task", #"{"title":"A","source":"local"}"#)
        #expect(local.priorityChoices.count == 6)
        #expect(local.priorityChoices.first == .some(nil))
        #expect(!(try editor("create_task", #"{"title":"A","source":"github","repository":"beispiel/app"}"#)).supportsDueTime)

        // Repositories and projects come from the stored catalog, like for the tool.
        let issueEditor = try editor("create_task", issue)
        let target = try #require(issueEditor.issueTarget)
        #expect(target.catalog.repositories == ["beispiel/app"])
        #expect(target.catalog.projects.map(\.id) == ["PVT_1"])
        #expect(target.repository == "beispiel/app")
    }

    @Test func registry_coversExactlyTheFunctionsWithAnEditor() throws {
        #expect(ProposalEditors.toolNames == AssistantModel.adjustableToolNames)
        var full = context()
        full.assignment = { _ in ProposalAssignment(repository: "beispiel/app", current: ["octo"]) }
        for name in ProposalEditors.toolNames {
            #expect(ProposalEditors.make(for: call(name, #"{"title":"A","id":"t1","day":"2026-11-27","body":"x"}"#), context: full) != nil, "\(name)")
        }
        #expect(ProposalEditors.make(for: call("complete_task", #"{"id":"t1"}"#), context: context()) == nil)
        #expect(ProposalEditors.make(for: call("delete_event", #"{"event_id":"e1"}"#), context: context()) == nil)
    }

    @Test func editor_rejectsArgumentsThatAreNoObject() {
        #expect(TaskProposalEditor(call: call("create_task", "[1]"), context: context()) == nil)
    }

    // MARK: Issues: repository, projects and people

    @Test func untouchedPeople_surviveWhileTheListHasNotLoaded() throws {
        let editor = try editor("create_task", issue)

        editor.title = "Export neu"
        let result = try object(editor.arguments())

        // Not loaded yet: the only candidate would be the user, but the people of the call stay.
        #expect(result["assignees"] as? [String] == ["octo", "lea-m"])
        #expect(result["repository"] as? String == "beispiel/app")
        #expect(result["project_ids"] as? [String] == ["PVT_1"])
        #expect(result["title"] as? String == "Export neu")
    }

    @Test func issueEditor_changingThePeople_writesThem() async throws {
        let editor = try editor("create_task", issue)
        await editor.load()
        let target = try #require(editor.issueTarget)

        target.choose(["jonas-k"])
        let result = try object(editor.arguments())

        #expect(result["assignees"] as? [String] == ["jonas-k"])
        #expect(directory.assignableRequests == ["beispiel/app"])
    }

    @Test func issueEditor_dropsPeopleNobodyCanAssign() async throws {
        let editor = try editor("create_task", issue.replacingOccurrences(of: #""octo","lea-m""#, with: #""octo","ghost""#))
        await editor.load()
        let target = try #require(editor.issueTarget)

        target.choose(target.assignees.union(["lea-m"]))

        // "ghost" is not assignable: only the people of the loaded list are written.
        #expect(try object(editor.arguments())["assignees"] as? [String] == ["octo", "lea-m"])
    }

    @Test func issueEditor_withoutPeople_keepsTheUserDefault() throws {
        let editor = try editor("create_task", issue.replacingOccurrences(of: #"["octo","lea-m"]"#, with: "null"))
        editor.title = "Export neu"

        #expect(try object(editor.arguments())["assignees"] is NSNull)
    }

    @Test func issueEditor_withoutCatalog_isLockedAndKeepsTheTarget() throws {
        let editor = try editor("create_task", issue, directory: FakeGitHubDirectory(catalog: nil))
        #expect(editor.issueTarget == nil)
        #expect(editor.targetLocked)
        #expect(editor.isValid)

        editor.title = "Export neu"
        let result = try object(editor.arguments())
        #expect(result["repository"] as? String == "beispiel/app")
        #expect(result["assignees"] as? [String] == ["octo", "lea-m"])
    }

    @Test func issueEditor_withoutRepository_isNotValid() throws {
        let editor = try editor("create_task", issue)
        editor.issueTarget?.repository = nil
        #expect(!editor.isValid)
    }
}
