import Foundation
import Testing
@testable import GitHubKit

struct GitHubProjectPagingTests {
    let transport = StubTransport()

    func makeAPI() -> GitHubAPI {
        let credentials = GitHubCredentials(accessToken: "gho_valid", refreshToken: "ghr", accessExpiresAt: nil, refreshExpiresAt: nil)
        let client = DeviceFlowClient(clientID: "client", transport: transport, sleep: { _ in }, now: { fixedNow })
        let tokens = TokenManager(store: MemoryCredentialStore(credentials), client: client, now: { fixedNow })
        return GitHubAPI(transport: transport, tokens: tokens)
    }

    /// A viewer response with projects "numbers" and the given paging state.
    private func page(_ numbers: ClosedRange<Int>, hasNext: Bool, cursor: String?, closed: Set<Int> = []) -> String {
        let nodes = numbers.map { number in
            #"{"id":"PVT_\#(number)","number":\#(number),"title":"Project \#(number)","closed":\#(closed.contains(number)),"repositories":{"nodes":[]},"fields":{"nodes":[]}}"#
        }.joined(separator: ",")
        let endCursor = cursor.map { #""\#($0)""# } ?? "null"
        return #"{"data":{"viewer":{"login":"octo","projectsV2":{"pageInfo":{"hasNextPage":\#(hasNext),"endCursor":\#(endCursor)},"nodes":[\#(nodes)]}}}}"#
    }

    @Test func viewerProjects_requestsHundredPerPage() async throws {
        transport.enqueueJSON("/graphql", page(1...2, hasNext: false, cursor: nil))
        _ = try await makeAPI().viewerProjects()
        #expect(transport.requests.first?.bodyString.contains("projectsV2(first: 100") == true)
        #expect(!ProjectsQuery.viewerProjects.contains("first: 20, query"))
    }

    @Test func viewerProjects_followsCursorUntilTheLastPage() async throws {
        transport.enqueueJSON("/graphql", page(1...2, hasNext: true, cursor: "C1"))
        transport.enqueueJSON("/graphql", page(3...4, hasNext: true, cursor: "C2"))
        transport.enqueueJSON("/graphql", page(5...5, hasNext: false, cursor: "C3"))
        let result = try await makeAPI().viewerProjects()
        #expect(result.login == "octo")
        #expect(result.projects.map(\.number) == [1, 2, 3, 4, 5])
        #expect(transport.requests.count == 3)
        #expect(transport.requests[0].bodyString.contains(#""cursor":null"#))
        #expect(transport.requests[1].bodyString.contains(#""cursor":"C1""#))
        #expect(transport.requests[2].bodyString.contains(#""cursor":"C2""#))
    }

    @Test func viewerProjects_withoutPageInfo_isASinglePage() async throws {
        transport.enqueueJSON("/graphql", Fixtures.viewerProjects)
        let result = try await makeAPI().viewerProjects()
        #expect(result.projects.map(\.number) == [1, 2])
        #expect(transport.requests.count == 1)
    }

    @Test func viewerProjects_skipsClosedProjectsOnEveryPage() async throws {
        transport.enqueueJSON("/graphql", page(1...2, hasNext: true, cursor: "C1", closed: [2]))
        transport.enqueueJSON("/graphql", page(3...4, hasNext: false, cursor: nil, closed: [3]))
        let result = try await makeAPI().viewerProjects()
        #expect(result.projects.map(\.number) == [1, 4])
    }

    @Test func viewerProjects_stopsWhenTheCursorDoesNotAdvance() async throws {
        transport.enqueueJSON("/graphql", page(1...1, hasNext: true, cursor: nil))
        let result = try await makeAPI().viewerProjects()
        #expect(result.projects.map(\.number) == [1])
        #expect(transport.requests.count == 1)
    }

    @Test func viewerProjects_failureOnALaterPage_throwsInsteadOfReturningAPartialList() async throws {
        transport.enqueueJSON("/graphql", page(1...2, hasNext: true, cursor: "C1"))
        transport.enqueue("/graphql", .failure(.notConnectedToInternet))
        await #expect(throws: GitHubAPIError.self) { try await makeAPI().viewerProjects() }
    }

    @Test func viewerProjects_stopsAtThePageLimit() async throws {
        for index in 1...4 { transport.enqueueJSON("/graphql", page(index...index, hasNext: true, cursor: "C\(index)")) }
        let result = try await makeAPI().viewerProjects(maxPages: 3)
        #expect(result.projects.count == 3)
        #expect(transport.requests.count == 3)
    }
}
