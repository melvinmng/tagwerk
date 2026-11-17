import Foundation
import Testing
import TagwerkCore
@testable import GitHubKit

/// In-memory cache.
@MainActor
final class MemoryGitHubCache: GitHubCache {
    var snapshot: (records: [GitHubIssueRecord], fetchedAt: Date)?
    func load() -> (records: [GitHubIssueRecord], fetchedAt: Date)? { snapshot }
    func store(_ records: [GitHubIssueRecord], fetchedAt: Date) { snapshot = (records, fetchedAt) }
}

@MainActor
struct GitHubTaskProviderReadTests {
    let transport = StubTransport()
    let cache = MemoryGitHubCache()
    var selection: Set<String>? = nil

    func makeProvider(signedIn: Bool = true, selection: Set<String>? = nil) -> GitHubTaskProvider {
        let credentials = signedIn ? GitHubCredentials(accessToken: "gho_valid", refreshToken: "ghr", accessExpiresAt: nil, refreshExpiresAt: nil) : nil
        let client = DeviceFlowClient(clientID: "client", transport: transport, sleep: { _ in }, now: { fixedNow })
        let tokens = TokenManager(store: MemoryCredentialStore(credentials), client: client, now: { fixedNow })
        return GitHubTaskProvider(api: GitHubAPI(transport: transport, tokens: tokens), tokens: tokens, cache: cache,
                                  selectedProjectIDs: { selection }, now: { fixedNow })
    }

    private func enqueueAllProjects() {
        Fixtures.enqueueAssignedIssues(on: transport)
    }

    @Test func openTasks_online_returnsVisibleIssuesAndStoresCache() async throws {
        enqueueAllProjects()
        let provider = makeProvider()
        let items = try await provider.openTasks()

        #expect(items.map(\.id.rawValue) == ["I_1", "I_3"])
        #expect(items.first?.due == DueDate(year: 2026, month: 11, day: 18))
        #expect(cache.snapshot?.records.map(\.issueID) == ["I_1", "I_3"])
        #expect(cache.snapshot?.fetchedAt == fixedNow)
        #expect(provider.offlineSince == nil)
        #expect(provider.login == "octo")
        #expect(provider.projects.map(\.number) == [1, 2, 4])
    }

    @Test func openTasks_networkError_returnsCacheAndSetsOffline() async throws {
        let cachedAt = fixedNow.addingTimeInterval(-3600)
        cache.snapshot = ([makeRecord(placements: [makePlacement(makeProject(1))])], cachedAt)
        transport.enqueue("/graphql", .failure(.notConnectedToInternet))

        let provider = makeProvider()
        let items = try await provider.openTasks()

        #expect(items.map(\.title) == ["Login-Fehler beheben"])
        #expect(provider.offlineSince == cachedAt)
    }

    @Test func openTasks_networkErrorWithoutCache_fails() async {
        transport.enqueue("/graphql", .failure(.notConnectedToInternet))
        await #expect(throws: TaskWriteError.self) { try await makeProvider().openTasks() }
    }

    @Test func openTasks_signedOut_throwsSignedOut() async {
        await #expect(throws: TaskWriteError.signedOut) { try await makeProvider(signedIn: false).openTasks() }
        #expect(transport.requests.isEmpty)
    }

