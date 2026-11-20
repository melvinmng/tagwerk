import Foundation
import Testing
import TagwerkCore
@testable import GitHubKit

@MainActor
struct ClosedIssuesTests {
    let transport = StubTransport()

    private static let berlin = TimeZone(identifier: "Europe/Berlin")!
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        return calendar
    }

    /// The local day (Europe/Berlin) that contains noon of the given date components.
    private static func day(_ year: Int, _ month: Int, _ day: Int) -> DateInterval {
        let start = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        return calendar.dateInterval(of: .day, for: start)!
    }

    private static func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func makeAPI() -> (GitHubAPI, TokenManager) {
        let credentials = GitHubCredentials(accessToken: "gho_valid", refreshToken: "ghr", accessExpiresAt: nil, refreshExpiresAt: nil)
        let client = DeviceFlowClient(clientID: "client", transport: transport, sleep: { _ in }, now: { fixedNow })
        let tokens = TokenManager(store: MemoryCredentialStore(credentials), client: client, now: { fixedNow })
        return (GitHubAPI(transport: transport, tokens: tokens), tokens)
    }

    /// The reply to the request that reads the own login ("octo"); a provider asks for it once per call.
    private func enqueueLogin() {
        transport.enqueueJSON("/graphql", Fixtures.viewerProjects)
    }

    /// A provider that has not loaded anything yet; `selected` is the user's project choice.
    private func makeProvider(selected: Set<String>? = ["PVT_1"]) -> GitHubTaskProvider {
        let (api, tokens) = makeAPI()
        return GitHubTaskProvider(api: api, tokens: tokens, cache: MemoryGitHubCache(), catalogStore: nil,
                                  selectedProjectIDs: { selected }, now: { fixedNow })
    }

    private func variables(of request: URLRequest?) throws -> [String: Any] {
        let body = try #require(request?.bodyString)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        return try #require(json["variables"] as? [String: Any])
    }

    @Test func closedIssues_buildsQueryWithDayBefore() async throws {
        transport.enqueueJSON("/graphql", Fixtures.closedResponse([]))
        _ = try await makeAPI().0.closedIssues(assignedTo: "octo", closedSince: "2026-11-19")
        let request = try #require(transport.requests.last)
        let variables = try variables(of: request)
        #expect(variables["query"] as? String == "is:issue is:closed assignee:octo closed:>=2026-11-19")
        // The search text travels as a variable and never as part of the document.
        let body = try #require(request.bodyString)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        let document = try #require(json["query"] as? String)
        #expect(!document.contains("assignee:octo"))
        #expect(document.contains("first: 100"))
        #expect(document.contains("stateReason") && document.contains("closedAt"))
    }

    @Test func closedIssues_withUpperBound_buildsRange() async throws {
        transport.enqueueJSON("/graphql", Fixtures.closedResponse([]))
        _ = try await makeAPI().0.closedIssues(assignedTo: "octo", closedSince: "2026-11-02", closedUntil: "2026-11-08")
        #expect(try variables(of: transport.requests.last)["query"] as? String
                == "is:issue is:closed assignee:octo closed:2026-11-02..2026-11-08")
    }

    @Test func closedIssues_decodesStateReasonAndProjects() async throws {
        transport.enqueueJSON("/graphql", Fixtures.closedResponse([
            Fixtures.closedNode(id: "I_1", closedAt: "2026-11-20T09:00:00Z", projectIDs: ["PVT_1", "PVT_2"], archivedProjectIDs: ["PVT_3"]),
            Fixtures.closedNode(id: "I_2", closedAt: "2026-11-20T10:00:00Z", stateReason: "NOT_PLANNED"),
            Fixtures.closedNode(id: "I_3", closedAt: "2026-11-20T11:00:00Z", stateReason: nil, projectIDs: []),
        ]))
        let issues = try await makeAPI().0.closedIssues(assignedTo: "octo", closedSince: "2026-11-19")
        #expect(issues.map(\.id) == ["I_1", "I_2", "I_3"])
        #expect(issues.map(\.isCompleted) == [true, false, true])      // a missing reason counts as completed
        #expect(issues[0].projectIDs == ["PVT_1", "PVT_2", "PVT_3"])
        #expect(issues[2].projectIDs.isEmpty)
        #expect(issues[0].closedAt == Self.date("2026-11-20T09:00:00Z"))
    }

    @Test func closedIssues_countsOnlyCompletedOrMissingReasonAsCompleted() async throws {
        transport.enqueueJSON("/graphql", Fixtures.closedResponse([
            Fixtures.closedNode(id: "I_completed", closedAt: "2026-11-20T09:00:00Z", stateReason: "COMPLETED"),
            Fixtures.closedNode(id: "I_notPlanned", closedAt: "2026-11-20T10:00:00Z", stateReason: "NOT_PLANNED"),
            Fixtures.closedNode(id: "I_duplicate", closedAt: "2026-11-20T11:00:00Z", stateReason: "DUPLICATE"),
            Fixtures.closedNode(id: "I_missing", closedAt: "2026-11-20T12:00:00Z", stateReason: nil),
        ]))
        let issues = try await makeAPI().0.closedIssues(assignedTo: "octo", closedSince: "2026-11-19")
        let completed = Dictionary(uniqueKeysWithValues: issues.map { ($0.id, $0.isCompleted) })
        #expect(completed == ["I_completed": true, "I_notPlanned": false, "I_duplicate": false, "I_missing": true])
    }

    @Test func closedIssueCount_skipsDuplicates() async throws {
        enqueueLogin()
        transport.enqueueJSON("/graphql", Fixtures.closedResponse([
            Fixtures.closedNode(id: "I_1", closedAt: "2026-11-20T09:00:00Z", stateReason: "COMPLETED"),
            Fixtures.closedNode(id: "I_2", closedAt: "2026-11-20T10:00:00Z", stateReason: "DUPLICATE"),
        ]))
        #expect(try await makeProvider().closedIssueCount(in: Self.day(2026, 11, 20)) == 1)
    }

    @Test func closedIssues_followsSecondPage() async throws {
        transport.enqueueJSON("/graphql", Fixtures.closedResponse(
            [Fixtures.closedNode(id: "I_1", closedAt: "2026-11-20T09:00:00Z")], hasNextPage: true, endCursor: "CUR1"))
        transport.enqueueJSON("/graphql", Fixtures.closedResponse([Fixtures.closedNode(id: "I_2", closedAt: "2026-11-20T10:00:00Z")]))
        let issues = try await makeAPI().0.closedIssues(assignedTo: "octo", closedSince: "2026-11-19")
        #expect(issues.map(\.id) == ["I_1", "I_2"])
        #expect(transport.requests.count == 2)
        #expect(try variables(of: transport.requests.last)["cursor"] as? String == "CUR1")
    }

    @Test func closedIssues_stopsAfterThreePages() async throws {
        for page in 1...4 {
            transport.enqueueJSON("/graphql", Fixtures.closedResponse(
                [Fixtures.closedNode(id: "I_\(page)", closedAt: "2026-11-20T09:00:00Z")], hasNextPage: true, endCursor: "CUR\(page)"))
        }
        let issues = try await makeAPI().0.closedIssues(assignedTo: "octo", closedSince: "2026-11-19")
        #expect(issues.count == 3)
        #expect(transport.requests.count == 3)
    }

    @Test func closedIssues_filtersByLocalInterval() async throws {
        enqueueLogin()
        // 2026-11-19T23:30Z is 00:30 on 20 November in Berlin: it belongs to the 20th, not to the 19th.
        let late = Fixtures.closedNode(id: "I_late", closedAt: "2026-11-19T23:30:00Z")
        let early = Fixtures.closedNode(id: "I_early", closedAt: "2026-11-19T22:30:00Z")       // 23:30 on the 19th
        let response = Fixtures.closedResponse([late, early])
        transport.enqueueJSON("/graphql", response)
        enqueueLogin()
        transport.enqueueJSON("/graphql", response)
        let provider = makeProvider()
        let twentieth = try await provider.closedIssueDates(in: Self.day(2026, 11, 20))
        #expect(twentieth == [Self.date("2026-11-19T23:30:00Z")])
        let nineteenth = try await provider.closedIssueDates(in: Self.day(2026, 11, 19))
        #expect(nineteenth == [Self.date("2026-11-19T22:30:00Z")])
        // The query starts one day before the interval (UTC date), so the zone offset never hides an issue.
        #expect(try variables(of: transport.requests[1])["query"] as? String
                == "is:issue is:closed assignee:octo closed:2026-11-18..2026-11-20")
    }

    @Test func closedIssueCount_skipsNotPlanned() async throws {
        enqueueLogin()
        transport.enqueueJSON("/graphql", Fixtures.closedResponse([
            Fixtures.closedNode(id: "I_1", closedAt: "2026-11-20T09:00:00Z"),
            Fixtures.closedNode(id: "I_2", closedAt: "2026-11-20T10:00:00Z", stateReason: "NOT_PLANNED"),
            Fixtures.closedNode(id: "I_3", closedAt: "2026-11-20T11:00:00Z", stateReason: nil),
        ]))
        let provider = makeProvider()
        #expect(try await provider.closedIssueCount(in: Self.day(2026, 11, 20)) == 2)
    }

    @Test func closedIssueCount_skipsIssuesOutsideShownProjects() async throws {
        enqueueLogin()
        transport.enqueueJSON("/graphql", Fixtures.closedResponse([
            Fixtures.closedNode(id: "I_1", closedAt: "2026-11-20T09:00:00Z", projectIDs: ["PVT_1"]),
            Fixtures.closedNode(id: "I_2", closedAt: "2026-11-20T10:00:00Z", projectIDs: ["PVT_9"]),
            Fixtures.closedNode(id: "I_3", closedAt: "2026-11-20T11:00:00Z", projectIDs: []),
        ]))
        let provider = makeProvider(selected: ["PVT_1"])
        #expect(try await provider.closedIssueCount(in: Self.day(2026, 11, 20)) == 1)
    }

    @Test func closedIssueCount_countsArchivedProjectItems() async throws {
        enqueueLogin()
        // Completing a task in Tagwerk can leave an archived project item behind; the issue still counts.
        transport.enqueueJSON("/graphql", Fixtures.closedResponse([
            Fixtures.closedNode(id: "I_1", closedAt: "2026-11-20T09:00:00Z", projectIDs: [], archivedProjectIDs: ["PVT_1"]),
        ]))
        let provider = makeProvider(selected: ["PVT_1"])
        #expect(try await provider.closedIssueCount(in: Self.day(2026, 11, 20)) == 1)
    }

    @Test func closedIssueCount_withoutChosenProjectsAndBeforeProjectsLoaded_isUnavailable() async {
        enqueueLogin()
        // No stored choice and no loaded projects: the default selection is still empty and would report a false zero.
        transport.enqueueJSON("/graphql", Fixtures.closedResponse([Fixtures.closedNode(id: "I_1", closedAt: "2026-11-20T09:00:00Z")]))
        let provider = makeProvider(selected: nil)
        await #expect(throws: IssueSearchError.self) {
            _ = try await provider.closedIssueCount(in: Self.day(2026, 11, 20))
        }
    }

    @Test func closedIssueCount_withoutChosenProjects_usesTheDefaultSelectionOnceProjectsAreLoaded() async throws {
        Fixtures.enqueueAssignedIssues(on: transport)
        let provider = makeProvider(selected: nil)
        _ = try await provider.openTasks()
        #expect(provider.defaultSelectedProjectIDs.contains("PVT_1"))
        // The provider knows its login from the load above, so no further login request is needed.
        transport.enqueueJSON("/graphql", Fixtures.closedResponse([
            Fixtures.closedNode(id: "I_1", closedAt: "2026-11-20T09:00:00Z", projectIDs: ["PVT_1"]),
            Fixtures.closedNode(id: "I_2", closedAt: "2026-11-20T10:00:00Z", projectIDs: ["PVT_9"]),
        ]))
        #expect(try await provider.closedIssueCount(in: Self.day(2026, 11, 20)) == 1)
    }

    @Test func closedIssueCount_resolvesTheLoginWhenUnknown() async throws {
        transport.enqueueJSON("/graphql", Fixtures.viewerProjects)       // own login "octo"
        transport.enqueueJSON("/graphql", Fixtures.closedResponse([Fixtures.closedNode(id: "I_1", closedAt: "2026-11-20T09:00:00Z")]))
        #expect(try await makeProvider().closedIssueCount(in: Self.day(2026, 11, 20)) == 1)
        #expect(try variables(of: transport.requests.last)["query"] as? String
                == "is:issue is:closed assignee:octo closed:2026-11-18..2026-11-20")
    }

    @Test func closedIssueCount_mapsOfflineError() async {
        enqueueLogin()
        transport.enqueue("/graphql", .failure(.notConnectedToInternet))
        let provider = makeProvider()
        await #expect(throws: IssueSearchError.offline) {
            _ = try await provider.closedIssueCount(in: Self.day(2026, 11, 20))
        }
    }

    @Test func closedIssueDates_weekInterval_countsAllSevenDays() async throws {
        enqueueLogin()
        let week = DateInterval(start: Self.day(2026, 11, 16).start, end: Self.day(2026, 11, 22).end)
        var nodes = (16...22).map { Fixtures.closedNode(id: "I_\($0)", closedAt: "2026-11-\($0)T12:00:00Z") }
        nodes.append(Fixtures.closedNode(id: "I_before", closedAt: "2026-11-15T12:00:00Z"))       // the week before
        nodes.append(Fixtures.closedNode(id: "I_after", closedAt: "2026-11-23T12:00:00Z"))        // the week after
        transport.enqueueJSON("/graphql", Fixtures.closedResponse(nodes))
        let provider = makeProvider()
        let dates = try await provider.closedIssueDates(in: week)
        #expect(dates.count == 7)
        #expect(dates.first == Self.date("2026-11-16T12:00:00Z") && dates.last == Self.date("2026-11-22T12:00:00Z"))
        #expect(try variables(of: transport.requests.last)["query"] as? String
                == "is:issue is:closed assignee:octo closed:2026-11-14..2026-11-22")
    }
}
