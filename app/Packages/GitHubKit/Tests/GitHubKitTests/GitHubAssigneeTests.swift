import Foundation
import Testing
import TagwerkCore
@testable import GitHubKit

@MainActor
struct GitHubAssigneeTests {
    let transport = StubTransport()
    let store = MemoryCatalogStore()
    let path = "/repos/beispiel/app/assignees"

    func makeProvider(withStore: Bool = true) -> GitHubTaskProvider {
        let credentials = GitHubCredentials(accessToken: "gho_valid", refreshToken: "ghr", accessExpiresAt: nil, refreshExpiresAt: nil)
        let client = DeviceFlowClient(clientID: "client", transport: transport, sleep: { _ in }, now: { fixedNow })
        let tokens = TokenManager(store: MemoryCredentialStore(credentials), client: client, now: { fixedNow })
        return GitHubTaskProvider(api: GitHubAPI(transport: transport, tokens: tokens), tokens: tokens, cache: MemoryGitHubCache(),
                                  catalogStore: withStore ? store : nil, selectedProjectIDs: { nil }, now: { fixedNow })
    }

    private func item(assignees: [String]?) -> TaskItem {
        TaskItem(id: TaskID(source: .github, rawValue: "I_1"), title: "Issue", notes: nil, due: nil, priority: nil,
                 estimateMinutes: nil, isCompleted: false, container: TaskContainer(id: "beispiel/app", name: "beispiel/app", colorHex: nil),
                 url: nil, version: "1", editableFields: [], assignees: assignees,
                 // A listed issue sits in at least one project.
                 statuses: [SubContainerStatus(subContainerID: "PVT_1", subContainerName: "App", current: "Ready",
                                               options: ["Ready", "Done"], isWritable: true)])
    }

    @Test func assignableUsers_requestsFirstPageOfHundred() async throws {
        transport.enqueueJSON(path, #"[{"login":"octo"},{"login":"lea-m"}]"#)
        let logins = try await makeProvider().api.assignableUsers(repository: "beispiel/app")
        #expect(logins == ["octo", "lea-m"])
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == path)
        #expect(request.url?.query == "per_page=100")
    }

    @Test func assignableUsers_freshCacheSkipsRequest() async {
        store.catalog = GitHubCatalog(repositories: ["beispiel/app"], projects: [], fetchedAt: fixedNow)
        transport.enqueueJSON(path, #"[{"login":"octo"},{"login":"lea-m"}]"#)
        let provider = makeProvider()
        let first = await provider.assignableUsers(in: "beispiel/app", maxAge: 300)
        let second = await provider.assignableUsers(in: "beispiel/app", maxAge: 300)
        #expect(first == ["octo", "lea-m"])
        #expect(second == ["octo", "lea-m"])
        #expect(transport.requests(to: path).count == 1)
    }

    @Test func assignableUsers_expiredCacheRefetchesAndStores() async {
        store.catalog = GitHubCatalog(repositories: ["beispiel/app"], projects: [], fetchedAt: fixedNow)
        transport.enqueueJSON(path, #"[{"login":"octo"}]"#)
        transport.enqueueJSON(path, #"[{"login":"octo"},{"login":"sam"}]"#)
        let provider = makeProvider()
        _ = await provider.assignableUsers(in: "beispiel/app", maxAge: 0)
        let second = await provider.assignableUsers(in: "beispiel/app", maxAge: 0)
        #expect(second == ["octo", "sam"])
        #expect(transport.requests(to: path).count == 2)
        #expect(store.load()?.assignable["beispiel/app"]?.logins == ["octo", "sam"])
        #expect(store.load()?.assignable["beispiel/app"]?.fetchedAt == fixedNow)
    }

    @Test func assignableUsers_failureFallsBackToStoredThenNil() async {
        let old = AssignableUsers(logins: ["octo", "old"], fetchedAt: fixedNow.addingTimeInterval(-3600))
        store.catalog = GitHubCatalog(repositories: ["beispiel/app"], projects: [], fetchedAt: fixedNow,
                                      assignable: ["beispiel/app": old])
        transport.enqueue(path, .failure(.notConnectedToInternet))
        let provider = makeProvider()
        #expect(await provider.assignableUsers(in: "beispiel/app", maxAge: 300) == ["octo", "old"])

        store.catalog = GitHubCatalog(repositories: ["beispiel/app"], projects: [], fetchedAt: fixedNow)
        transport.enqueue(path, .failure(.notConnectedToInternet))
        #expect(await provider.assignableUsers(in: "beispiel/app", maxAge: 300) == nil)
    }

    @Test func assignableUsers_withoutStoredCatalog_returnsWithoutKeeping() async {
        transport.enqueueJSON(path, #"[{"login":"octo"}]"#)
        #expect(await makeProvider().assignableUsers(in: "beispiel/app", maxAge: 300) == ["octo"])
        #expect(store.load() == nil)
    }

    @Test func catalogReload_keepsAssignableOfRemainingRepositories() async {
        let users = AssignableUsers(logins: ["octo"], fetchedAt: fixedNow)
        store.catalog = GitHubCatalog(repositories: ["beispiel/app", "beispiel/alt"], projects: [],
                                      fetchedAt: fixedNow.addingTimeInterval(-301),
                                      assignable: ["beispiel/app": users, "beispiel/alt": users])
        transport.enqueueJSON("/user/repos", #"[{"full_name":"beispiel/app"}]"#)
        transport.enqueueJSON("/graphql", Fixtures.viewerProjects)
        let catalog = await makeProvider().catalog(maxAge: 300)
        #expect(catalog?.assignable.keys.sorted() == ["beispiel/app"])
        #expect(store.load()?.assignable.keys.sorted() == ["beispiel/app"])
    }

    @Test func catalog_decodesStoredJSONWithoutAssignable() throws {
        let json = #"{"repositories":["beispiel/app"],"projects":[],"fetchedAt":0}"#
        let catalog = try JSONDecoder().decode(GitHubCatalog.self, from: Data(json.utf8))
        #expect(catalog.repositories == ["beispiel/app"])
        #expect(catalog.assignable.isEmpty)
    }

    @Test func storedCatalog_readsTheStoreWithoutRequests() {
        store.catalog = GitHubCatalog(repositories: ["beispiel/app"], projects: [], fetchedAt: fixedNow.addingTimeInterval(-9999))
        #expect(makeProvider().storedCatalog?.repositories == ["beispiel/app"])
        #expect(transport.requests.isEmpty)
    }

    @Test func isListed_ignoresCase() async throws {
        Fixtures.enqueueAssignedIssues(on: transport)
        let provider = makeProvider()
        _ = try await provider.openTasks()
        #expect(provider.login == "octo")
        #expect(provider.isListed(item(assignees: ["Octo"])))
        #expect(!provider.isListed(item(assignees: ["lea-m"])))
        #expect(!provider.isListed(item(assignees: [])))
    }

    @Test func isListed_unknownLogin_isTrue() {
        #expect(makeProvider().isListed(item(assignees: ["lea-m"])))
    }
}
