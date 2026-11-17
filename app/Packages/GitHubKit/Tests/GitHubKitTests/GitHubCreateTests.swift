import Foundation
import Testing
import TagwerkCore
@testable import GitHubKit

@MainActor
struct GitHubCreateTests {
    let transport = StubTransport()

    func makeProvider() -> GitHubTaskProvider {
        let credentials = GitHubCredentials(accessToken: "gho_valid", refreshToken: "ghr", accessExpiresAt: nil, refreshExpiresAt: nil)
        let client = DeviceFlowClient(clientID: "client", transport: transport, sleep: { _ in }, now: { fixedNow })
        let tokens = TokenManager(store: MemoryCredentialStore(credentials), client: client, now: { fixedNow })
        return GitHubTaskProvider(api: GitHubAPI(transport: transport, tokens: tokens), tokens: tokens, cache: MemoryGitHubCache(),
                                  selectedProjectIDs: { nil }, now: { fixedNow })
    }

    private func draft() -> TaskDraft {
        TaskDraft(title: "Tests für Export", notes: "Details", due: DueDate(year: 2026, month: 11, day: 27),
                  priority: .p2, estimateMinutes: 120, containerID: "beispiel/app", subContainerID: "PVT_1")
    }

    private func enqueueCreateFlow() {
        transport.enqueueJSON("/graphql", Fixtures.viewerProjects)
        transport.enqueueJSON("/repos/beispiel/app/issues", status: 201, #"{"id":7,"node_id":"I_new","number":7}"#)
        transport.enqueueJSON("/graphql", #"{"data":{"addProjectV2ItemById":{"item":{"id":"PVTI_new"}}}}"#)
        for _ in 0..<4 { transport.enqueueJSON("/graphql", Fixtures.mutationOK) }
        transport.enqueueJSON("/graphql", Fixtures.issue())
    }

    @Test func create_postsIssueAssignedToViewer() async throws {
        enqueueCreateFlow()
        _ = try await makeProvider().create(draft())
        let post = try #require(transport.requests.first { $0.httpMethod == "POST" && $0.url?.path == "/repos/beispiel/app/issues" })
        let json = try #require(try JSONSerialization.jsonObject(with: post.httpBody ?? Data()) as? [String: Any])
        #expect(json["title"] as? String == "Tests für Export")
        #expect(json["body"] as? String == "Details")
        #expect(json["assignees"] as? [String] == ["octo"])
    }

    @Test func create_addsToProjectThenSetsFields() async throws {
        enqueueCreateFlow()
        let item = try await makeProvider().create(draft())

        let steps = transport.requests.map { request -> String in
            let body = request.bodyString
            if request.httpMethod == "POST", request.url?.path.hasPrefix("/repos") == true { return "createIssue" }
            if body.contains("addProjectV2ItemById") { return "addToProject" }
            if body.contains("updateProjectV2ItemFieldValue") {
                if body.contains("F_due") { return "due" }
                if body.contains("F_prio") { return "priority" }
                if body.contains("F_est") { return "estimate" }
                if body.contains("F_status") { return "status" }
            }
            if body.contains("projectItems") { return "read" }
            if body.contains("viewer") { return "viewer" }
            return "other"
        }
        #expect(steps == ["viewer", "createIssue", "addToProject", "due", "priority", "estimate", "status", "read"])
        let add = try #require(transport.requests.first { $0.bodyString.contains("addProjectV2ItemById") })
        #expect(add.bodyString.contains("PVT_1") && add.bodyString.contains("I_new"))
        let estimate = try #require(transport.requests.first { $0.bodyString.contains("F_est") })
        #expect(estimate.bodyString.contains(#""number":2"#))
        let status = try #require(transport.requests.first { $0.bodyString.contains("F_status") })
        #expect(status.bodyString.contains("OPT_ready"))
        #expect(item.id == TaskID(source: .github, rawValue: "I_1"))
    }

    @Test func create_withoutProject_throwsFailed() async {
        var incomplete = draft()
        incomplete.subContainerID = nil
        await #expect(throws: TaskWriteError.self) { try await makeProvider().create(incomplete) }
        #expect(transport.requests.isEmpty)
    }

    @Test func create_offline_throwsOffline() async {
        transport.enqueue("/graphql", .failure(.notConnectedToInternet))
        await #expect(throws: TaskWriteError.offline) { try await makeProvider().create(draft()) }
    }

    @Test func ownedRepositories_readsFullNames() async throws {
        transport.enqueueJSON("/user/repos", #"[{"full_name":"beispiel/app"},{"full_name":"beispiel/web"}]"#)
        let provider = makeProvider()
        let repos = try await provider.api.ownedRepositories()
        #expect(repos == ["beispiel/app", "beispiel/web"])
        let query = try #require(transport.requests.first?.url?.query)
        #expect(query.contains("affiliation=owner") && query.contains("sort=pushed") && query.contains("per_page=100"))
    }
}
