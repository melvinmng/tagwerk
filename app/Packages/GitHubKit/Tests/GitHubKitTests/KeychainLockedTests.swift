import Foundation
import Testing
import TagwerkCore
@testable import GitHubKit

/// An unreadable keychain (device locked, prewarming before the first unlock) is never a sign-out.
@MainActor
struct KeychainLockedTests {
    let transport = StubTransport()
    let cache = MemoryGitHubCache()
    let credentials = GitHubCredentials(accessToken: "gho_valid", refreshToken: "ghr", accessExpiresAt: nil, refreshExpiresAt: nil)

    private func makeTokens(_ store: LockableCredentialStore) -> TokenManager {
        let client = DeviceFlowClient(clientID: "client", transport: transport, sleep: { _ in }, now: { fixedNow })
        return TokenManager(store: store, client: client, now: { fixedNow })
    }

    @Test func hasCredentials_storeThrows_rethrowsAndKeepsCredentials() async throws {
        let store = LockableCredentialStore(credentials)
        let tokens = makeTokens(store)
        await #expect(throws: GitHubAuthError.credentialsUnreadable) { try await tokens.hasCredentials() }
        #expect(store.deleteCount == 0)
        store.unlock()
        #expect(try await tokens.hasCredentials())
    }

    @Test func openTasks_keychainUnreadable_showsCacheAndKeepsSignIn() async throws {
        let cachedAt = fixedNow.addingTimeInterval(-3600)
        cache.snapshot = ([makeRecord(placements: [makePlacement(makeProject(1))])], cachedAt)
        let store = LockableCredentialStore(credentials)
        let tokens = makeTokens(store)
        let provider = GitHubTaskProvider(api: GitHubAPI(transport: transport, tokens: tokens), tokens: tokens, cache: cache,
                                          selectedProjectIDs: { nil }, now: { fixedNow })
        let tasks = try await provider.openTasks()
        #expect(tasks.map(\.title) == ["Login-Fehler beheben"])
        #expect(provider.offlineSince == cachedAt)
        #expect(provider.offlineReason == "Anmeldung derzeit nicht lesbar.")
        #expect(cache.snapshot != nil)
        #expect(store.deleteCount == 0)
        #expect(transport.requests.isEmpty)
    }

    @Test func openTasks_keychainUnreadableWithoutCache_failsWithoutSignOut() async {
        let store = LockableCredentialStore(credentials)
        let tokens = makeTokens(store)
        let provider = GitHubTaskProvider(api: GitHubAPI(transport: transport, tokens: tokens), tokens: tokens, cache: cache,
                                          selectedProjectIDs: { nil }, now: { fixedNow })
        await #expect(throws: TaskWriteError.failed("Anmeldung derzeit nicht lesbar.")) { try await provider.openTasks() }
        #expect(store.deleteCount == 0)
    }
}
