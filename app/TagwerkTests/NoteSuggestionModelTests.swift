import AIKit
import Foundation
import GitHubKit
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

    /// An answer with a sentence of text before the calls.
    func enqueue(_ calls: [(String, String)], text: String) {
        lock.withLock {
            script.append([.textDelta(text)]
                          + calls.map { .functionCall(callID: $0.0, name: $0.1.components(separatedBy: "|").first!, arguments: $0.1.components(separatedBy: "|").last!) }
                          + [.completed(usage: nil)])
        }
    }

    /// An answer with text only, e.g. the JSON of a single-card follow-up.
    func enqueue(text: String) {
        lock.withLock { script.append([.textDelta(text), .completed(usage: nil)]) }
    }

    func fail(_ error: ChatGPTError) { lock.withLock { failure = error } }
    func clearFailure() { lock.withLock { failure = nil } }
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

    private func makeModel(events: [CalendarEvent] = [], consent: Bool? = nil,
                           directory: FakeGitHubDirectory? = nil) -> NoteSuggestionModel {
        let counter = self.counter, clock = self.clock
        if let consent { counter.consent = consent }
        let context = makeContext(events: events)
        let planning = self.planning
        return NoteSuggestionModel(responder: responder, model: { counter.models += 1; return "gpt-test" }, tools: tools,
                                   describer: ActionCardDescriber(planning: planning, gitHubDirectory: { directory }), notes: notes,
                                   hasConsent: { counter.consent }, context: { context }, now: { clock.now },
                                   gitHubDirectory: { directory })
    }

    /// Two repositories with the same short name in different owners, one of them unique, and two projects.
    private func twoRepositoryDirectory() -> FakeGitHubDirectory {
        let tagwerk = ProjectInfo(id: "PVT_T", number: 1, title: "Tagwerk", fields: [], repositories: ["melvinmng/tagwerk"])
        let other = ProjectInfo(id: "PVT_O", number: 2, title: "Sonstiges", fields: [], repositories: [])
        let catalog = GitHubCatalog(repositories: ["melvinmng/tagwerk", "melvinmng/app", "firma/app"], projects: [tagwerk, other],
                                    fetchedAt: Date(timeIntervalSince1970: 0))
        return FakeGitHubDirectory(login: "octo", catalog: catalog,
                                   assignable: ["melvinmng/tagwerk": ["octo", "lea-m"], "melvinmng/app": ["octo"], "firma/app": ["octo"]])
    }

    private func arguments(of call: ToolCall) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: call.arguments) as? [String: Any]) ?? [:]
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

    @Test func request_sendsPlainTextWithoutAttachmentReferences() async {
        let reference = MarkdownText.reference(for: UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301")!, name: "Foto", isImage: true)
        let file = MarkdownText.reference(for: UUID(uuidString: "A1B2C3D4-0000-4000-8000-000000000002")!, name: "Plan.pdf", isImage: false)
        let text = "# Training\n- [ ] **Zahnarzt** anrufen\n\(reference)\n\(file)"
        let model = makeModel()
        await model.fetch(noteID: note(text).id, text: text, kind: .evening)
        let sent = responder.sent[0].input.compactMap { item -> String? in if case .user(let text) = item { text } else { nil } }.joined(separator: "\n")
        #expect(sent.contains("Training") && sent.contains("Zahnarzt anrufen") && sent.contains("Plan.pdf"))
        #expect(!sent.contains("attachment:") && !sent.contains("3F2504E0") && !sent.contains("**") && !sent.contains("!["))
    }

    @Test func request_sendsNoHtml() async {
        let text = "Vor <b onclick=\"x()\">fett</b> <img src=\"https://example.com/pixel.png\"> <script>alert(1)</script>nach"
        let model = makeModel()
        await model.fetch(noteID: note(text).id, text: text, kind: .evening)
        let sent = responder.sent[0].input.compactMap { item -> String? in if case .user(let text) = item { text } else { nil } }.joined(separator: "\n")
        #expect(sent.contains("Vor fett") && sent.contains("nach"))
        #expect(!sent.contains("<b") && !sent.contains("<img") && !sent.contains("<script") && !sent.contains("example.com") && !sent.contains("onclick"))
    }

    @Test func fetch_neverSendsADreamNote() async {
        let dream = notes.create(text: "Traum vom Meer", kind: .dream, dayKey: "2026-11-18")!
        let model = makeModel()
        await model.fetch(noteID: dream.id, text: "Traum vom Meer", kind: .dream)
        #expect(responder.calls == 0 && counter.models == 0)
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

    @Test func accepted_gitHubCall_isDroppedWithoutGitHub() {
        let context = makeContext()
        let calls = [toolCall("create_task", #"{"title":"Zahnarzt anrufen","source":null}"#),
                     toolCall("create_task", #"{"title":"Issue","source":"github","repository":"a/b"}"#)]
        #expect(NoteSuggestionRules.accepted(calls, context: context).count == 1)
        #expect(NoteSuggestionRules.accepted(calls, context: context, gitHub: false).count == 1)
    }

    @Test func accepted_gitHubCall_isKeptWithGitHub() {
        let context = makeContext()
        let calls = [toolCall("create_task", #"{"title":"Zahnarzt anrufen","source":null}"#),
                     toolCall("create_task", #"{"title":"Issue","source":"github","repository":"a/b"}"#)]
        #expect(NoteSuggestionRules.accepted(calls, context: context, gitHub: true).count == 2)
    }

    // MARK: Issue target

    private func issueCall(_ json: String) -> ToolCall { toolCall("create_task", json) }

    @Test func issueDraft_forcesAssigneesToNull() throws {
        let catalog = try #require(twoRepositoryDirectory().storedCatalog)
        let draft = NoteSuggestionRules.issueDraft(
            for: issueCall(#"{"title":"Export","source":"github","repository":"melvinmng/tagwerk","project_ids":null,"assignees":["lea-m","octo"]}"#),
            catalog: catalog)
        let args = arguments(of: draft.call)
        #expect(args["assignees"] is NSNull)
        #expect(args["source"] as? String == "github")
        // Without the key the model has no say either: the key is present and null.
        let without = NoteSuggestionRules.issueDraft(for: issueCall(#"{"title":"Export","source":"github","repository":"melvinmng/tagwerk"}"#),
                                                     catalog: catalog)
        #expect(arguments(of: without.call)["assignees"] is NSNull)
    }

    @Test func issueDraft_resolvesRepositoryByShortName() throws {
        let catalog = try #require(twoRepositoryDirectory().storedCatalog)
        let draft = NoteSuggestionRules.issueDraft(for: issueCall(#"{"title":"Export","source":"github","repository":"Tagwerk"}"#), catalog: catalog)
        #expect(draft.target == AppTools.GitHubTarget(repository: "melvinmng/tagwerk", projectIDs: ["PVT_T"]))
        #expect(arguments(of: draft.call)["repository"] as? String == "melvinmng/tagwerk")
        #expect(arguments(of: draft.call)["project_ids"] as? [String] == ["PVT_T"])
        #expect(NoteSuggestionRules.repository(named: "MELVINMNG/TAGWERK", in: catalog) == "melvinmng/tagwerk")
        #expect(NoteSuggestionRules.repository(named: " tagwerk ", in: catalog) == "melvinmng/tagwerk")
    }

    @Test func issueDraft_ambiguousShortName_needsTarget() throws {
        let catalog = try #require(twoRepositoryDirectory().storedCatalog)
        #expect(NoteSuggestionRules.repository(named: "app", in: catalog) == nil)
        for repository in ["app", "unbekannt", "andere/tagwerk", ""] {
            let draft = NoteSuggestionRules.issueDraft(
                for: issueCall(#"{"title":"Export","source":"github","repository":"\#(repository)"}"#), catalog: catalog)
            #expect(draft.target == nil, "repository \(repository)")
            #expect(arguments(of: draft.call)["repository"] is NSNull, "repository \(repository)")
        }
        // A missing repository with several to choose from is not guessed either.
        let none = NoteSuggestionRules.issueDraft(for: issueCall(#"{"title":"Export","source":"github","repository":null}"#), catalog: catalog)
        #expect(none.target == nil)
    }

    @Test func issueDraft_singleRepository_usesLinkedProjects() throws {
        let catalog = try #require(FakeGitHubDirectory.single().storedCatalog)
        let draft = NoteSuggestionRules.issueDraft(for: issueCall(#"{"title":"Export","source":"github","repository":null,"project_ids":null}"#),
                                                   catalog: catalog)
        #expect(draft.target == AppTools.GitHubTarget(repository: "beispiel/app", projectIDs: ["PVT_1"]))
        #expect(arguments(of: draft.call)["repository"] as? String == "beispiel/app")
        #expect(arguments(of: draft.call)["project_ids"] as? [String] == ["PVT_1"])
    }

    @Test func issueDraft_unknownProjectIDs_areDropped() throws {
        let catalog = try #require(twoRepositoryDirectory().storedCatalog)
        let draft = NoteSuggestionRules.issueDraft(
            for: issueCall(#"{"title":"Export","source":"github","repository":"melvinmng/tagwerk","project_ids":["PVT_erfunden"]}"#), catalog: catalog)
        // The invented id is gone; the project linked to the repository takes its place.
        #expect(draft.target == AppTools.GitHubTarget(repository: "melvinmng/tagwerk", projectIDs: ["PVT_T"]))
        #expect(arguments(of: draft.call)["project_ids"] as? [String] == ["PVT_T"])
        // A known id the model names is kept.
        let known = NoteSuggestionRules.issueDraft(
            for: issueCall(#"{"title":"Export","source":"github","repository":"melvinmng/tagwerk","project_ids":["PVT_O","PVT_erfunden"]}"#),
            catalog: catalog)
        #expect(known.target == AppTools.GitHubTarget(repository: "melvinmng/tagwerk", projectIDs: ["PVT_O"]))
    }

    @Test func issueDraft_repositoryWithoutAProjectToTake_needsTarget() throws {
        // The repository is clear, but two projects exist and none is linked to it: the user chooses.
        let catalog = try #require(twoRepositoryDirectory().storedCatalog)
        let draft = NoteSuggestionRules.issueDraft(for: issueCall(#"{"title":"Export","source":"github","repository":"melvinmng/app"}"#),
                                                   catalog: catalog)
        #expect(draft.target == nil)
        #expect(arguments(of: draft.call)["repository"] as? String == "melvinmng/app")
        #expect(arguments(of: draft.call)["project_ids"] is NSNull)
    }

    @Test func issueDraft_leavesOtherCallsUntouched() throws {
        let catalog = try #require(twoRepositoryDirectory().storedCatalog)
        let local = issueCall(#"{"title":"Zahnarzt","source":"local"}"#)
        let draft = NoteSuggestionRules.issueDraft(for: local, catalog: catalog)
        #expect(draft.call == local && draft.target == nil)
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

    @Test func instructions_withoutGitHub_forbidGitHub() {
        #expect(NoteSuggestionModel.instructions.contains(#"never "github""#))
        #expect(NoteSuggestionModel.instructions(gitHub: false) == NoteSuggestionModel.instructions)
        let withGitHub = NoteSuggestionModel.instructions(gitHub: true)
        #expect(!withGitHub.contains(#"never "github""#))
        #expect(withGitHub.contains(#"source "github""#) && withGitHub.contains("project_ids null") && withGitHub.contains("assignees null"))
    }

    // MARK: GitHub issue cards

    private func fetchIssueCards(_ calls: [(String, String)], directory: FakeGitHubDirectory?) async -> NoteSuggestionModel {
        let record = note("Issue im Tagwerk-Repo: Export prüfen")
        responder.enqueue(calls)
        let model = makeModel(directory: directory)
        await model.fetch(noteID: record.id, text: record.text, kind: .evening)
        return model
    }

    @Test func fetch_gitHubCard_withoutGitHub_isNotOffered() async {
        let model = await fetchIssueCards([call("c1", "create_task", #"{"title":"Export prüfen","source":"github","repository":"tagwerk"}"#)],
                                          directory: nil)
        #expect(model.cards.isEmpty && model.phase == .empty)
        // Signed in but no catalog stored: the target cannot be resolved, so no issue is offered either.
        let noCatalog = await fetchIssueCards([call("c2", "create_task", #"{"title":"Export prüfen","source":"github"}"#)],
                                              directory: FakeGitHubDirectory(catalog: nil))
        #expect(noCatalog.cards.isEmpty)
    }

    @Test func fetch_gitHubCard_withTarget_isReadyAndShowsAssignment() async {
        let model = await fetchIssueCards([call("c1", "create_task", #"{"title":"Export prüfen","source":"github","repository":"tagwerk","assignees":["lea-m"]}"#)],
                                          directory: twoRepositoryDirectory())
        #expect(model.cards.count == 1)
        let card = model.cards[0]
        #expect(!card.needsTarget && card.target == AppTools.GitHubTarget(repository: "melvinmng/tagwerk", projectIDs: ["PVT_T"]))
        #expect(card.text.title == "Export prüfen")
        // The target has its own row; the text names the assignment only, and always the user (decision D8).
        #expect(card.text.change == "Issue anlegen · Zugewiesen: dir")
        #expect(model.confirmableCount == 1)
    }

    @Test func fetch_gitHubCard_withoutTarget_needsTarget() async {
        let model = await fetchIssueCards([call("c1", "create_task", #"{"title":"Export prüfen","source":"github","repository":"app"}"#)],
                                          directory: twoRepositoryDirectory())
        #expect(model.cards.count == 1 && model.cards[0].needsTarget && model.cards[0].target == nil)
        #expect(model.openCount == 1 && model.confirmableCount == 0)
    }

    @Test func confirm_cardNeedingTarget_doesNothing() async {
        let model = await fetchIssueCards([call("c1", "create_task", #"{"title":"Export prüfen","source":"github"}"#)],
                                          directory: twoRepositoryDirectory())
        await model.confirm("c1")
        #expect(tools.runs.isEmpty)
        #expect(model.cards[0].status == .pending)
    }

    @Test func confirmAll_skipsUnresolvedIssueCards() async {
        let model = await fetchIssueCards([call("c1", "create_task", #"{"title":"Zahnarzt anrufen"}"#),
                                           call("c2", "create_task", #"{"title":"Offen","source":"github"}"#),
                                           call("c3", "create_task", #"{"title":"Klar","source":"github","repository":"tagwerk"}"#)],
                                          directory: twoRepositoryDirectory())
        #expect(model.openCount == 3 && model.confirmableCount == 2)
        await model.confirmAll()
        #expect(tools.runs.map(\.id) == ["c1", "c3"])
        #expect(model.cards[1].status == .pending)
        #expect(model.confirmableCount == 0 && model.openCount == 1)
    }

    @Test func confirmAll_skipsIssueCardsAssignedBeyondMe() async {
        let model = await fetchIssueCards([call("c1", "create_task", #"{"title":"Zahnarzt anrufen"}"#),
                                           call("c2", "create_task", #"{"title":"Für Lea","source":"github","repository":"tagwerk"}"#),
                                           call("c3", "create_task", #"{"title":"Für niemanden","source":"github","repository":"tagwerk"}"#),
                                           call("c4", "create_task", #"{"title":"Für mich","source":"github","repository":"tagwerk"}"#)],
                                          directory: twoRepositoryDirectory())
        #expect(model.confirmableCount == 4)
        model.setTarget("c2", repository: "melvinmng/tagwerk", projectIDs: ["PVT_T"], assignees: ["lea-m"])
        model.setTarget("c3", repository: "melvinmng/tagwerk", projectIDs: ["PVT_T"], assignees: [])
        model.setTarget("c4", repository: "melvinmng/tagwerk", projectIDs: ["PVT_T"], assignees: ["octo"])
        // Issues for other people or for no one are confirmed alone, as in the chat.
        #expect(model.confirmableCount == 2)
        #expect(model.openCount == 4 && model.hasSingleConfirmationCards)
        await model.confirmAll()
        #expect(tools.runs.map(\.id) == ["c1", "c4"])
        #expect(model.cards[1].status == .pending && model.cards[2].status == .pending)
        // A tap on the card itself still confirms it.
        await model.confirm("c2")
        await model.confirm("c3")
        #expect(tools.runs.map(\.id) == ["c1", "c4", "c2", "c3"])
        #expect(!model.hasSingleConfirmationCards)
    }

    @Test func setTarget_rewritesArgumentsAndDescription() async {
        let model = await fetchIssueCards([call("c1", "create_task", #"{"title":"Export prüfen","source":"github","repository":null,"assignees":["fremd"]}"#)],
                                          directory: twoRepositoryDirectory())
        #expect(model.cards[0].needsTarget)
        model.setTarget("c1", repository: "melvinmng/tagwerk", projectIDs: ["PVT_T", "PVT_O"], assignees: ["lea-m"])
        let card = model.cards[0]
        #expect(!card.needsTarget && card.target == AppTools.GitHubTarget(repository: "melvinmng/tagwerk", projectIDs: ["PVT_T", "PVT_O"]))
        let args = arguments(of: card.call)
        #expect(args["repository"] as? String == "melvinmng/tagwerk")
        #expect(args["project_ids"] as? [String] == ["PVT_T", "PVT_O"])
        #expect(args["assignees"] as? [String] == ["lea-m"])
        #expect(args["title"] as? String == "Export prüfen")
        #expect(card.call.id == "c1")
        #expect(card.text.change == "Issue anlegen · Zugewiesen: lea-m (nicht dir)")
        // `nil` assignees stand for the user, and an empty list of projects is a choice.
        model.setTarget("c1", repository: "melvinmng/app", projectIDs: [], assignees: nil)
        #expect(arguments(of: model.cards[0].call)["assignees"] is NSNull)
        #expect(arguments(of: model.cards[0].call)["project_ids"] as? [String] == [])
        #expect(model.cards[0].text.change == "Issue anlegen · Zugewiesen: dir")
        #expect(model.confirmableCount == 1)
    }

    @Test func confirm_afterSetTarget_runsTheRewrittenCall() async {
        let model = await fetchIssueCards([call("c1", "create_task", #"{"title":"Export prüfen","source":"github"}"#)],
                                          directory: twoRepositoryDirectory())
        model.setTarget("c1", repository: "melvinmng/tagwerk", projectIDs: ["PVT_T"], assignees: nil)
        await model.confirm("c1")
        #expect(tools.runs.count == 1)
        let args = arguments(of: tools.runs[0])
        #expect(args["repository"] as? String == "melvinmng/tagwerk" && args["project_ids"] as? [String] == ["PVT_T"])
        #expect(args["assignees"] is NSNull)
    }

    @Test func setTarget_ignoresDoneAndOtherCards() async {
        let model = await fetchIssueCards([call("c1", "create_task", #"{"title":"A","source":"github","repository":"tagwerk"}"#),
                                           call("c2", "create_task", #"{"title":"B"}"#)],
                                          directory: twoRepositoryDirectory())
        await model.confirm("c1")
        let before = model.cards
        model.setTarget("c1", repository: "melvinmng/app", projectIDs: [], assignees: nil)   // already confirmed
        model.setTarget("c2", repository: "melvinmng/app", projectIDs: [], assignees: nil)   // not an issue
        model.setTarget("fehlt", repository: "melvinmng/app", projectIDs: [], assignees: nil)
        #expect(model.cards == before)
    }

    @Test func targetSheetModel_startsFromTheCard() async throws {
        let directory = twoRepositoryDirectory()
        let model = await fetchIssueCards([call("c1", "create_task", #"{"title":"A","source":"github","repository":"melvinmng/app"}"#),
                                           call("c2", "create_task", #"{"title":"B","source":"github","repository":"tagwerk"}"#),
                                           call("c3", "create_task", #"{"title":"C"}"#)], directory: directory)
        // The repository is clear, no project is: the sheet opens with the repository and without projects.
        let open = try #require(model.targetSheetModel(for: "c1"))
        #expect(open.repository == "melvinmng/app" && open.projectIDs.isEmpty && !open.assigneesChosen && open.me == "octo")
        await open.loadAssignees()
        #expect(open.assigneeCandidates == ["octo"])
        let resolved = try #require(model.targetSheetModel(for: "c2"))
        #expect(resolved.repository == "melvinmng/tagwerk" && resolved.projectIDs == ["PVT_T"])
        #expect(model.targetSheetModel(for: "c3") == nil)          // not an issue
        #expect(model.targetSheetModel(for: "fehlt") == nil)
        #expect(model.targetSheetModel(for: "c1") != nil)
        await model.confirm("c2")
        #expect(model.targetSheetModel(for: "c2") == nil)          // done
    }

    @Test func targetSummary_followsTheCard() async {
        let model = await fetchIssueCards([call("c1", "create_task", #"{"title":"A","source":"github","repository":"tagwerk"}"#),
                                           call("c2", "create_task", #"{"title":"B","source":"github"}"#),
                                           call("c3", "create_task", #"{"title":"C"}"#)], directory: twoRepositoryDirectory())
        #expect(model.targetSummary(of: model.cards[0]) == "Ziel: melvinmng/tagwerk · Projekt Tagwerk")
        #expect(model.targetSummary(of: model.cards[1]) == "Ziel wählen")
        #expect(model.targetSummary(of: model.cards[2]) == nil)
    }

    @Test func request_containsNoRepositoryNames() async {
        let directory = twoRepositoryDirectory()
        _ = await fetchIssueCards([], directory: directory)
        let sent = responder.sent[0]
        let text = sent.input.compactMap { item -> String? in if case .user(let text) = item { text } else { nil } }.joined(separator: "\n")
        let tools = sent.tools.map { $0.description + String(decoding: $0.parameters, as: UTF8.self) }.joined(separator: "\n")
        let everything = [sent.instructions, text, tools].joined(separator: "\n")
        for name in ["melvinmng", "firma/app", "PVT_T", "PVT_O", "Sonstiges", "list_github_targets"] {
            #expect(!everything.contains(name), "\(name) was sent")
        }
        // The model is told how to name a GitHub issue.
        #expect(sent.instructions.contains(#"source "github""#))
    }
}
