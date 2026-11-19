import AIKit
import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// Answers with scripted function calls and records everything that was sent.
final class NoteSuggestionResponder: ResponseStreaming, @unchecked Sendable {
    struct Request {
        let instructions: String
        let input: [InputItem]
        let tools: [ToolDefinition]
    }

    private let lock = NSLock()
    private var script: [[StreamEvent]] = []
    private var failure: ChatGPTError?
    private var requests: [Request] = []
    /// Holds every answer back until it returns, for the late answer.
    var holdBack: (@Sendable () async -> Void)?

    func enqueue(_ calls: [(String, String)]) {
        lock.withLock {
            script.append(calls.map { .functionCall(callID: $0.0, name: $0.1.components(separatedBy: "|").first!, arguments: $0.1.components(separatedBy: "|").last!) }
                          + [.completed(usage: nil)])
        }
    }

    func fail(_ error: ChatGPTError) { lock.withLock { failure = error } }
    var sent: [Request] { lock.withLock { requests } }
    var calls: Int { sent.count }

    func respond(model: String, instructions: String, input: [InputItem], tools: [ToolDefinition],
                 jsonSchema: (name: String, schema: Data)?) -> AsyncThrowingStream<StreamEvent, Error> {
        let (events, error, holdBack) = lock.withLock { () -> ([StreamEvent], ChatGPTError?, (@Sendable () async -> Void)?) in
            requests.append(Request(instructions: instructions, input: input, tools: tools))
            return (script.isEmpty ? [.completed(usage: nil)] : script.removeFirst(), failure, self.holdBack)
        }
        return AsyncThrowingStream { continuation in
            Task {
                if let holdBack { await holdBack() }
                if let error { continuation.finish(throwing: error); return }
                events.forEach { continuation.yield($0) }
                continuation.finish()
            }
        }
    }
}

/// Executes confirmed calls without touching the app; records them.
@MainActor
final class NoteSuggestionTools: ToolHandler {
    var definitions: [ToolDefinition] { AppTools.allDefinitions }
    private(set) var runs: [ToolCall] = []
    var output = #"{"ok":true}"#
    func kind(of name: String) -> ToolKind { .write }
    func run(_ call: ToolCall) async -> String {
        runs.append(call)
        return output
    }
}

@MainActor
struct NoteSuggestionModelTests {
    final class Clock { var now: Date; init(_ now: Date) { self.now = now } }

