import AIKit
import Foundation
import GitHubKit
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// A `NoteSuggestionModel` with its fakes, for the tests of adjusting and following up on the suggestions of a note
/// (plan ki-vorschlaege-anpassen, tasks C1 and C2).
@MainActor
final class NoteSuggestionFixture {
    final class Clock { var now: Date; init(_ now: Date) { self.now = now } }
    final class Flags { var consent = true; var models = 0 }

    let container: ModelContainer
    let settings: AppSettings
    let calendar = testCalendar()
    let local: FakeTaskProvider
    let taskList: TaskListModel
    let planning: PlanningModel
    let notes: NoteStore
    let responder = NoteSuggestionResponder()
    let tools = NoteSuggestionTools()
    let clock: Clock
    let flags = Flags()

    init() async throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        settings.planCalendarID = "plan"
        let now = Clock(calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 10))!)
        clock = now
        local = FakeTaskProvider(source: .local, tasks: [
            makeTask("Wochenaufgabe", source: .local, due: DueDate(year: 2026, month: 11, day: 24)),
            makeTask("Heute", source: .local, due: DueDate(year: 2026, month: 11, day: 18)),
        ])
        taskList = TaskListModel(providers: [local], now: { now.now }, calendar: calendar)
        await taskList.reload()
        let planStore = PlanStore(context: container.mainContext)
        let calendarStore = FakeCalendarStore()
        let blocks = BlockPlanner(store: calendarStore, planStore: planStore, links: EventLinkStore(context: container.mainContext),
                                  settings: settings, calendar: calendar)
        planning = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: FakeAccessStore(), planStore: planStore,
                                 efforts: RecurringEffortStore(context: container.mainContext), blocks: blocks, settings: settings,
                                 marks: EventMarkStore(context: container.mainContext), now: { now.now }, calendar: calendar)
        await planning.reload()
        notes = NoteStore(context: container.mainContext, now: { now.now })
    }

    /// Two repositories with the same short name in different owners, one of them unique, and two projects.
    func directory() -> FakeGitHubDirectory {
        let tagwerk = ProjectInfo(id: "PVT_T", number: 1, title: "Tagwerk", fields: [], repositories: ["melvinmng/tagwerk"])
        let other = ProjectInfo(id: "PVT_O", number: 2, title: "Sonstiges", fields: [], repositories: [])
        let catalog = GitHubCatalog(repositories: ["melvinmng/tagwerk", "melvinmng/app", "firma/app"], projects: [tagwerk, other],
                                    fetchedAt: Date(timeIntervalSince1970: 0))
        return FakeGitHubDirectory(login: "octo", catalog: catalog,
                                   assignable: ["melvinmng/tagwerk": ["octo", "lea-m"], "melvinmng/app": ["octo"], "firma/app": ["octo"]])
    }

    func makeModel(directory: FakeGitHubDirectory? = nil, withEditors: Bool = true) -> NoteSuggestionModel {
        let flags = self.flags, clock = self.clock, taskList = self.taskList, planning = self.planning
        let calendar = self.calendar
        let context = NoteSuggestionContext.make(taskList: taskList, planning: planning, events: { _ in [] }, planCalendarID: "plan", now: clock.now)
        let describer = ActionCardDescriber(planning: planning, gitHubDirectory: { directory })
        var editorContext: (@MainActor () -> ProposalEditorContext)?
        if withEditors {
            editorContext = { ProposalEditorContext(calendar: calendar, now: { clock.now }, gitHubDirectory: { directory }) }
        }
        let github: @MainActor () -> (any GitHubDirectory)? = { directory }
        return NoteSuggestionModel(
            responder: responder, model: { flags.models += 1; return "gpt-test" }, tools: tools, describer: describer, notes: notes,
            hasConsent: { flags.consent }, context: { context }, now: { clock.now }, gitHubDirectory: github,
            editorContext: editorContext)
    }

    func note(_ text: String = "Zahnarzt anrufen, Export prüfen", kind: NoteKind = .evening) -> NoteRecord {
        notes.create(text: text, kind: kind, dayKey: "2026-11-18")!
    }

    /// Fetches cards from a scripted answer; each entry is (call id, function name, arguments JSON).
    func fetched(_ calls: [(String, String, String)], directory: FakeGitHubDirectory? = nil,
                 withEditors: Bool = true) async -> (model: NoteSuggestionModel, note: NoteRecord) {
        let record = note()
        responder.enqueue(calls.map { ($0.0, "\($0.1)|\($0.2)") })
        let model = makeModel(directory: directory, withEditors: withEditors)
        await model.fetch(noteID: record.id, text: record.text, kind: .evening)
        return (model, record)
    }

    func arguments(of call: ToolCall) -> [String: Any] {
        ProposalArguments.decode(call.arguments) ?? [:]
    }

    /// The user message of a request that was sent.
    func requestText(_ index: Int) -> String {
        responder.sent[index].input.compactMap { item -> String? in if case .user(let text) = item { text } else { nil } }.joined(separator: "\n")
    }
}
