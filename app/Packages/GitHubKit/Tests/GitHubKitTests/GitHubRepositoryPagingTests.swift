import Foundation
import Testing
@testable import GitHubKit

struct GitHubRepositoryPagingTests {
    let transport = StubTransport()

    func makeAPI() -> GitHubAPI {
        let credentials = GitHubCredentials(accessToken: "gho_valid", refreshToken: "ghr", accessExpiresAt: nil, refreshExpiresAt: nil)
        let client = DeviceFlowClient(clientID: "client", transport: transport, sleep: { _ in }, now: { fixedNow })
        let tokens = TokenManager(store: MemoryCredentialStore(credentials), client: client, now: { fixedNow })
        return GitHubAPI(transport: transport, tokens: tokens)
    }

    /// JSON array of repositories named "owner/repo<number>" for the given numbers.
    private func page(_ numbers: ClosedRange<Int>, owner: String = "octo") -> String {
        "[" + numbers.map { #"{"full_name":"\#(owner)/repo\#($0)"}"# }.joined(separator: ",") + "]"
    }

    /// The `page` query value of every request, in order.
    private func requestedPages() -> [Int] {
        transport.requests.compactMap { request in
            request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                .queryItems?.first { $0.name == "page" }?.value.flatMap(Int.init)
        }
    }

    @Test func accessibleRepositories_asksForOwnedCollaboratorAndOrganizationRepositories() async throws {
        transport.enqueueJSON("/user/repos", page(1...2))
        _ = try await makeAPI().accessibleRepositories()
        let query = try #require(transport.requests.first?.url?.query)
        #expect(query.contains("affiliation=owner,collaborator,organization_member")
                || query.contains("affiliation=owner%2Ccollaborator%2Corganization_member"))
        #expect(query.contains("sort=pushed") && query.contains("per_page=100") && query.contains("page=1"))
    }

    @Test func accessibleRepositories_followsPagesUntilAShortPage() async throws {
        transport.enqueueJSON("/user/repos", page(1...3))
        transport.enqueueJSON("/user/repos", page(4...6))
        transport.enqueueJSON("/user/repos", page(7...7))
        let repositories = try await makeAPI().accessibleRepositories(pageSize: 3)
        #expect(repositories.count == 7)
        #expect(repositories.first == "octo/repo1" && repositories.last == "octo/repo7")
        #expect(requestedPages() == [1, 2, 3])
    }

    @Test func accessibleRepositories_requestsOneMorePageWhenTheLastPageIsFull() async throws {
        transport.enqueueJSON("/user/repos", page(1...2))
        transport.enqueueJSON("/user/repos", "[]")
        let repositories = try await makeAPI().accessibleRepositories(pageSize: 2)
        #expect(repositories == ["octo/repo1", "octo/repo2"])
        #expect(transport.requests.count == 2)
    }

    @Test func accessibleRepositories_dropsDuplicatesWhenThePushOrderShiftsBetweenPages() async throws {
        transport.enqueueJSON("/user/repos", page(1...3))
        transport.enqueueJSON("/user/repos", page(3...4))
        let repositories = try await makeAPI().accessibleRepositories(pageSize: 3)
        #expect(repositories == ["octo/repo1", "octo/repo2", "octo/repo3", "octo/repo4"])
    }

    @Test func accessibleRepositories_stopsAtThePageLimit() async throws {
        for start in [1, 3, 5, 7] { transport.enqueueJSON("/user/repos", page(start...(start + 1))) }
        let repositories = try await makeAPI().accessibleRepositories(pageSize: 2, maxPages: 3)
        #expect(repositories.count == 6)
        #expect(transport.requests.count == 3)
    }

    @Test func accessibleRepositories_failureOnALaterPage_throwsInsteadOfReturningAPartialList() async throws {
        transport.enqueueJSON("/user/repos", page(1...2))
        transport.enqueue("/user/repos", .failure(.notConnectedToInternet))
        await #expect(throws: GitHubAPIError.self) { try await makeAPI().accessibleRepositories(pageSize: 2) }
    }

    @Test func accessibleRepositories_includesOrganizationRepositories() async throws {
        transport.enqueueJSON("/user/repos", #"[{"full_name":"octo/app"},{"full_name":"acme-corp/platform"}]"#)
        let repositories = try await makeAPI().accessibleRepositories()
        #expect(repositories == ["octo/app", "acme-corp/platform"])
    }
}
