import AIKit
import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// "Alle anpassen …": the open cards go back to ChatGPT with their state (plan ki-vorschlaege-anpassen, task B5, AN5a).
@MainActor
struct AssistantReviseAllTests {
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
        let model = AssistantModel(responder: responder, tools: tools, model: { "gpt-test" }, store: store, planning: planning, now: testNow)
        model.language = { .german }
        model.gitHubDirectory = { directory }
        return (model, store)
    }

    private func task(_ title: String, assignees: String = "null") -> String {
        #"{"title":"\#(title)","due":"2026-11-27","priority":null,"minutes":null,"notes":null,"source":"local","repository":null,"project_ids":null,"assignees":\#(assignees)}"#
    }

    private func propose(_ model: AssistantModel, _ cards: [(String, String, String)]) async {
        responder.enqueueEvents(cards.map { .functionCall(callID: $0.0, name: $0.1, arguments: $0.2) } + [.completed(usage: nil)])
        await model.send("Leg das an")
    }

    private func output(_ id: String, in model: AssistantModel) throws -> String {
        try #require(model.conversation?.history.compactMap { item -> String? in
            if case .functionOutput(let callID, let output) = item, callID == id { output } else { nil }
        }.first)
    }

    @Test func send_withoutTheChip_stillRejectsTheOpenCards() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        await propose(model, [("c1", "create_task", task("A"))])
        responder.enqueue("Ok.")

        await model.send("Doch nicht")

        #expect(try output("c1", in: model) == Conversation.declinedOutput)
    }

    @Test func revise_withTheChip_sendsTheStateAndResetsTheChip() async throws {
        let (model, store) = await make()
        model.open(context: .tasks)
        model.adjustableTools = AssistantModel.adjustableToolNames
        await propose(model, [("c1", "create_task", task("A")), ("c2", "create_task", task("B"))])
        let first = try #require(model.conversation?.pendingActions.first)
        model.adjust(first, arguments: Data(task("A neu").utf8))
        responder.enqueue("Neu vorgelegt.")

        model.composesRevision = true
        await model.send("Alles eine Woche später")

        #expect(!model.composesRevision)
        let adjusted = try output("c1", in: model)
        #expect(adjusted.contains("revision_requested") && adjusted.contains("A neu") && adjusted.contains(#""adjusted_by_user":true"#))
        #expect(try output("c2", in: model).contains(#""adjusted_by_user":false"#))
        // The old cards show as revised and the answer is part of the stored chat.
        let statuses = model.conversation?.messages.compactMap { message -> ChatMessage.ActionStatus? in
            if case .action(_, let status) = message.content { status } else { nil }
        }
        #expect(statuses == [.revised, .revised])
        #expect(store.history(for: ChatStore.assistantKey).contains(.user("Alles eine Woche später")))
    }

    @Test func revise_guardedCardsStayGuardedInTheNewSet() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        await propose(model, [("c1", "create_task", task("A"))])
        // The revised set contains an issue for someone else: a guarded card again.
        let issue = #"{"title":"Export","due":null,"priority":null,"minutes":null,"notes":null,"source":"github","repository":"beispiel/app","project_ids":["PVT_1"],"assignees":["lea-m"]}"#
        responder.enqueueEvents([.functionCall(callID: "c2", name: "create_task", arguments: issue), .completed(usage: nil)])

        model.composesRevision = true
        await model.send("Gib das Lea")

        #expect(model.conversation?.pendingActions.map(\.id) == ["c2"])
        #expect(model.batchConfirmable.isEmpty)
        #expect(model.openCards.guarded == 1)
    }

    @Test func voiceMode_spokenChange_usesRevise() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        await propose(model, [("c1", "create_task", task("A"))])
        model.onTurnFinished = { _ in }
        responder.enqueue("Ok.")

        await model.send("Lieber nächste Woche", spoken: true)

        #expect(try output("c1", in: model).contains("revision_requested"))
    }

    @Test func dictationInTheTextChat_stillRejectsTheOpenCards() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        await propose(model, [("c1", "create_task", task("A"))])
        responder.enqueue("Ok.")

        // Spoken, but not in the voice mode (the microphone of the input line): as before.
        await model.send("Doch nicht", spoken: true)

        #expect(try output("c1", in: model) == Conversation.declinedOutput)
    }

    @Test func voiceMode_offersNoSheet() async throws {
        let (model, _) = await make()
        model.adjustableTools = AssistantModel.adjustableToolNames
        model.open(context: .tasks)
        await propose(model, [("c1", "create_task", task("A"))])
        let call = try #require(model.conversation?.pendingActions.first)
        #expect(model.describe(call).canAdjust)

        model.onTurnFinished = { _ in }

        #expect(!model.describe(call).canAdjust)
    }

    @Test func instructions_explainRevisionOutput() async {
        let (model, _) = await make()
        let text = model.instructions()
        #expect(text.contains("revision_requested"))
        #expect(text.contains("adjusted_by_user"))
        #expect(text.contains("unverändert"))
    }

    @Test func storedHistory_keepsRevisionOutputs() async throws {
        let (model, store) = await make()
        model.open(context: .tasks)
        await propose(model, [("c1", "create_task", task("A"))])
        responder.enqueue("Ok.")
        model.composesRevision = true
        await model.send("Später")

        let stored = store.history(for: ChatStore.assistantKey)
        let revision = try #require(stored.compactMap { item -> String? in
            if case .functionOutput("c1", let output) = item { output } else { nil }
        }.first)
        #expect(revision.contains("revision_requested"))
    }
}
