import Foundation
import Testing
import TagwerkCore
@testable import GitHubKit

struct ProjectItemsTests {
    let transport = StubTransport()

    private func makeAPI() -> GitHubAPI {
        let credentials = GitHubCredentials(accessToken: "gho_valid", refreshToken: "ghr", accessExpiresAt: nil, refreshExpiresAt: nil)
        let client = DeviceFlowClient(clientID: "client", transport: transport, sleep: { _ in }, now: { fixedNow })
        let tokens = TokenManager(store: MemoryCredentialStore(credentials), client: client, now: { fixedNow })
        return GitHubAPI(transport: transport, tokens: tokens)
    }

    private static func issue(_ number: Int, state: String = "OPEN", reason: String? = nil, closedAt: String? = nil,
                              blockedBy: Int = 0, blocking: Int = 0, assignees: [String] = [], withType: Bool = true) -> String {
        let reasonJSON = reason.map { #""\#($0)""# } ?? "null"
        let closedJSON = closedAt.map { #""\#($0)""# } ?? "null"
        let people = assignees.map { #"{"login":"\#($0)"}"# }.joined(separator: ",")
        let type = withType ? #""__typename":"Issue","# : ""
        return """
        {\(type)"id":"I_\(number)","number":\(number),"title":"Issue \(number)","url":"https://github.com/octo/repo/issues/\(number)",\
        "state":"\(state)","stateReason":\(reasonJSON),"createdAt":"2026-11-01T09:00:00Z","closedAt":\(closedJSON),\
        "updatedAt":"2026-11-02T09:00:00Z","repository":{"nameWithOwner":"octo/repo"},"assignees":{"nodes":[\(people)]},\
        "issueDependenciesSummary":{"blockedBy":\(blockedBy),"blocking":\(blocking)}}
        """
    }

    private static func item(_ content: String, archived: Bool = false, status: String? = nil, due: String? = nil,
                             estimate: (field: String, value: Double)? = nil) -> String {
        var values: [String] = []
        if let estimate { values.append(#"{"number":\#(estimate.value),"field":{"name":"\#(estimate.field)"}}"#) }
        if let status { values.append(#"{"name":"\#(status)","field":{"name":"Status"}}"#) }
        if let due { values.append(#"{"date":"\#(due)","field":{"name":"Due date"}}"#) }
        return #"{"isArchived":\#(archived),"fieldValues":{"nodes":[\#(values.joined(separator: ","))]},"content":\#(content)}"#
    }

    private static func projectPage(_ items: [String], hasNext: Bool = false, cursor: String? = nil) -> String {
        let end = cursor.map { #""\#($0)""# } ?? "null"
        return #"{"data":{"node":{"items":{"pageInfo":{"hasNextPage":\#(hasNext),"endCursor":\#(end)},"nodes":[\#(items.joined(separator: ","))]}}}}"#
    }

    private static func repositoryPage(_ issues: [String], hasNext: Bool = false, cursor: String? = nil) -> String {
        let end = cursor.map { #""\#($0)""# } ?? "null"
        return #"{"data":{"repository":{"issues":{"pageInfo":{"hasNextPage":\#(hasNext),"endCursor":\#(end)},"nodes":[\#(issues.joined(separator: ","))]}}}}"#
    }

    @Test func projectItems_readsAllItemsWhoeverIsAssigned() async throws {
        transport.enqueueJSON("/graphql", Self.projectPage([
            Self.item(Self.issue(1, assignees: ["octo"])),
            Self.item(Self.issue(2, assignees: ["someone-else"])),
            Self.item(Self.issue(3)),
        ]))
        let result = try await makeAPI().projectItems(projectID: "PVT_1")
        #expect(result.items.map(\.number) == [1, 2, 3])
        #expect(result.items[1].assignees == ["someone-else"])
        #expect(!result.isTruncated)
        let body = try #require(transport.requests.last?.bodyString)
        #expect(!body.contains("assignee:@me"), "the query reads the project, not the viewer's issues")
        #expect(body.contains(#""id":"PVT_1""#))
    }

    @Test func projectItems_readsTheEstimateInMinutes() async throws {
        transport.enqueueJSON("/graphql", Self.projectPage([
            Self.item(Self.issue(1), estimate: ("Estimate (h)", 1.5)),
            Self.item(Self.issue(2), estimate: ("Estimate (MDs)", 0.5)),
            Self.item(Self.issue(3)),
            Self.item(Self.issue(4), estimate: ("Story points", 8)),
        ]))
        let result = try await makeAPI().projectItems(projectID: "PVT_1")
        #expect(result.items.map(\.estimateMinutes) == [90, 240, nil, nil])
    }

    @Test func projectItems_followsTheCursorToTheLastPage() async throws {
        transport.enqueueJSON("/graphql", Self.projectPage([Self.item(Self.issue(1))], hasNext: true, cursor: "C1"))
        transport.enqueueJSON("/graphql", Self.projectPage([Self.item(Self.issue(2))], hasNext: true, cursor: "C2"))
        transport.enqueueJSON("/graphql", Self.projectPage([Self.item(Self.issue(3))]))
        let result = try await makeAPI().projectItems(projectID: "PVT_1")
        #expect(result.items.map(\.number) == [1, 2, 3])
        #expect(transport.requests.count == 3)
        #expect(!transport.requests[0].bodyString.contains(#""cursor""#), "the first page has no cursor")
        #expect(transport.requests[1].bodyString.contains(#""cursor":"C1""#))
        #expect(transport.requests[2].bodyString.contains(#""cursor":"C2""#))
    }

    @Test func projectItems_reportsTruncationAtThePageLimit() async throws {
        for page in 1...3 {
            transport.enqueueJSON("/graphql", Self.projectPage([Self.item(Self.issue(page))], hasNext: true, cursor: "C\(page)"))
        }
        let result = try await makeAPI().projectItems(projectID: "PVT_1", maxPages: 2)
        #expect(result.items.count == 2)
        #expect(result.isTruncated)
        #expect(transport.requests.count == 2)
    }

    @Test func projectItems_aRepeatedCursorEndsTheLoop() async throws {
        transport.enqueueJSON("/graphql", Self.projectPage([Self.item(Self.issue(1))], hasNext: true, cursor: "SAME"))
        transport.enqueueJSON("/graphql", Self.projectPage([Self.item(Self.issue(2))], hasNext: true, cursor: "SAME"))
        transport.enqueueJSON("/graphql", Self.projectPage([Self.item(Self.issue(3))], hasNext: true, cursor: "SAME"))
        let result = try await makeAPI().projectItems(projectID: "PVT_1")
        #expect(result.items.count == 2)
        #expect(transport.requests.count == 2)
    }

    @Test func projectItems_skipsDraftsAndPullRequests() async throws {
        transport.enqueueJSON("/graphql", Self.projectPage([
            Self.item(Self.issue(1)),
            Self.item(#"{"__typename":"PullRequest"}"#),
            Self.item(#"{"__typename":"DraftIssue"}"#),
            #"{"isArchived":false,"fieldValues":{"nodes":[]},"content":null}"#,
        ]))
        let result = try await makeAPI().projectItems(projectID: "PVT_1")
        #expect(result.items.map(\.number) == [1])
    }

    @Test func projectItems_mapsTheStateReason() async throws {
        transport.enqueueJSON("/graphql", Self.projectPage([
            Self.item(Self.issue(1)),
            Self.item(Self.issue(2, state: "CLOSED", reason: "COMPLETED", closedAt: "2026-11-10T10:00:00Z")),
            Self.item(Self.issue(3, state: "CLOSED", reason: nil, closedAt: "2026-11-11T10:00:00Z")),
            Self.item(Self.issue(4, state: "CLOSED", reason: "NOT_PLANNED", closedAt: "2026-11-12T10:00:00Z")),
            Self.item(Self.issue(5, state: "CLOSED", reason: "DUPLICATE", closedAt: "2026-11-13T10:00:00Z")),
        ]))
        let result = try await makeAPI().projectItems(projectID: "PVT_1")
        #expect(result.items.map(\.state) == [.open, .completed, .completed, .closedNotPlanned, .closedNotPlanned])
        #expect(result.items[0].closedAt == nil)
        #expect(result.items[1].closedAt == ISO8601DateFormatter().date(from: "2026-11-10T10:00:00Z"))
    }

    @Test func projectItems_readsStatusAndDueDate() async throws {
        transport.enqueueJSON("/graphql", Self.projectPage([
            Self.item(Self.issue(1), status: "Blocked", due: "2026-12-24"),
        ]))
        let item = try #require(try await makeAPI().projectItems(projectID: "PVT_1").items.first)
        #expect(item.status == "Blocked")
        #expect(item.due == DueDate(year: 2026, month: 12, day: 24))
    }

    @Test func projectItems_readsTheOpenDependencyCounts() async throws {
        transport.enqueueJSON("/graphql", Self.projectPage([Self.item(Self.issue(1, blockedBy: 2, blocking: 3))]))
        let item = try #require(try await makeAPI().projectItems(projectID: "PVT_1").items.first)
        #expect(item.openBlockedByCount == 2)
        #expect(item.openBlockingCount == 3)
        #expect(ProjectsQuery.projectItems.contains("issueDependenciesSummary"))
    }

    @Test func projectItems_keepsArchivedItems() async throws {
        transport.enqueueJSON("/graphql", Self.projectPage([
            Self.item(Self.issue(1, state: "CLOSED", reason: "COMPLETED", closedAt: "2026-11-10T10:00:00Z"), archived: true),
        ]))
        let item = try #require(try await makeAPI().projectItems(projectID: "PVT_1").items.first)
        #expect(item.isArchived)
        #expect(item.state == .completed)
    }

    @Test func projectItems_anIssueOnTheBoardTwiceCountsOnce() async throws {
        transport.enqueueJSON("/graphql", Self.projectPage([Self.item(Self.issue(1)), Self.item(Self.issue(1))]))
        let result = try await makeAPI().projectItems(projectID: "PVT_1")
        #expect(result.items.count == 1)
    }

    @Test func projectItems_partialErrorsKeepTheReadableNodes() async throws {
        let body = #"{"data":{"node":{"items":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[null,\#(Self.item(Self.issue(2)))]}}},"errors":[{"message":"organization has not approved the app"}]}"#
        transport.enqueueJSON("/graphql", body)
        let result = try await makeAPI().projectItems(projectID: "PVT_1")
        #expect(result.items.map(\.number) == [2])
    }

    @Test func projectItems_aMissingProjectThrows() async throws {
        transport.enqueueJSON("/graphql", #"{"data":{"node":null}}"#)
        await #expect(throws: GitHubAPIError.self) { try await makeAPI().projectItems(projectID: "PVT_gone") }
    }

    @Test func projectItems_aFailingPageFailsTheCall() async throws {
        transport.enqueueJSON("/graphql", Self.projectPage([Self.item(Self.issue(1))], hasNext: true, cursor: "C1"))
        transport.enqueueJSON("/graphql", status: 502, "{}")
        await #expect(throws: GitHubAPIError.http(502)) { try await makeAPI().projectItems(projectID: "PVT_1") }
    }

    @Test func repositoryIssues_splitsTheNameAndReadsIssuesWithoutAType() async throws {
        transport.enqueueJSON("/graphql", Self.repositoryPage([Self.issue(7, withType: false), Self.issue(8, state: "CLOSED", reason: "NOT_PLANNED", closedAt: "2026-11-12T10:00:00Z", withType: false)]))
        let result = try await makeAPI().repositoryIssues("octo/repo")
        #expect(result.items.map(\.number) == [7, 8])
        #expect(result.items.map(\.state) == [.open, .closedNotPlanned])
        #expect(result.items[0].status == nil)
        let body = try #require(transport.requests.last?.bodyString)
        #expect(body.contains(#""owner":"octo""#) && body.contains(#""name":"repo""#))
    }

    @Test func repositoryIssues_followsTheCursor() async throws {
        transport.enqueueJSON("/graphql", Self.repositoryPage([Self.issue(1, withType: false)], hasNext: true, cursor: "R1"))
        transport.enqueueJSON("/graphql", Self.repositoryPage([Self.issue(2, withType: false)]))
        let result = try await makeAPI().repositoryIssues("octo/repo")
        #expect(result.items.map(\.number) == [1, 2])
        #expect(transport.requests[1].bodyString.contains(#""cursor":"R1""#))
    }

    @Test func repositoryIssues_rejectsAnInvalidName() async throws {
        await #expect(throws: GitHubAPIError.invalidRepository) { try await makeAPI().repositoryIssues("not-a-repository") }
        #expect(transport.requests.isEmpty)
    }
}
