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

    private func make(responder override: ResponseStreaming? = nil) async -> (AssistantModel, ChatStore) {
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
        let model = AssistantModel(responder: override ?? responder, tools: tools, model: { "gpt-test" }, store: store,
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

    // MARK: Consent withdrawn

    @Test func withdrawingConsent_reducesHistoryInMemory() async {
        let (model, store) = await make()
        model.open(context: .settings)
        responder.enqueueEvents([Self.searchCall, .completed(usage: nil)])
        responder.enqueue("Ich habe eine Notiz gefunden.")
        await model.send("Such meine Notiz")
        #expect(model.conversation?.history.map { "\($0)" }.joined().contains(Self.title) == true)

        model.endNoteSession()

        let memory = model.conversation?.history.map { "\($0)" }.joined() ?? ""
        #expect(!memory.isEmpty && !memory.contains(Self.title) && !memory.contains(Self.snippet))
        #expect(!storedText(store).contains(Self.title))
        // The chat goes on, and the next request holds no note text.
        responder.enqueue("Okay.")
        await model.send("Und jetzt?")
        let sent = responder.calls.last?.input.map { "\($0)" }.joined() ?? ""
        #expect(!sent.contains(Self.title) && !sent.contains(Self.snippet))
        #expect(sent.contains("Ich habe eine Notiz gefunden."))
    }

    @Test func withdrawingConsent_duringTurn_reducesAfterwards() async {
        let gate = TurnGate()
        let (model, store) = await make(responder: gate)
        model.open(context: .settings)
        gate.enqueue([Self.searchCall, .completed(usage: nil)], blocked: false)
        gate.enqueue([.textDelta("Gefunden."), .completed(usage: nil)], blocked: true)
        let sending = Task { await model.send("Such meine Notiz") }
        // The search ran; the second request is held back.
        while !gate.isHolding { await Task.yield() }
        model.endNoteSession()
        let during = model.conversation?.history.map { "\($0)" }.joined() ?? ""
        #expect(during.contains(Self.title), "a running turn is not touched")
        gate.release()
        await sending.value
        let after = model.conversation?.history.map { "\($0)" }.joined() ?? ""
        #expect(!after.contains(Self.title) && !after.contains(Self.snippet))
        #expect(after.contains("Gefunden."))
        #expect(!storedText(store).contains(Self.title))
    }
}

/// A model answer that waits until it is released, to end the consent in the middle of a turn.
final class TurnGate: ResponseStreaming, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [(events: [StreamEvent], blocked: Bool)] = []
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private var holding = false

    func enqueue(_ events: [StreamEvent], blocked: Bool) { lock.withLock { answers.append((events, blocked)) } }
    var isHolding: Bool { lock.withLock { holding } }

    func release() {
        let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            released = true
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume()
    }

    func respond(model: String, instructions: String, input: [InputItem], tools: [ToolDefinition],
                 jsonSchema: (name: String, schema: Data)?) -> AsyncThrowingStream<StreamEvent, Error> {
        let answer = lock.withLock { answers.isEmpty ? nil : answers.removeFirst() }
        return AsyncThrowingStream { stream in
            Task {
                if let answer, answer.blocked {
                    await withCheckedContinuation { (waiting: CheckedContinuation<Void, Never>) in
                        let alreadyReleased = lock.withLock { () -> Bool in
                            if released { return true }
                            continuation = waiting
                            holding = true
                            return false
                        }
                        if alreadyReleased { waiting.resume() }
                    }
                }
                answer?.events.forEach { stream.yield($0) }
                stream.finish()
            }
        }
    }
}
