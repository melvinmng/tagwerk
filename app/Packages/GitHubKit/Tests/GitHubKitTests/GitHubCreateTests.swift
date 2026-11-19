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
                  priority: .p2, estimateMinutes: 120, containerID: "beispiel/app", subContainerIDs: ["PVT_1"])
    }

    private func enqueueCreateFlow(assignees: [String] = ["octo"]) {
        transport.enqueueJSON("/graphql", Fixtures.viewerProjects)
        transport.enqueueJSON("/repos/beispiel/app/issues", status: 201, #"{"id":7,"node_id":"I_new","number":7}"#)
        transport.enqueueJSON("/graphql", #"{"data":{"addProjectV2ItemById":{"item":{"id":"PVTI_new"}}}}"#)
        for _ in 0..<4 { transport.enqueueJSON("/graphql", Fixtures.mutationOK) }
        transport.enqueueJSON("/graphql", Fixtures.issue(assignees: assignees))
    }

    /// The `assignees` array of the issue POST.
    private func postedAssignees() throws -> [String]? {
        let post = try #require(transport.requests.first { $0.httpMethod == "POST" && $0.url?.path == "/repos/beispiel/app/issues" })
        let json = try #require(try JSONSerialization.jsonObject(with: post.httpBody ?? Data()) as? [String: Any])
        return json["assignees"] as? [String]
    }

    @Test func create_sendsChosenAssignees() async throws {
        enqueueCreateFlow(assignees: ["octo", "lea-m"])
        var chosen = draft()
        chosen.assignees = ["octo", "lea-m"]
        let item = try await makeProvider().create(chosen)
        #expect(try postedAssignees() == ["octo", "lea-m"])
        #expect(item.assignees == ["octo", "lea-m"])
    }

    @Test func create_emptyAssignees_sendsEmptyList() async throws {
        enqueueCreateFlow(assignees: [])
        var chosen = draft()
        chosen.assignees = []
        _ = try await makeProvider().create(chosen)
        #expect(try postedAssignees() == [])
    }

    @Test func create_moreThanTen_failsBeforeAnyRequest() async {
        var chosen = draft()
        chosen.assignees = (1...11).map { "user-\($0)" }
        await #expect(throws: TaskWriteError.failed("Höchstens 10 Personen je Issue.")) {
            try await makeProvider().create(chosen)
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func create_forOthersOnly_isNotRemembered() async throws {
        enqueueCreateFlow(assignees: ["lea-m"])
        var chosen = draft()
        chosen.assignees = ["lea-m"]
        let provider = makeProvider()
        let item = try await provider.create(chosen)
        #expect(item.assignees == ["lea-m"])
        #expect(provider.cachedTasks.isEmpty)
        #expect(provider.issueReference(for: item.id) == nil)
    }

    @Test func create_forMe_isRemembered() async throws {
        enqueueCreateFlow()
        let provider = makeProvider()
        let item = try await provider.create(draft())
        #expect(provider.issueReference(for: item.id) != nil)
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
        incomplete.subContainerIDs = []
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

    @Test func create_inTwoProjects_addsToBothAndSetsFieldsInEach() async throws {
        transport.enqueueJSON("/graphql", Fixtures.viewerProjects)
        transport.enqueueJSON("/repos/beispiel/app/issues", status: 201, #"{"id":7,"node_id":"I_new","number":7}"#)
        transport.enqueueJSON("/graphql", #"{"data":{"addProjectV2ItemById":{"item":{"id":"PVTI_new1"}}}}"#)
        for _ in 0..<4 { transport.enqueueJSON("/graphql", Fixtures.mutationOK) }
        transport.enqueueJSON("/graphql", #"{"data":{"addProjectV2ItemById":{"item":{"id":"PVTI_new2"}}}}"#)
        for _ in 0..<3 { transport.enqueueJSON("/graphql", Fixtures.mutationOK) }
        transport.enqueueJSON("/graphql", Fixtures.issue())

        var twoProjects = draft()
        twoProjects.subContainerIDs = ["PVT_1", "PVT_2"]
        _ = try await makeProvider().create(twoProjects)

        let adds = transport.requests.filter { $0.bodyString.contains("addProjectV2ItemById") }
        #expect(adds.count == 1 + 1)
        #expect(adds[0].bodyString.contains("PVT_1") && adds[1].bodyString.contains("PVT_2"))
        #expect(transport.requests.filter { $0.httpMethod == "POST" && $0.url?.path == "/repos/beispiel/app/issues" }.count == 1)
        #expect(transport.requests.contains { $0.bodyString.contains("F2_due") })
        #expect(transport.requests.contains { $0.bodyString.contains("F2_status") && $0.bodyString.contains("OPT2_ready") })
    }
}

/// Repositories, projects and their links, cached for the "new issue" sheet.
@MainActor
final class MemoryCatalogStore: GitHubCatalogStore {
    var catalog: GitHubCatalog?
    func load() -> GitHubCatalog? { catalog }
    func store(_ catalog: GitHubCatalog) { self.catalog = catalog }
}

@MainActor
struct GitHubCatalogTests {
    let transport = StubTransport()
    let store = MemoryCatalogStore()

    func makeProvider(now: Date = fixedNow) -> GitHubTaskProvider {
        let credentials = GitHubCredentials(accessToken: "gho_valid", refreshToken: "ghr", accessExpiresAt: nil, refreshExpiresAt: nil)
        let client = DeviceFlowClient(clientID: "client", transport: transport, sleep: { _ in }, now: { now })
        let tokens = TokenManager(store: MemoryCredentialStore(credentials), client: client, now: { now })
        return GitHubTaskProvider(api: GitHubAPI(transport: transport, tokens: tokens), tokens: tokens, cache: MemoryGitHubCache(),
                                  catalogStore: store, selectedProjectIDs: { nil }, now: { now })
    }

    private func enqueueCatalog() {
        transport.enqueueJSON("/user/repos", #"[{"full_name":"beispiel/app"},{"full_name":"beispiel/studium"}]"#)
        transport.enqueueJSON("/graphql", Fixtures.viewerProjects)
    }

    @Test func catalog_fetchesReposProjectsAndLinks() async throws {
        enqueueCatalog()
        let catalog = try #require(await makeProvider().catalog(maxAge: 300))
        #expect(catalog.repositories == ["beispiel/app", "beispiel/studium"])
        #expect(catalog.projectIDs(linkedTo: "beispiel/app") == ["PVT_1", "PVT_2"])
        #expect(catalog.projectIDs(linkedTo: "beispiel/studium") == ["PVT_2"])
        #expect(catalog.projectIDs(linkedTo: "beispiel/other").isEmpty)
        #expect(store.catalog == catalog)
    }

    @Test func catalog_fresh_usesStoreWithoutRequests() async throws {
        store.catalog = GitHubCatalog(repositories: ["beispiel/app"], projects: [], fetchedAt: fixedNow.addingTimeInterval(-60))
        let catalog = await makeProvider().catalog(maxAge: 300)
        #expect(catalog?.repositories == ["beispiel/app"])
        #expect(transport.requests.isEmpty)
    }

    @Test func catalog_stale_refetches() async throws {
        store.catalog = GitHubCatalog(repositories: ["alt/repo"], projects: [], fetchedAt: fixedNow.addingTimeInterval(-301))
        enqueueCatalog()
        let catalog = await makeProvider().catalog(maxAge: 300)
        #expect(catalog?.repositories == ["beispiel/app", "beispiel/studium"])
        #expect(catalog?.fetchedAt == fixedNow)
    }

    @Test func catalog_offline_returnsStoredCatalog() async throws {
        store.catalog = GitHubCatalog(repositories: ["alt/repo"], projects: [], fetchedAt: fixedNow.addingTimeInterval(-3600))
        transport.enqueue("/user/repos", .failure(.notConnectedToInternet))
        let catalog = await makeProvider().catalog(maxAge: 300)
        #expect(catalog?.repositories == ["alt/repo"])
    }

    @Test func projectInfo_withoutRepositories_decodesFromOldCache() throws {
        let json = #"{"id":"PVT_1","number":1,"title":"App","fields":[]}"#
        let info = try JSONDecoder().decode(ProjectInfo.self, from: Data(json.utf8))
        #expect(info.repositories.isEmpty)
        #expect(info.canWrite)
    }
}
