import Foundation
import Testing
import TagwerkCore
@testable import GitHubKit

@MainActor
struct IssueSearchTests {
    let transport = StubTransport()

    private func makeAPI(credentials: GitHubCredentials? = GitHubCredentials(
        accessToken: "gho_valid", refreshToken: "ghr", accessExpiresAt: nil, refreshExpiresAt: nil)) -> (GitHubAPI, TokenManager) {
        let client = DeviceFlowClient(clientID: "client", transport: transport, sleep: { _ in }, now: { fixedNow })
        let tokens = TokenManager(store: MemoryCredentialStore(credentials), client: client, now: { fixedNow })
        return (GitHubAPI(transport: transport, tokens: tokens), tokens)
    }

    @Test func queryListsAtMostThirtyRepositories() {
        let repos = (1...40).map { "octo/r\($0)" }
        let query = IssueSearchQuery.make(text: "login", repositories: repos, login: "octo")
        #expect(query.hasPrefix("is:issue login repo:octo/r1 "))
        #expect(query.components(separatedBy: "repo:").count - 1 == 30)
        #expect(!query.contains("octo/r31"))
        #expect(IssueSearchQuery.make(text: "login", repositories: [], login: "octo") == "is:issue login user:octo")
    }

    @Test func ownerFallbackNamesEachOwnerOnce() {
        let query = IssueSearchQuery.makeByOwner(text: "login", repositories: ["octo/a", "acme/b", "acme/c"], login: "octo")
        #expect(query == "is:issue login user:octo org:acme")
    }

    @Test func searchTextTravelsAsVariable() async throws {
        transport.enqueueJSON("/graphql", Fixtures.searchResponse([]))
        _ = try await makeAPI().0.searchIssues(text: "\"offen repo:x/y", repositories: ["octo/a"], login: "octo")
        let body = try #require(transport.requests.last?.bodyString)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        #expect((json["variables"] as? [String: Any])?["query"] as? String == "is:issue \"offen repo:x/y repo:octo/a")
        let document = try #require(json["query"] as? String)
        #expect(!document.contains("offen"))
        #expect(document.contains("first: 20"))
    }

    @Test func hitsDecodeWithoutProjectsAndAssignees() async throws {
        transport.enqueueJSON("/graphql", Fixtures.searchResponse([Fixtures.searchNode(id: "I_9", number: 9, state: "CLOSED")]))
        let hits = try await makeAPI().0.searchIssues(text: "issue", repositories: [], login: "octo")
        let hit = try #require(hits.first)
        #expect(hit.record.issueID == "I_9" && !hit.record.isOpen && hit.record.assignees.isEmpty)
        #expect(hit.record.placements.isEmpty)
        #expect(!hit.hasOpenProject)
    }

    @Test func archivedItemsAndClosedProjectsDoNotCount() async throws {
        let archived = #"{"isArchived":true,"project":{"closed":false}}"#
        let closedProject = #"{"isArchived":false,"project":{"closed":true}}"#
        let open = #"{"isArchived":false,"project":{"closed":false}}"#
        transport.enqueueJSON("/graphql", Fixtures.searchResponse([
            Fixtures.searchNode(id: "I_1", number: 1, items: [archived, closedProject]),
            Fixtures.searchNode(id: "I_2", number: 2, items: [archived, open]),
        ]))
        let hits = try await makeAPI().0.searchIssues(text: "issue", repositories: [], login: "octo")
        #expect(hits.map(\.hasOpenProject) == [false, true])
    }

