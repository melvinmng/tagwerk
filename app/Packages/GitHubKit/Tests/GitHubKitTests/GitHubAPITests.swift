import Foundation
import Testing
import TagwerkCore
@testable import GitHubKit

struct GitHubAPITests {
    let transport = StubTransport()

    func makeAPI(_ credentials: GitHubCredentials = GitHubCredentials(
        accessToken: "gho_valid", refreshToken: "ghr_valid", accessExpiresAt: fixedNow.addingTimeInterval(3600), refreshExpiresAt: nil
    )) -> GitHubAPI {
        let client = DeviceFlowClient(clientID: "client", transport: transport, sleep: { _ in }, now: { fixedNow })
        let tokens = TokenManager(store: MemoryCredentialStore(credentials), client: client, now: { fixedNow })
        return GitHubAPI(transport: transport, tokens: tokens)
    }

    private func enqueueAllProjects() {
        transport.enqueueJSON("/graphql", Fixtures.viewerProjects)
        transport.enqueueJSON("/graphql", Fixtures.itemsProject1Page1)
        transport.enqueueJSON("/graphql", Fixtures.itemsProject1Page2)
        transport.enqueueJSON("/graphql", Fixtures.itemsProject2)
    }

    @Test func api_followsCursorAcrossPages() async throws {
        enqueueAllProjects()
        let result = try await makeAPI().openProjectIssues()

        #expect(transport.requests.count == 4)
        #expect(transport.requests[2].bodyString.contains("CURSOR_1"))
        #expect(Set(result.issues.map(\.issueID)) == ["I_1", "I_2"])
        #expect(result.login == "octo")
        #expect(result.projects.map(\.number) == [1, 2])
    }

    @Test func api_skipsDraftsPullRequestsAndArchivedItems() async throws {
        enqueueAllProjects()
        let result = try await makeAPI().openProjectIssues()
        #expect(!result.issues.contains { $0.issueID == "I_3" })
        #expect(result.issues.count == 2)
    }

    @Test func api_mergesIssueAcrossProjects() async throws {
        enqueueAllProjects()
        let issue = try #require(try await makeAPI().openProjectIssues().issues.first { $0.issueID == "I_1" })
        #expect(issue.placements.count == 2)
        let first = try #require(issue.placements.first { $0.project.number == 1 })
        let second = try #require(issue.placements.first { $0.project.number == 2 })
        #expect(first.status == "Ready")
        #expect(first.priority == .p3)
        #expect(first.due == DueDate(year: 2026, month: 11, day: 20))
        #expect(first.estimateMinutes == 90)
        #expect(second.estimateMinutes == 240)
        #expect(second.priority == nil)
        #expect(issue.repository == "beispiel/app")
        #expect(issue.assignees == ["octo"])
        #expect(issue.labels == ["bug"])
        #expect(issue.isOpen)
    }

    @Test func api_sendsAuthAndVersionHeaders() async throws {
        enqueueAllProjects()
        _ = try await makeAPI().openProjectIssues()
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.github.com/graphql")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer gho_valid")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
    }

    @Test func api_unauthorized_refreshesOnceAndRetries() async throws {
        transport.enqueueJSON("/graphql", status: 401, #"{"message":"Bad credentials"}"#)
        transport.enqueueJSON("/login/oauth/access_token", #"{"access_token":"gho_new","expires_in":28800,"refresh_token":"ghr_new"}"#)
        enqueueAllProjects()
        _ = try await makeAPI().openProjectIssues()
        let graphQLRequests = transport.requests(to: "/graphql")
        #expect(graphQLRequests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer gho_valid")
        #expect(graphQLRequests[1].value(forHTTPHeaderField: "Authorization") == "Bearer gho_new")
        #expect(transport.requests(to: "/login/oauth/access_token").count == 1)
    }

    @Test func api_graphQLErrors_throw() async {
        transport.enqueueJSON("/graphql", #"{"errors":[{"message":"Your token has not been granted the required scopes"}]}"#)
        await #expect(throws: GitHubAPIError.graphQL("Your token has not been granted the required scopes")) {
            try await makeAPI().openProjectIssues()
        }
    }

    @Test func api_offline_throwsNetwork() async {
        transport.enqueue("/graphql", .failure(.notConnectedToInternet))
        do {
            _ = try await makeAPI().openProjectIssues()
            Issue.record("expected an error")
        } catch GitHubAPIError.network {
            // expected
        } catch {
            Issue.record("expected .network, got \(error)")
        }
    }

    @Test func issue_nodeID_readsPlacementsOfOpenProjectsOnly() async throws {
        transport.enqueueJSON("/graphql", Fixtures.issueNode)
        let issue = try #require(try await makeAPI().issue(nodeID: "I_1"))
        #expect(issue.placements.map(\.project.id) == ["PVT_1"])
        #expect(issue.placements.first?.status == "Done")
        #expect(issue.placements.first?.due == DueDate(year: 2026, month: 11, day: 21))
        #expect(transport.requests.first?.bodyString.contains("I_1") == true)
    }
}