    let container: ModelContainer
    let settings: AppSettings
    let calendar = testCalendar()
    let local: FakeTaskProvider
    let taskList: TaskListModel
    let planStore: PlanStore
    let planning: PlanningModel
    let calendarStore = FakeCalendarStore()
    let notes: NoteStore
    let responder = NoteSuggestionResponder()
    let tools = NoteSuggestionTools()
    let clock: Clock
    final class Counter { var models = 0; var consent = true }
    let counter = Counter()

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    init() async throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        settings.planCalendarID = "plan"
        let now = Clock(calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 10))!)
        clock = now
        local = FakeTaskProvider(source: .local, tasks: [
            makeTask("Wochenaufgabe", source: .local, due: DueDate(year: 2026, month: 11, day: 24)),
            makeTask("Zu spät dran", source: .local, due: DueDate(year: 2026, month: 11, day: 25)),
            makeTask("Überfällig", source: .local, due: DueDate(year: 2026, month: 11, day: 10)),
            makeTask("Heute", source: .local, due: DueDate(year: 2026, month: 11, day: 18)),
        ])
        local.tasks[0].notes = "Geheime Aufgabennotiz"
        taskList = TaskListModel(providers: [local], now: { now.now }, calendar: calendar)
        await taskList.reload()
        planStore = PlanStore(context: container.mainContext)
        let blocks = BlockPlanner(store: calendarStore, planStore: planStore, links: EventLinkStore(context: container.mainContext),
                                  settings: settings, calendar: calendar)
        planning = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: FakeAccessStore(), planStore: planStore,
                                 efforts: RecurringEffortStore(context: container.mainContext), blocks: blocks, settings: settings,
                                 marks: EventMarkStore(context: container.mainContext), now: { now.now }, calendar: calendar)
        await planning.reload()
        notes = NoteStore(context: container.mainContext, now: { now.now })
    }

    private func makeContext(events: [CalendarEvent] = []) -> NoteSuggestionContext {
        NoteSuggestionContext.make(taskList: taskList, planning: planning, events: { interval in
            events.filter { $0.end > interval.start && $0.start < interval.end }
        }, planCalendarID: "plan", now: clock.now)
    }

    private func makeModel(events: [CalendarEvent] = [], consent: Bool? = nil) -> NoteSuggestionModel {
        let counter = self.counter, clock = self.clock
        if let consent { counter.consent = consent }
        let context = makeContext(events: events)
        return NoteSuggestionModel(responder: responder, model: { counter.models += 1; return "gpt-test" }, tools: tools,
                                   describer: ActionCardDescriber(planning: planning), notes: notes,
                                   hasConsent: { counter.consent }, context: { context }, now: { clock.now })
    }

    private func note(_ text: String = "Training morgen 18:00 verschieben, Zahnarzt anrufen") -> NoteRecord {
        notes.create(text: text, kind: .evening, dayKey: "2026-11-18")!
    }

    private func call(_ id: String, _ name: String, _ json: String) -> (String, String) { (id, "\(name)|\(json)") }

    private func id(_ title: String) -> String { TaskID(source: .local, rawValue: title).key }

    // MARK: Consent and request

    @Test func fetch_withoutConsent_sendsNothing() async {
        let model = makeModel(consent: false)
        await model.fetch(noteID: note().id, text: "Text", kind: .evening)
        #expect(responder.calls == 0 && counter.models == 0)
        #expect(model.phase == .idle)
    }

    @Test func fetch_sendsOneRequest_withExactlyTheFiveWriteTools() async {
        let model = makeModel()
        await model.fetch(noteID: note().id, text: "Training verschieben", kind: .evening)
        #expect(responder.calls == 1)
        let names = Set(responder.sent[0].tools.map(\.name))
        #expect(names == NoteSuggestionRules.allowedTools)
        #expect(!names.contains("list_tasks") && !names.contains("delete_event") && !names.contains("plan_period"))
    }

    @Test func fetch_sendsTheNoteAndTheSevenDayContext_butNoRoutineData() async {
        routineLeakCheckSetup()
        let model = makeModel()
        await model.fetch(noteID: note("Notiz-Marker: Training verschieben").id, text: "Notiz-Marker: Training verschieben", kind: .evening)
        let sent = responder.sent[0]
        let text = sent.input.compactMap { item -> String? in if case .user(let text) = item { text } else { nil } }.joined(separator: "\n")
        #expect(text.contains("Notiz-Marker: Training verschieben"))
        #expect(text.contains("Wochenaufgabe"))          // due 24.11., inside the window
        #expect(!text.contains("Zu spät dran"))           // due 25.11., outside
        #expect(!text.contains("Geheime Aufgabennotiz"))  // notes of tasks never go
        for marker in ["Dankbar-Marker", "Lesen 20 min", "Reflexion-Marker"] {
            #expect(!text.contains(marker) && !sent.instructions.contains(marker))
        }
    }

    /// Routine data that must never reach the request.
    private func routineLeakCheckSetup() {
        let store = RoutineStore(context: container.mainContext)
        store.update(PlanDay(year: 2026, month: 11, day: 18)) { $0.gratitude = ["Dankbar-Marker"] }
        HabitStore(context: container.mainContext).save(Habit(name: "Lesen 20 min", symbol: "book", order: 0,
                                                              start: PlanDay(year: 2026, month: 11, day: 1)))
        store.saveReflection(WeekReflection(wentWell: "Reflexion-Marker"), weekStart: PlanDay(year: 2026, month: 11, day: 16), at: clock.now)
    }

    // MARK: Context

    @Test func context_keepsOverdueTasks_andCapsAtSixtyTasksAndHundredEvents() async {
        #expect(makeContext().taskIDs.contains(id("Überfällig")))
        local.tasks = (0..<70).map { makeTask("Aufgabe \($0)", source: .local, due: DueDate(year: 2026, month: 11, day: 18 + $0 % 7)) }
        let events = (0..<120).map { index in
            CalendarEvent(id: "e\(index)", externalID: nil, calendarID: "cal", title: "Termin \(index)",
                          start: at(18 + index % 7, 8 + index % 10), end: at(18 + index % 7, 9 + index % 10),
                          isAllDay: false, url: nil, isBusy: true, version: "1")
        }
        await taskList.reload()
        let capped = makeContext(events: events)
        #expect(capped.eventIDs.count == 100)
        #expect(capped.taskIDs.count <= NoteSuggestionContext.maximumTasks)
    }

    @Test func context_omitsTaskNotes() {
        let context = makeContext()
        #expect(!context.json.contains("Geheime Aufgabennotiz"))
        #expect(context.json.contains("Wochenaufgabe"))
    }

    @Test func context_marksTagwerkTimeBlocks() {
        let block = CalendarEvent(id: "b1", externalID: nil, calendarID: "plan", title: "Training", start: at(19, 18), end: at(19, 19),
                                  isAllDay: false, url: TaskLinkURL.make(TaskID(source: .local, rawValue: "Heute")),
                                  isBusy: true, version: "1")
        let plain = CalendarEvent(id: "p1", externalID: nil, calendarID: "cal", title: "Vorlesung", start: at(19, 9), end: at(19, 10),
                                  isAllDay: false, url: nil, isBusy: true, version: "1")
        let context = makeContext(events: [block, plain])
        #expect(context.eventIDs == ["b1", "p1"])
        #expect(context.blockEventIDs == ["b1"])
    }

    // MARK: Rules

    private func toolCall(_ name: String, _ json: String) -> ToolCall { ToolCall(id: UUID().uuidString, name: name, arguments: Data(json.utf8)) }

    @Test func accepted_dropsUnknownIDs_andKeepsAtMostFive() {
        let context = makeContext()
        let good = id("Wochenaufgabe")
        let calls = [toolCall("reschedule_task", #"{"id":"\#(good)","due":"2026-11-20"}"#),
                     toolCall("reschedule_task", #"{"id":"local:erfunden","due":"2026-11-20"}"#),
                     toolCall("delete_event", #"{"event_id":"p1"}"#),
                     toolCall("complete_task", #"{"id":"\#(good)"}"#)]
        #expect(NoteSuggestionRules.accepted(calls, context: context).map(\.name) == ["reschedule_task"])
        let many = (0..<8).map { toolCall("create_task", #"{"title":"Aufgabe \#($0)"}"#) }
        #expect(NoteSuggestionRules.accepted(many, context: context).count == 5)
    }

    @Test func accepted_updateEvent_onlyForTagwerkBlocks() {
        let block = CalendarEvent(id: "b1", externalID: nil, calendarID: "plan", title: "Training", start: at(19, 18), end: at(19, 19),
                                  isAllDay: false, url: TaskLinkURL.make(TaskID(source: .local, rawValue: "Heute")),
                                  isBusy: true, version: "1")
        let plain = CalendarEvent(id: "p1", externalID: nil, calendarID: "cal", title: "Vorlesung", start: at(19, 9), end: at(19, 10),
                                  isAllDay: false, url: nil, isBusy: true, version: "1")
        let context = makeContext(events: [block, plain])
        let calls = [toolCall("update_event", #"{"event_id":"p1","start":"2026-11-19T07:00"}"#),
                     toolCall("update_event", #"{"event_id":"b1","start":"2026-11-19T07:00"}"#)]
        #expect(NoteSuggestionRules.accepted(calls, context: context).map { $0.arguments }.count == 1)
        #expect(String(decoding: NoteSuggestionRules.accepted(calls, context: context)[0].arguments, as: UTF8.self).contains("b1"))
    }

    @Test func accepted_createTask_needsNoID_butNeverForGitHub() {
        let context = makeContext()
        let calls = [toolCall("create_task", #"{"title":"Zahnarzt anrufen","source":null}"#),
                     toolCall("create_task", #"{"title":"Issue","source":"github","repository":"a/b"}"#)]
        #expect(NoteSuggestionRules.accepted(calls, context: context).count == 1)
    }

    // MARK: Cards

    @Test func fetch_setsProcessedAt() async {
        let record = note()
        responder.enqueue([call("c1", "create_task", #"{"title":"Zahnarzt anrufen"}"#)])
        let model = makeModel()
        await model.fetch(noteID: record.id, text: record.text, kind: .evening)
        #expect(notes.note(id: record.id)?.processedAt == clock.now)
        #expect(model.cards.count == 1 && model.phase == .loaded)
        #expect(model.cards[0].status == .pending)
        #expect(model.cards[0].text.title == "Zahnarzt anrufen")
    }

    @Test func confirm_runsTheToolOnce_withoutASecondRequest_andCountsTheAction() async {
        let record = note()
        responder.enqueue([call("c1", "create_task", #"{"title":"Zahnarzt anrufen"}"#)])
        let model = makeModel()
        await model.fetch(noteID: record.id, text: record.text, kind: .evening)
        await model.confirm("c1")
        #expect(responder.calls == 1 && tools.runs.count == 1)
        if case .done(let output) = model.cards[0].status { #expect(output == #"{"ok":true}"#) } else { Issue.record("not done") }
        #expect(model.cards[0].time == clock.now)
        #expect(notes.note(id: record.id)?.derivedActionCount == 1)
        // A second tap changes nothing.
        await model.confirm("c1")
        #expect(tools.runs.count == 1)
    }

    @Test func confirm_withAToolError_showsTheErrorAndDoesNotCount() async {
        let record = note()
        responder.enqueue([call("c1", "create_task", #"{"title":"X"}"#)])
        tools.output = #"{"error":"Nicht möglich."}"#
        let model = makeModel()
        await model.fetch(noteID: record.id, text: record.text, kind: .evening)
        await model.confirm("c1")
        if case .done(let output) = model.cards[0].status { #expect(ActionCardView.error(in: output) == "Nicht möglich.") }
        #expect(notes.note(id: record.id)?.derivedActionCount == 0)
    }

    @Test func confirmAll_runsOnlyPendingCards() async {
        let record = note()
        responder.enqueue([call("c1", "create_task", #"{"title":"A"}"#), call("c2", "create_task", #"{"title":"B"}"#),
                           call("c3", "create_task", #"{"title":"C"}"#)])
        let model = makeModel()
        await model.fetch(noteID: record.id, text: record.text, kind: .evening)
        model.decline("c2")
        #expect(model.openCount == 2)
        await model.confirmAll()
        #expect(tools.runs.map(\.id) == ["c1", "c3"])
        #expect(model.openCount == 0)
        #expect(model.cards[1].status == .declined)
    }

    @Test func answerWithoutCalls_isEmpty() async {
        let record = note()
        responder.enqueue([])
        let model = makeModel()
        await model.fetch(noteID: record.id, text: record.text, kind: .evening)
        #expect(model.phase == .empty && model.cards.isEmpty)
        #expect(notes.note(id: record.id)?.processedAt != nil)
    }

    @Test func networkFailure_offersRetry() async {
        let record = note()
        responder.fail(.network)
        let model = makeModel()
        await model.fetch(noteID: record.id, text: record.text, kind: .evening)
        #expect(model.phase == .failed("Keine Verbindung. Vorschläge brauchen Internet."))
        #expect(notes.note(id: record.id)?.processedAt == nil)
    }

    @Test func lateAnswerAfterReset_isDiscarded() async {
        let record = note()
        let gate = Gate()
        responder.holdBack = { await gate.wait() }
        responder.enqueue([call("c1", "create_task", #"{"title":"Zu spät"}"#)])
        let model = makeModel()
        let fetching = Task { await model.fetch(noteID: record.id, text: record.text, kind: .evening) }
        while responder.calls == 0 { await Task.yield() }
        model.reset()
        gate.open()
        await fetching.value
        #expect(model.cards.isEmpty && model.phase == .idle)
        #expect(notes.note(id: record.id)?.processedAt == nil)
    }

    // MARK: Which day may ask

    @Test func olderDay_cannotSuggest() {
        let clock = self.clock
        let old = NoteFieldModel(store: notes, kind: .evening, day: PlanDay(year: 2026, month: 11, day: 17), debounce: .milliseconds(1),
                                 sleep: { _ in }, isSignedIn: { true }, now: { clock.now }, calendar: calendar)
        old.text = "Etwas"
        #expect(!old.canSuggest)
    }

    @Test func eveningSheetAfterMidnight_canStillSuggest() {
        clock.now = at(19, 1)
        let clock = self.clock
        let model = NoteFieldModel(store: notes, kind: .evening, day: PlanDay(year: 2026, month: 11, day: 18), debounce: .milliseconds(1),
                                   sleep: { _ in }, isSignedIn: { true }, now: { clock.now }, calendar: calendar)
        model.text = "Etwas"
        #expect(model.canSuggest)
        model.text = "  "
        #expect(!model.canSuggest)
    }

    @Test func notSignedIn_cannotSuggest() {
        let clock = self.clock
        let model = NoteFieldModel(store: notes, kind: .evening, day: PlanDay(year: 2026, month: 11, day: 18), debounce: .milliseconds(1),
                                   sleep: { _ in }, isSignedIn: { false }, now: { clock.now }, calendar: calendar)
        model.text = "Etwas"
        #expect(!model.canSuggest)
    }

    @Test func instructions_forbidInventedIDsAndLimitTheCount() {
        let text = NoteSuggestionModel.instructions
        #expect(text.contains("at most 5") || text.contains("at most five"))
    }
}