    @Test func errorsMapToSearchErrors() async {
        func error(_ reply: StubTransport.Reply?, credentials: GitHubCredentials? = GitHubCredentials(
            accessToken: "gho_valid", refreshToken: "ghr", accessExpiresAt: nil, refreshExpiresAt: nil)) async -> IssueSearchError? {
            let stub = StubTransport()
            if let reply { stub.enqueue("/graphql", reply) }
            let client = DeviceFlowClient(clientID: "client", transport: stub, sleep: { _ in }, now: { fixedNow })
            let tokens = TokenManager(store: MemoryCredentialStore(credentials), client: client, now: { fixedNow })
            do {
                _ = try await GitHubAPI(transport: stub, tokens: tokens).searchIssues(text: "x", repositories: [], login: "octo")
                return nil
            } catch {
                return error as? IssueSearchError
            }
        }
        #expect(await error(.failure(.notConnectedToInternet)) == .offline)
        #expect(await error(.json(403, "{}")) == .rateLimited)
        #expect(await error(.json(429, "{}")) == .rateLimited)
        #expect(await error(.json(200, #"{"errors":[{"message":"API rate limit exceeded for user"}]}"#)) == .rateLimited)
        #expect(await error(nil, credentials: nil) == .signedOut)
        if case .failed? = await error(.json(500, "{}")) {} else { Issue.record("HTTP 500 must map to .failed") }
        if case .failed(let message)? = await error(.json(200, #"{"errors":[{"message":"Problem parsing query"}]}"#)) {
            #expect(message == "Problem parsing query")
        } else { Issue.record("a GraphQL error must map to .failed") }
    }

    /// A provider with a stored catalog, so the search needs no request for repositories.
    private func makeProvider() -> GitHubTaskProvider {
        let (api, tokens) = makeAPI()
        let store = MemoryCatalogStore()
        let project = ProjectInfo(id: "PVT_1", number: 1, title: "App", fields: [], repositories: ["beispiel/app"])
        store.store(GitHubCatalog(repositories: ["octo/owned", "beispiel/app"], projects: [project], fetchedAt: fixedNow))
        return GitHubTaskProvider(api: api, tokens: tokens, cache: MemoryGitHubCache(), catalogStore: store,
                                  selectedProjectIDs: { nil }, now: { fixedNow })
    }

    @Test func providerDropsLoadedIssuesAndSetsMarkers() async throws {
        let open = #"{"isArchived":false,"project":{"closed":false}}"#
        transport.enqueueJSON("/graphql", Fixtures.viewerProjects)     // the own login: not known before the first load
        transport.enqueueJSON("/graphql", Fixtures.searchResponse([
            Fixtures.searchNode(id: "I_1", number: 1, assignees: ["octo"], items: [open]),   // loaded already
            Fixtures.searchNode(id: "I_9", number: 9, state: "CLOSED"),
            Fixtures.searchNode(id: "I_8", number: 8, assignees: ["lea-m"], items: [open]),
            Fixtures.searchNode(id: "I_7", number: 7, assignees: ["octo"]),
            Fixtures.searchNode(id: "I_6", number: 6, items: [open]),
            Fixtures.searchNode(id: "I_5", number: 5, assignees: ["octo"], items: [open]),
        ]))
        let hits = try await makeProvider().searchOnline("issue", excluding: ["I_1"])
        #expect(hits.map(\.id) == ["I_9", "I_8", "I_7", "I_6", "I_5"])                // order as delivered
        #expect(hits.map(\.marker) == [.closed, .assignedToOthers, .noProject, .unassigned, nil])
        #expect(hits.first?.repository == "octo/r" && hits.first?.number == 9)
    }

    @Test func providerSearchesTheRepositoriesOfProjectsAndTheCatalog() async throws {
        transport.enqueueJSON("/graphql", Fixtures.viewerProjects)                    // the own login
        transport.enqueueJSON("/graphql", Fixtures.searchResponse([]))
        _ = try await makeProvider().searchOnline("login", excluding: [])
        let body = try #require(transport.requests.last?.bodyString)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        // Repositories of projects first, then the owned ones; each once.
        #expect((json["variables"] as? [String: Any])?["query"] as? String == "is:issue login repo:beispiel/app repo:octo/owned")
        #expect(transport.requests.count == 2)
    }
}
