import Foundation
import Testing
import TagwerkCore
@testable import GitHubKit

/// Fixture project with six status stages in board order (not alphabetical).
func makeBoardProject(_ number: Int = 1, stages: [String] = ["Backlog", "Ready", "In progress", "Blocked", "In review", "Done"],
                      canWrite: Bool = true) -> ProjectInfo {
    ProjectInfo(
        id: "PVT_\(number)", number: number, title: "Projekt \(number)",
        fields: [
            ProjectField(id: "F_\(number)_status", name: "Status",
                         orderedOptions: stages.enumerated().map { ProjectFieldOption(id: "OPT_\(number)_\($0.offset)", name: $0.element) }),
            ProjectField(id: "F_\(number)_due", name: "Due date", options: [:]),
        ],
        canWrite: canWrite
    )
}

struct GitHubStatusOptionsTests {
    @Test func orderedOptions_keepBoardOrder_andDictionaryIsDerived() throws {
        let project = makeBoardProject()
        let status = try #require(project.field(named: "Status"))
        #expect(status.orderedOptions.map(\.name) == ["Backlog", "Ready", "In progress", "Blocked", "In review", "Done"])
        #expect(status.options["In progress"] == "OPT_1_2")
        #expect(status.options.count == 6)
    }

    @Test func legacyInit_ordersByName() {
        let field = ProjectField(id: "F", name: "Status", options: ["Ready": "A", "Done": "B", "Blocked": "C"])
        #expect(field.orderedOptions.map(\.name) == ["Blocked", "Done", "Ready"])
        #expect(field.options == ["Ready": "A", "Done": "B", "Blocked": "C"])
    }

    @Test func decoding_oldCacheWithoutOrder_fallsBackToNameOrder() throws {
        let json = #"{"id":"F","name":"Status","options":{"Ready":"OPT_ready","Done":"OPT_done"}}"#
        let field = try JSONDecoder().decode(ProjectField.self, from: Data(json.utf8))
        #expect(field.orderedOptions.map(\.name) == ["Done", "Ready"])
        #expect(field.options["Ready"] == "OPT_ready")
    }

    @Test func decoding_oldProjectInfoCache_stillDecodes() throws {
        let json = """
        {"id":"PVT_1","number":1,"title":"App","fields":[{"id":"F","name":"Status","options":{"Ready":"R","Done":"D"}}]}
        """
        let project = try JSONDecoder().decode(ProjectInfo.self, from: Data(json.utf8))
        #expect(project.field(named: "Status")?.orderedOptions.map(\.name) == ["Done", "Ready"])
        #expect(project.canWrite)
    }

    @Test func roundTrip_keepsOrderNotAlphabetical() throws {
        let project = makeBoardProject()
        let decoded = try JSONDecoder().decode(ProjectInfo.self, from: JSONEncoder().encode(project))
        #expect(decoded == project)
        #expect(decoded.field(named: "Status")?.orderedOptions.map(\.name).first == "Backlog")
    }

    @Test func graphQLReading_keepsOptionOrderOfTheBoard() async throws {
        let transport = StubTransport()
        let credentials = GitHubCredentials(accessToken: "gho_valid", refreshToken: "ghr", accessExpiresAt: nil, refreshExpiresAt: nil)
        let client = DeviceFlowClient(clientID: "client", transport: transport, sleep: { _ in }, now: { fixedNow })
        let tokens = TokenManager(store: MemoryCredentialStore(credentials), client: client, now: { fixedNow })
        let api = GitHubAPI(transport: transport, tokens: tokens)
        transport.enqueueJSON("/graphql", Fixtures.viewerProjectsJSON(statusOptions: ["Backlog", "Ready", "In progress", "Blocked", "In review", "Done"]))
        let result = try await api.viewerProjects()
        let status = try #require(result.projects.first?.field(named: "Status"))
        #expect(status.orderedOptions.map(\.name) == ["Backlog", "Ready", "In progress", "Blocked", "In review", "Done"])
    }

    @Test func duplicateOptionNames_keepFirst() {
        let field = ProjectField(id: "F", name: "Status",
                                 orderedOptions: [ProjectFieldOption(id: "1", name: "Ready"), ProjectFieldOption(id: "2", name: "Ready")])
        #expect(field.orderedOptions.count == 1)
        #expect(field.options["Ready"] == "1")
    }

    // MARK: Done and reopen option resolution

    @Test func doneOption_matchesCaseInsensitively() {
        let project = makeBoardProject(stages: ["Todo", "DONE"])
        #expect(GitHubMapping.doneOption(in: project) == "DONE")
        #expect(GitHubMapping.doneOption(in: makeBoardProject(stages: ["Todo", "Closed"])) == nil)
        #expect(GitHubMapping.isDone("done"))
        #expect(!GitHubMapping.isDone("In review"))
        #expect(!GitHubMapping.isDone(nil))
    }

    @Test func reopenOption_prefersReady() {
        #expect(GitHubMapping.reopenOption(in: makeBoardProject()) == "Ready")
        #expect(GitHubMapping.reopenOption(in: makeBoardProject(stages: ["Backlog", "ready", "Done"])) == "ready")
    }

    @Test func reopenOption_withoutReady_isFirstNonDoneInBoardOrder() {
        #expect(GitHubMapping.reopenOption(in: makeBoardProject(stages: ["Done", "Todo", "Doing"])) == "Todo")
        #expect(GitHubMapping.reopenOption(in: makeBoardProject(stages: ["Done"])) == nil)
        #expect(GitHubMapping.reopenOption(in: makeProject(1, fields: ["Due date"])) == nil)
    }

    @Test func statusOptions_areTheBoardOrder() {
        #expect(GitHubMapping.statusOptions(in: makeBoardProject()) == ["Backlog", "Ready", "In progress", "Blocked", "In review", "Done"])
    }
}