    @Test func openTasks_refreshRejected_throwsSignedOut() async {
        let expired = GitHubCredentials(accessToken: "gho_old", refreshToken: "ghr_old",
                                        accessExpiresAt: fixedNow.addingTimeInterval(-10), refreshExpiresAt: nil)
        let client = DeviceFlowClient(clientID: "client", transport: transport, sleep: { _ in }, now: { fixedNow })
        let tokens = TokenManager(store: MemoryCredentialStore(expired), client: client, now: { fixedNow })
        let provider = GitHubTaskProvider(api: GitHubAPI(transport: transport, tokens: tokens), tokens: tokens, cache: cache,
                                          selectedProjectIDs: { nil }, now: { fixedNow })
        transport.enqueueJSON("/login/oauth/access_token", #"{"error":"bad_refresh_token"}"#)
        await #expect(throws: TaskWriteError.signedOut) { try await provider.openTasks() }
    }

    @Test func openTasks_serverError_returnsCacheAndSetsOffline() async throws {
        cache.snapshot = ([makeRecord(placements: [makePlacement(makeProject(1))])], fixedNow.addingTimeInterval(-60))
        transport.enqueueJSON("/graphql", status: 502, "<html>bad gateway</html>")
        let provider = makeProvider()
        #expect(try await provider.openTasks().count == 1)
        #expect(provider.offlineSince == fixedNow.addingTimeInterval(-60))
    }

    @Test func openTasks_graphQLError_returnsCache() async throws {
        cache.snapshot = ([makeRecord(placements: [makePlacement(makeProject(1))])], fixedNow)
        transport.enqueueJSON("/graphql", #"{"errors":[{"message":"Something went wrong"}]}"#)
        #expect(try await makeProvider().openTasks().count == 1)
    }

    @Test func openTasks_tokenRefreshServerError_returnsCache() async throws {
        cache.snapshot = ([makeRecord(placements: [makePlacement(makeProject(1))])], fixedNow)
        let expired = GitHubCredentials(accessToken: "gho_old", refreshToken: "ghr_old",
                                        accessExpiresAt: fixedNow.addingTimeInterval(-10), refreshExpiresAt: nil)
        let client = DeviceFlowClient(clientID: "client", transport: transport, sleep: { _ in }, now: { fixedNow })
        let tokens = TokenManager(store: MemoryCredentialStore(expired), client: client, now: { fixedNow })
        let provider = GitHubTaskProvider(api: GitHubAPI(transport: transport, tokens: tokens), tokens: tokens, cache: cache,
                                          selectedProjectIDs: { nil }, now: { fixedNow })
        transport.enqueueJSON("/login/oauth/access_token", status: 503, "unavailable")
        #expect(try await provider.openTasks().count == 1)
        #expect(provider.offlineSince == fixedNow)
    }

    @Test func openTasks_respectsSelectedProjects() async throws {
        enqueueAllProjects()
        let items = try await makeProvider(selection: ["PVT_1"]).openTasks()
        let item = try #require(items.first)
        #expect(item.subContainers.map(\.id) == ["PVT_1"])
        #expect(item.due == DueDate(year: 2026, month: 11, day: 20))
    }

    @Test func openTasks_selectionWithoutIssues_isEmpty() async throws {
        enqueueAllProjects()
        #expect(try await makeProvider(selection: ["PVT_other"]).openTasks().isEmpty)
    }

    @Test func openTasks_nilSelection_usesDefaultSelection() async throws {
        enqueueAllProjects()
        let provider = makeProvider(selection: nil)
        let item = try #require(try await provider.openTasks().first)
        #expect(Set(item.subContainers.map(\.id)) == ["PVT_1", "PVT_2"])
        #expect(provider.defaultSelectedProjectIDs == ["PVT_1", "PVT_2", "PVT_foreign"])
    }
}

import Observation

@MainActor
struct GitHubTaskProviderObservationTests {
    /// Settings show login and projects; they must redraw when a load fills them.
    @Test func openTasks_notifiesObserversOfLoginAndProjects() async throws {
        let transport = StubTransport()
        Fixtures.enqueueAssignedIssues(on: transport)
        let credentials = GitHubCredentials(accessToken: "gho_valid", refreshToken: "ghr", accessExpiresAt: nil, refreshExpiresAt: nil)
        let client = DeviceFlowClient(clientID: "client", transport: transport, sleep: { _ in }, now: { fixedNow })
        let tokens = TokenManager(store: MemoryCredentialStore(credentials), client: client, now: { fixedNow })
        let provider = GitHubTaskProvider(api: GitHubAPI(transport: transport, tokens: tokens), tokens: tokens,
                                          cache: MemoryGitHubCache(), selectedProjectIDs: { nil }, now: { fixedNow })
        let changed = Flag()
        withObservationTracking {
            _ = provider.login
            _ = provider.projects
        } onChange: {
            changed.set()
        }
        _ = try await provider.openTasks()
        #expect(changed.value)
    }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.withLock { flag } }
    func set() { lock.withLock { flag = true } }
}
