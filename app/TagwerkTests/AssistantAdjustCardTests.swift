import AIKit
import Foundation
import GitHubKit
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// Action cards the user adjusts before confirming (plan ki-vorschlaege-anpassen, task A2).
@MainActor
struct AssistantAdjustCardTests {
    let container: ModelContainer
    let settings: AppSettings
    let calendarStore = FakeCalendarStore()
    let github = FakeTaskProvider(source: .github)
    let directory = FakeGitHubDirectory.single()
    let taskList: TaskListModel
    let responder = FakePlanResponder()
    let calendar = testCalendar()

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        github.viewerLogin = "octo"
        taskList = TaskListModel(providers: [github], now: testNow, calendar: calendar)
    }

    private func make() async -> (AssistantModel, ChatStore) {
        await taskList.reload()
        let planStore = PlanStore(context: container.mainContext)
        let blocks = BlockPlanner(store: calendarStore, planStore: planStore, links: EventLinkStore(context: container.mainContext),
                                  settings: settings, calendar: calendar)
        let planning = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: FakeAccessStore(),
                                     planStore: planStore, efforts: RecurringEffortStore(context: container.mainContext),
                                     blocks: blocks, settings: settings, marks: EventMarkStore(context: container.mainContext),
                                     now: testNow, calendar: calendar)
        await planning.reload()
        let directory = self.directory
        let tools = AppTools(taskList: taskList, planning: planning, planner: nil, events: { _ in [] }, gitHub: { directory })
        let store = ChatStore(context: container.mainContext)
        let model = AssistantModel(responder: responder, tools: tools, model: { "gpt-test" }, store: store,
                                   planning: planning, now: testNow)
        model.language = { .german }
        model.gitHubDirectory = { directory }
        model.adjustableTools = ["create_task", "update_task"]
        return (model, store)
    }

    /// Arguments of a `create_task` call for an issue; `assignees` is raw JSON.
    private func issueArguments(_ title: String = "Export", assignees: String = #"["octo"]"#, due: String = "null") -> Data {
        Data((#"{"title":"\#(title)","due":\#(due),"priority":null,"minutes":null,"notes":null,"source":"github","#
              + #""repository":"beispiel/app","project_ids":["PVT_1"],"assignees":\#(assignees)}"#).utf8)
    }

    private func pendingCards(_ model: AssistantModel, _ cards: [(id: String, name: String, arguments: Data)]) async {
        responder.enqueueEvents(cards.map { .functionCall(callID: $0.id, name: $0.name, arguments: String(decoding: $0.arguments, as: UTF8.self)) }
                                + [.completed(usage: nil)])
        await model.send("Leg das an")
    }

    // MARK: Buttons

    @Test func card_threeButtons_whenEditorExists() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        await pendingCards(model, [("c1", "create_task", issueArguments())])
        let call = try #require(model.conversation?.pendingActions.first)

        #expect(model.describe(call).canAdjust)
        #expect(model.canAdjust(call))
    }

    @Test func card_twoButtons_forToolsWithoutEditor() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        await pendingCards(model, [("c1", "complete_task", Data(#"{"id":"github:ISSUE_1"}"#.utf8))])
        let call = try #require(model.conversation?.pendingActions.first)

        #expect(!model.describe(call).canAdjust)
        #expect(model.adjust(call, arguments: Data(#"{"id":"github:ISSUE_2"}"#.utf8)) == nil)
        #expect(model.conversation?.isAdjusted(call) == false)
    }

    @Test func card_adjustableTools_followTheEditorRegistry() async throws {
        let (model, _) = await make()
        model.adjustableTools = AssistantModel.adjustableToolNames
        #expect(model.adjustableTools == ProposalEditors.toolNames)
        model.open(context: .tasks)
        await pendingCards(model, [("c1", "create_task", issueArguments()),
                                   ("c2", "complete_task", Data(#"{"id":"github:ISSUE_1"}"#.utf8))])
        let create = try #require(model.conversation?.pendingActions.first { $0.id == "c1" })
        let complete = try #require(model.conversation?.pendingActions.first { $0.id == "c2" })

        #expect(model.describe(create).canAdjust)
        #expect(!model.describe(complete).canAdjust)
    }

    @Test func card_noAdjust_onceItIsNotOpen() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        await pendingCards(model, [("c1", "create_task", issueArguments())])
        let call = try #require(model.conversation?.pendingActions.first)

        #expect(!model.describe(call, isOpen: false).canAdjust)
        responder.enqueue("Angelegt.")
        await model.confirm(call)
        #expect(!model.canAdjust(call))
        #expect(model.adjust(call, arguments: issueArguments("Anderes")) == nil)
    }

    // MARK: Mark and texts

    @Test func card_showsMarkAfterAdjust() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        await pendingCards(model, [("c1", "create_task", issueArguments())])
        let call = try #require(model.conversation?.pendingActions.first)
        #expect(model.describe(call).mark == nil)
        #expect(model.describe(call).proposedChange == nil)

        let adjusted = try #require(model.adjust(call, arguments: issueArguments("Export neu")))

        let card = model.describe(adjusted)
        #expect(card.mark == .byUser)
        #expect(card.title == "Export neu")
        // Back to the proposal: no mark any more.
        let reset = try #require(model.resetAdjustment(adjusted))
        #expect(model.describe(reset).mark == nil)
        #expect(model.describe(reset).title == "Export")
    }

    @Test func card_changeText_showsOldAndNew() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        await pendingCards(model, [("c1", "create_task", issueArguments(due: #""2026-11-27""#))])
        let call = try #require(model.conversation?.pendingActions.first)
        let before = model.describe(call).change

        let adjusted = try #require(model.adjust(call, arguments: issueArguments(due: #""2026-11-23""#)))

        let card = model.describe(adjusted)
        #expect(card.proposedChange == before)
        #expect(card.change != before)
    }

    @Test func spokenCard_namesAdjustment() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        await pendingCards(model, [("c1", "create_task", issueArguments()), ("c2", "create_task", issueArguments("Zweite"))])
        let call = try #require(model.conversation?.pendingActions.first)
        let untouched = try #require(model.conversation?.pendingActions.last)
        let adjusted = try #require(model.adjust(call, arguments: issueArguments("Export neu")))

        #expect(model.describe(adjusted, spoken: true).change.hasSuffix(". von dir angepasst"))
        #expect(model.describe(adjusted, language: .english, spoken: true).change.hasSuffix(". adjusted by you"))
        #expect(!model.describe(untouched, spoken: true).change.contains("angepasst"))
    }

    @Test func mark_labelsInBothLanguages() {
        #expect(ProposalMark.byUser.label() == "von dir angepasst")
        #expect(ProposalMark.byAssistant.label() == "von ChatGPT angepasst")
        #expect(ProposalMark.byUser.label(in: .english) == "adjusted by you")
        #expect(ProposalMark.byAssistant.label(in: .english) == "adjusted by ChatGPT")
    }

    // MARK: Confirmation

    @Test func adjust_thenConfirm_createsTheEditedIssue() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        await pendingCards(model, [("c1", "create_task", issueArguments())])
        let call = try #require(model.conversation?.pendingActions.first)
        let adjusted = try #require(model.adjust(call, arguments: issueArguments("Export neu")))

        responder.enqueue("Angelegt.")
        // A view may still hold the call as the model proposed it.
        await model.confirm(call)

        #expect(github.createdDrafts.map(\.title) == ["Export neu"])
        #expect(model.conversation?.pendingActions.isEmpty == true)
        let result = try output(of: "c1", in: model)
        #expect(model.conversation?.messages.contains { $0.content == .action(adjusted, .done(result)) } == true)
    }

    private func output(of id: String, in model: AssistantModel) throws -> String {
        try #require(model.conversation?.history.compactMap { item -> String? in
            if case .functionOutput(let callID, let output) = item, callID == id { output } else { nil }
        }.first)
    }

    @Test func adjust_doesNotSaveAnything() async throws {
        let (model, store) = await make()
        model.open(context: .tasks)
        await pendingCards(model, [("c1", "create_task", issueArguments())])
        let call = try #require(model.conversation?.pendingActions.first)
        let before = store.history(for: ChatStore.assistantKey)

        model.adjust(call, arguments: issueArguments("Export neu"))

        #expect(store.history(for: ChatStore.assistantKey) == before)
    }

    // MARK: Guards follow the adjusted values

    @Test func adjustedIssueForOthers_becomesSingleConfirmation() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        await pendingCards(model, [("c1", "create_task", issueArguments("Für mich")),
                                   ("c2", "create_task", issueArguments("Zweite"))])
        #expect(model.batchConfirmable.map(\.id) == ["c1", "c2"])
        let first = try #require(model.conversation?.pendingActions.first)

        let adjusted = try #require(model.adjust(first, arguments: issueArguments("Für Lea", assignees: #"["lea-m"]"#)))

        #expect(model.batchConfirmable.map(\.id) == ["c2"])
        #expect(model.openCards == OpenCards(ids: ["c1", "c2"], deletes: 0, guarded: 1))
        // The card names everyone the issue goes to, for the new values.
        #expect(model.describe(adjusted).change.contains("lea-m"))
        // Back to oneself: the card joins "Alle bestätigen" again.
        model.adjust(adjusted, arguments: issueArguments("Für mich"))
        #expect(model.batchConfirmable.map(\.id) == ["c1", "c2"])
    }

    @Test func confirmAll_includesAdjustedUnguardedCards() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        await pendingCards(model, [("c1", "create_task", issueArguments("Eins")),
                                   ("c2", "create_task", issueArguments("Zwei"))])
        let second = try #require(model.conversation?.pendingActions.last)
        model.adjust(second, arguments: issueArguments("Zwei geändert"))
        #expect(model.batchConfirmable.map(\.id) == ["c1", "c2"])

        responder.enqueue("Beide angelegt.")
        await model.confirmAll()

        #expect(github.createdDrafts.map(\.title) == ["Eins", "Zwei geändert"])
    }

    // MARK: Editor and sheet (task B1)

    @Test func adjust_withoutChanges_leavesCardUnmarked() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        await pendingCards(model, [("c1", "create_task", issueArguments(due: #""2026-11-27""#))])
        let call = try #require(model.conversation?.pendingActions.first)
        let editor = try #require(model.proposalEditor(for: call))

        // "Fertig" without a change: the editor writes the arguments in another key order, which is no adjustment.
        let adjusted = try #require(model.adjust(call, arguments: editor.arguments()))

        #expect(model.describe(adjusted).mark == nil)
        #expect(model.describe(adjusted).proposedChange == nil)
        #expect(model.conversation?.isAdjusted(adjusted) == false)
    }

    @Test func editor_opensWithTheAdjustedValues() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        await pendingCards(model, [("c1", "create_task", issueArguments("Export"))])
        let call = try #require(model.conversation?.pendingActions.first)
        let first = try #require(model.proposalEditor(for: call) as? TaskProposalEditor)
        first.title = "Export neu"
        model.adjust(call, arguments: first.arguments())

        // The view still holds the call as the model proposed it.
        let second = try #require(model.proposalEditor(for: call) as? TaskProposalEditor)
        #expect(second.title == "Export neu")
    }

    @Test func editor_missingForToolsWithoutOneAndForClosedCards() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        await pendingCards(model, [("c1", "complete_task", Data(#"{"id":"github:ISSUE_1"}"#.utf8)),
                                   ("c2", "create_task", issueArguments())])
        let complete = try #require(model.conversation?.pendingActions.first { $0.id == "c1" })
        let create = try #require(model.conversation?.pendingActions.first { $0.id == "c2" })
        #expect(model.proposalEditor(for: complete) == nil)
        #expect(model.proposalEditor(for: create) != nil)

        responder.enqueue("Ok.")
        await model.decline(create)
        #expect(model.proposalEditor(for: create) == nil)
    }

    @Test func adjust_thenConfirm_createsEditedTask() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        await pendingCards(model, [("c1", "create_task", issueArguments("Export"))])
        let call = try #require(model.conversation?.pendingActions.first)
        let editor = try #require(model.proposalEditor(for: call) as? TaskProposalEditor)
        editor.title = "Export für Montag"
        editor.due = ProposalDue(day: PlanDay(year: 2026, month: 11, day: 23), minutes: nil)
        let adjusted = try #require(model.adjust(call, arguments: editor.arguments()))
        #expect(model.describe(adjusted).mark == .byUser)

        responder.enqueue("Angelegt.")
        await model.confirm(adjusted)

        #expect(github.createdDrafts.map(\.title) == ["Export für Montag"])
        #expect(github.createdDrafts.first?.due == DueDate(year: 2026, month: 11, day: 23))
    }

    @Test func adjust_invalidCombination_showsToolErrorOnCard() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        await pendingCards(model, [("c1", "create_task", Data(#"{"title":"Lokal","due":null,"priority":null,"minutes":null,"notes":null,"source":"local","repository":null,"project_ids":null,"assignees":null}"#.utf8))])
        let call = try #require(model.conversation?.pendingActions.first)
        // A source this session does not have is refused by the tool with its known error; nothing is created.
        let invalid = Data(#"{"title":"Lokal","due":null,"priority":null,"minutes":null,"notes":null,"source":"local","repository":"beispiel/app","project_ids":null,"assignees":null}"#.utf8)
        let adjusted = try #require(model.adjust(call, arguments: invalid))

        responder.enqueue("Das ging nicht.")
        await model.confirm(adjusted)

        let result = try output(of: "c1", in: model)
        #expect(ActionCardView.error(in: result) != nil)
        #expect(github.createdDrafts.isEmpty)
    }

    @Test func resetToAssistant_restoresProposal() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        await pendingCards(model, [("c1", "create_task", issueArguments("Export"))])
        let call = try #require(model.conversation?.pendingActions.first)
        let editor = try #require(model.proposalEditor(for: call) as? TaskProposalEditor)
        editor.title = "Export neu"
        let adjusted = try #require(model.adjust(call, arguments: editor.arguments()))
        #expect(model.conversation?.isAdjusted(adjusted) == true)

        let reset = try #require(model.resetAdjustment(adjusted))

        #expect(model.describe(reset).mark == nil)
        #expect(model.describe(reset).title == "Export")
        #expect((try #require(model.proposalEditor(for: reset) as? TaskProposalEditor)).title == "Export")
    }

    @Test func rescheduleAndAssignToDay_cardsShowTheNewValues() async throws {
        let (model, _) = await make()
        model.adjustableTools = AssistantModel.adjustableToolNames
        model.open(context: .tasks)
        await pendingCards(model, [("c1", "reschedule_task", Data(#"{"id":"github:ISSUE_1","due":"2026-11-27"}"#.utf8)),
                                   ("c2", "assign_to_day", Data(#"{"id":"github:ISSUE_1","day":"2026-11-27"}"#.utf8))])
        let reschedule = try #require(model.conversation?.pendingActions.first { $0.id == "c1" })
        let assign = try #require(model.conversation?.pendingActions.first { $0.id == "c2" })
        let dueEditor = try #require(model.proposalEditor(for: reschedule) as? TaskProposalEditor)
        dueEditor.due = ProposalDue(day: PlanDay(year: 2026, month: 11, day: 30), minutes: nil)
        let dayEditor = try #require(model.proposalEditor(for: assign) as? TaskProposalEditor)
        dayEditor.day = PlanDay(year: 2026, month: 11, day: 30)

        let newReschedule = try #require(model.adjust(reschedule, arguments: dueEditor.arguments()))
        let newAssign = try #require(model.adjust(assign, arguments: dayEditor.arguments()))

        #expect(model.describe(newReschedule).mark == .byUser)
        #expect(model.describe(newReschedule).change != model.describe(newReschedule).proposedChange)
        #expect(model.describe(newAssign).change.contains("30"))
    }
}
