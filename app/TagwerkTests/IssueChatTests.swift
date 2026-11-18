import AIKit
import Foundation
import GitHubKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct IssueChatTests {
    let reader = FakeRepositoryReader()
    let reference = IssueReference(repository: "beispiel/app", number: 42, nodeID: "I_42")

    func makeTools() async throws -> (TaskChatTools, TaskListModel) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let settings = try AppSettings.current(in: container.mainContext)
        let calendarStore = FakeCalendarStore()
        let github = FakeTaskProvider(source: .github, tasks: [makeTask("I_42", source: .github)])
        let taskList = TaskListModel(providers: [github], now: testNow, calendar: testCalendar())
        await taskList.reload()
        let planStore = PlanStore(context: container.mainContext)
        let blocks = BlockPlanner(store: calendarStore, planStore: planStore, links: EventLinkStore(context: container.mainContext),
                                  settings: settings, calendar: testCalendar())
        let planning = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: FakeAccessStore(),
                                     planStore: planStore, efforts: RecurringEffortStore(context: container.mainContext),
                                     blocks: blocks, settings: settings, marks: EventMarkStore(context: container.mainContext),
                                     now: testNow, calendar: testCalendar())
        let base = AppTools(taskList: taskList, planning: planning, planner: nil, events: { _ in [] })
        return (TaskChatTools(base: base, reader: reader, reference: reference), taskList)
    }

    func run(_ tools: TaskChatTools, _ name: String, _ arguments: String) async -> String {
        await tools.run(ToolCall(id: "c", name: name, arguments: Data(arguments.utf8)))
    }

    @Test func repoTools_areReadOnly_andOfferedOnlyWithIssue() async throws {
        let (tools, _) = try await makeTools()
        let names = Set(tools.definitions.map(\.name))
        #expect(names.isSuperset(of: ["get_issue_comments", "get_repository_readme", "get_repository_file",
                                      "search_repository", "get_pull_request", "complete_task"]))
        for name in TaskChatTools.repositoryTools { #expect(tools.kind(of: name) == .read) }
        let withoutIssue = TaskChatTools(base: tools.base, reader: reader, reference: nil)
        #expect(!withoutIssue.definitions.contains { $0.name == "get_repository_readme" })
    }

    @Test func repoTools_otherRepository_rejected() async throws {
        let (tools, _) = try await makeTools()
        // The schemas have no repository argument; a smuggled one is ignored.
        for definition in tools.definitions where TaskChatTools.repositoryTools.contains(definition.name) {
            let schema = try #require(try JSONSerialization.jsonObject(with: definition.parameters) as? [String: Any])
            let keys = (schema["properties"] as? [String: Any])?.keys.map { $0 } ?? []
            #expect(!keys.contains { $0.contains("repo") || $0.contains("owner") }, "\(definition.name)")
        }
        let output = await run(tools, "get_repository_file", #"{"path":"README.md","repository":"evil/other"}"#)
        #expect(output.contains("Inhalt von README.md"))
        #expect(reader.requestedRepositories == ["beispiel/app"])
    }

    @Test func readme_andSearch_returnContent() async throws {
        let (tools, _) = try await makeTools()
        #expect(await run(tools, "get_repository_readme", "{}").contains("# Projekt"))
        #expect(await run(tools, "search_repository", #"{"query":"Login"}"#).contains("Sources/Login.swift"))
        #expect(await run(tools, "get_pull_request", #"{"number":7}"#).contains("\"title\":\"Fix\""))
    }

    @Test func issueContext_includesCommentsLabelsFieldsNeighbours() async throws {
        let (_, taskList) = try await makeTools()
        var task = try #require(taskList.items.first)
        task.labels = ["frontend"]
        task.subContainers = [TaskContainer(id: "P1", name: "Tagwerk", colorHex: nil)]
        task.notes = "Login schlägt fehl."
        let context = await IssueContext.load(task: task, reference: reference, reader: reader)
        #expect(context.contains("#42"))
        #expect(context.contains("Login schlägt fehl."))
        #expect(context.contains("frontend"))
        #expect(context.contains("Tagwerk"))
        #expect(context.contains("anna: Sieht gut aus."))
        #expect(context.contains("Epic #2"))
        #expect(context.contains("#41 Nachbar"))
        #expect(context.contains("README, Dateien, Suche und Pull Requests"))
    }
}
