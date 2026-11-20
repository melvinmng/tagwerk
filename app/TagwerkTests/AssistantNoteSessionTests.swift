import AIKit
import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// Note text and the session (issue #173, point 8): the history in memory keeps the full results, what is saved
/// keeps only the stored form; the session ends with the chat, the consent or the app.
@MainActor
struct AssistantNoteSessionTests {
    let container: ModelContainer
    let settings: AppSettings
    let calendarStore = FakeCalendarStore()
    let local: FakeTaskProvider
    let taskList: TaskListModel
    let responder = FakePlanResponder()
    let calendar = testCalendar()
    /// Marker words that appear in note titles and excerpts only.
    static let title = "Zuckerbäckerei Planung"
    static let snippet = "geheimer Teigplan"

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        settings.planCalendarID = "plan"
        local = FakeTaskProvider(source: .local, tasks: [makeTask("Fahrrad", source: .local, due: DueDate(year: 2026, month: 11, day: 18))])
        taskList = TaskListModel(providers: [local], now: testNow, calendar: calendar)
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
        let note = NoteSearchItem(id: UUID(), text: "\(Self.title)\nDas ist der \(Self.snippet) für Sonntag", kindLabel: "Notiz",
                                  updatedAt: testNow())
        let sources = SearchToolSources(events: { _ in [] }, calendarNames: { [:] }, completedTasks: { [] },
                                        notes: { [note] }, notesAllowed: { true })
        let tools = AppTools(taskList: taskList, planning: planning, planner: nil, events: { _ in [] }, search: sources)
        let store = ChatStore(context: container.mainContext)
        let model = AssistantModel(responder: responder, tools: tools, model: { "gpt-test" }, store: store,
                                   planning: planning, now: testNow)
        model.language = { .german }
        return (model, store)
    }

    private static let searchCall = StreamEvent.functionCall(
        callID: "s1", name: "search",
        arguments: #"{"query":"teigplan","kind":"all","include_completed":false,"from":null,"to":null,"github_online":false}"#)
    private static let completeCall = StreamEvent.functionCall(callID: "c1", name: "complete_task", arguments: #"{"id":"local:Fahrrad"}"#)

    private func storedText(_ store: ChatStore) -> String {
        let history = store.history(for: ChatStore.assistantKey)
        return (try? String(decoding: JSONEncoder().encode(history), as: UTF8.self)) ?? ""
    }

    @Test func persist_storesReducedFormWhileCardsAreOpen() async {
        let (model, store) = await make()
        model.open(context: .settings)
        responder.enqueueEvents([Self.searchCall, Self.completeCall, .completed(usage: nil)])
        await model.send("Such meine Notiz und hak das Fahrrad ab")
        #expect(model.conversation?.pendingActions.map(\.id) == ["c1"])
        // In memory the model still has the full result.
        let memory = model.conversation?.history.map { "\($0)" }.joined() ?? ""
        #expect(memory.contains(Self.title) && memory.contains(Self.snippet))
        // The saved chat holds no title and no excerpt, but ids and the marker.
        let stored = storedText(store)
        #expect(!stored.contains(Self.title) && !stored.contains(Self.snippet))
        #expect(stored.contains("redacted") && stored.contains("note:"))
    }

    @Test func nextTurn_stillSendsFullOutput() async {
        let (model, store) = await make()
        model.open(context: .settings)
        responder.enqueueEvents([Self.searchCall, .completed(usage: nil)])
        responder.enqueue("Ich habe eine Notiz gefunden.")
        await model.send("Such meine Notiz")
        responder.enqueue("Gern.")
        await model.send("Danke")
        let lastInput = responder.calls.last?.input ?? []
        let sent = lastInput.map { "\($0)" }.joined()
        #expect(sent.contains(Self.title) && sent.contains(Self.snippet))
        #expect(!storedText(store).contains(Self.title))
    }

    @Test func restoredChat_hasNoNoteText() async {
        let (model, _) = await make()
        model.open(context: .settings)
        responder.enqueueEvents([Self.searchCall, .completed(usage: nil)])
        responder.enqueue("Ich habe eine Notiz gefunden.")
        await model.send("Such meine Notiz")
        let (reopened, _) = await make()
        reopened.open(context: .settings)
        let restored = reopened.conversation?.history.map { "\($0)" }.joined() ?? ""
        #expect(!restored.isEmpty)
        #expect(!restored.contains(Self.title) && !restored.contains(Self.snippet))
        // The next request of the restored chat holds no note text either.
        responder.enqueue("Okay.")
        await reopened.send("Und jetzt?")
        let sent = responder.calls.last?.input.map { "\($0)" }.joined() ?? ""
        #expect(!sent.contains(Self.title))
    }
}
