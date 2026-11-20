import AIKit
import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// Cards of `assign_task` (issue #173, decision 1/2): what changes, and what a hand-over costs.
@MainActor
struct ActionCardDescriberTests {
    let container: ModelContainer
    let settings: AppSettings
    let calendarStore = FakeCalendarStore()
    let github = FakeTaskProvider(source: .github)
    let directory = FakeGitHubDirectory.single()
    let taskList: TaskListModel
    let calendar = testCalendar()

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        settings.planCalendarID = "plan"
        github.viewerLogin = "octo"
        taskList = TaskListModel(providers: [github], now: testNow, calendar: calendar)
    }

    private func issue(_ number: Int, assignees: [String]) -> TaskItem {
        TaskItem(id: TaskID(source: .github, rawValue: "ISSUE_\(number)"), title: "Export \(number)", notes: nil, due: nil,
                 priority: nil, estimateMinutes: nil, isCompleted: false,
                 container: TaskContainer(id: "beispiel/app", name: "beispiel/app", colorHex: nil),
                 url: URL(string: "https://github.com/beispiel/app/issues/\(number)"), version: "1",
                 editableFields: [.title, .notes, .due, .priority, .assignees], assignees: assignees)
    }

    private func make(issues: [TaskItem]) async -> (ActionCardDescriber, BlockPlanner) {
        github.tasks = issues
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
        return (ActionCardDescriber(planning: planning, gitHubDirectory: { directory }), blocks)
    }

    private func call(_ id: String, add: [String] = [], remove: [String] = []) -> ToolCall {
        func json(_ values: [String]) -> String {
            String(decoding: try! JSONSerialization.data(withJSONObject: values), as: UTF8.self)
        }
        return ToolCall(id: "c1", name: "assign_task", arguments: Data(#"{"id":"\#(id)","add":\#(json(add)),"remove":\#(json(remove))}"#.utf8))
    }

    private func at(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    @Test func describe_assignTask_addsPerson() async {
        let task = issue(212, assignees: ["octo"])
        let (describer, _) = await make(issues: [task])
        let card = describer.describe(call(task.id.key, add: ["lea-m"]))
        #expect(card.title == "Export 212")
        #expect(card.change == "Zugewiesen: dir → dir und lea-m")
        #expect(card.warning == nil)
        #expect(card.confirmTitle == nil)
        #expect(!card.isDestructive)
    }

    @Test func describe_assignTask_handOver_namesFutureBlocks() async throws {
        let task = issue(212, assignees: ["octo"])
        let (describer, blocks) = await make(issues: [task])
        _ = try blocks.createBlock(for: task, start: at(17, 9), minutes: 60)   // past: not counted
        _ = try blocks.createBlock(for: task, start: at(19, 9), minutes: 60)
        _ = try blocks.createBlock(for: task, start: at(20, 9), minutes: 60)
        let card = describer.describe(call(task.id.key, add: ["lea-m"], remove: ["octo"]))
        #expect(card.change == "Zugewiesen: dir → lea-m (nicht mehr dir)")
        #expect(card.warning == "#212 verschwindet aus Aufgaben und Planung. 2 geplante Zeitblöcke werden gelöscht.")
        #expect(card.confirmTitle == "Abgeben")
        #expect(card.isDestructive)
    }

    @Test func describe_assignTask_leavesUnassigned() async {
        let task = issue(212, assignees: ["octo"])
        let (describer, _) = await make(issues: [task])
        let card = describer.describe(call(task.id.key, remove: ["octo"]))
        #expect(card.change == "Zugewiesen: dir → niemand")
        #expect(card.warning?.hasSuffix("Das Issue ist dann niemandem zugewiesen.") == true)
        #expect(card.confirmTitle == "Abgeben")
        #expect(card.isDestructive)
    }

    @Test func describe_assignTask_unknownState_listsTheChange() async {
        let (describer, _) = await make(issues: [])
        let card = describer.describe(call("github:GONE", add: ["lea-m"], remove: ["octo"]))
        #expect(card.change == "Zuweisung ändern: ＋ lea-m · − dir")
        #expect(card.warning == nil)
        #expect(card.confirmTitle == nil)
    }

    @Test func describe_assignTask_spoken_avoidsSymbols() async {
        let task = issue(212, assignees: ["octo"])
        let (describer, _) = await make(issues: [task])
        let card = describer.describe(call(task.id.key, add: ["lea-m"], remove: ["octo"]), spoken: true)
        #expect(card.change.hasPrefix("Zuweisung ändern: lea-m dazu, du nicht mehr"))
        #expect(!card.change.contains("→") && !card.change.contains("＋") && !card.change.contains("−"))
        // The consequences are spoken as well: by voice the card is the only place that names them.
        #expect(card.change.contains("verschwindet aus Aufgaben und Planung"))
    }

    @Test func describe_assignTask_inEnglish() async {
        let task = issue(212, assignees: ["octo"])
        let (describer, _) = await make(issues: [task])
        let card = describer.describe(call(task.id.key, add: ["lea-m"]), language: .english)
        #expect(card.change == "Assigned: you → you and lea-m")
    }

    @Test func describe_assignTask_unlistedIssue_showsNumberAndRepository() async {
        let (describer, _) = await make(issues: [])
        let online = OnlineIssue(id: "ISSUE_151", number: 151, title: "Export prüfen", repository: "beispiel/app",
                                 url: URL(string: "https://github.com/beispiel/app/issues/151")!, updatedAt: testNow(),
                                 marker: .unassigned, assignees: [])
        var withFound = describer
        withFound.foundIssue = { $0 == "github:ISSUE_151" ? online : nil }
        let card = withFound.describe(call("github:ISSUE_151", add: ["octo"]))
        #expect(card.title == "Export prüfen")
        #expect(card.change == "beispiel/app #151\nZugewiesen: niemand → dir")
        // Nothing is planned for an issue outside the lists: no consequences, no red button.
        #expect(card.warning == nil && card.confirmTitle == nil && !card.isDestructive)
        let spoken = withFound.describe(call("github:ISSUE_151", add: ["octo"]), spoken: true)
        #expect(spoken.change == "beispiel/app #151. Zuweisung ändern: du dazu")
        // Taking someone else away from it names who is assigned afterwards.
        var others = withFound
        others.foundIssue = { _ in
            OnlineIssue(id: "ISSUE_151", number: 151, title: "Export prüfen", repository: "beispiel/app",
                        url: online.url, updatedAt: testNow(), marker: .assignedToOthers, assignees: ["max"])
        }
        #expect(others.describe(call("github:ISSUE_151", add: ["lea-m"], remove: ["max"])).change
                == "beispiel/app #151\nZugewiesen: max → lea-m")
    }
}

