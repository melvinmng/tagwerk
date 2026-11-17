import Foundation
import Testing
@testable import GitHubKit

struct TokenManagerTests {
    let transport = StubTransport()
    let expired = GitHubCredentials(accessToken: "gho_old", refreshToken: "ghr_old",
                                    accessExpiresAt: fixedNow.addingTimeInterval(-10), refreshExpiresAt: nil)
    let valid = GitHubCredentials(accessToken: "gho_valid", refreshToken: "ghr_valid",
                                  accessExpiresAt: fixedNow.addingTimeInterval(3600), refreshExpiresAt: nil)
    let refreshReply = """
    {"access_token":"gho_new","expires_in":28800,"refresh_token":"ghr_new","refresh_token_expires_in":15638400}
    """

    func makeManager(_ store: MemoryCredentialStore) -> TokenManager {
        let client = DeviceFlowClient(clientID: "client", transport: transport, sleep: { _ in }, now: { fixedNow })
        return TokenManager(store: store, client: client, now: { fixedNow })
    }

    @Test func validToken_isReturnedWithoutRefresh() async throws {
        let manager = makeManager(MemoryCredentialStore(valid))
        #expect(try await manager.validAccessToken() == "gho_valid")
        #expect(transport.requests.isEmpty)
    }

    @Test func signedOut_throwsSignedOut() async {
        let manager = makeManager(MemoryCredentialStore())
        await #expect(throws: GitHubAuthError.signedOut) { try await manager.validAccessToken() }
        #expect(await manager.isSignedIn == false)
    }

    @Test func tokenManager_concurrentCallsWithExpiredToken_refreshOnce() async throws {
        transport.enqueueJSON("/login/oauth/access_token", refreshReply)
        transport.enqueueJSON("/login/oauth/access_token", #"{"error":"bad_refresh_token"}"#)
        let store = MemoryCredentialStore(expired)
        let manager = makeManager(store)

        async let first = manager.validAccessToken()
        async let second = manager.validAccessToken()
        let tokens = try await [first, second]

        #expect(tokens == ["gho_new", "gho_new"])
        #expect(transport.requests.count == 1)
        #expect(store.current?.refreshToken == "ghr_new")
        #expect(store.saveCount == 1)
    }

    @Test func handleUnauthorized_withStaleToken_doesNotRefreshAgain() async throws {
        transport.enqueueJSON("/login/oauth/access_token", refreshReply)
        let manager = makeManager(MemoryCredentialStore(valid))
        let first = try await manager.handleUnauthorized(failedToken: "gho_valid")
        let second = try await manager.handleUnauthorized(failedToken: "gho_valid")
        #expect(first == "gho_new")
        #expect(second == "gho_new")
        #expect(transport.requests.count == 1)
    }

    @Test func tokenManager_refreshBadRefreshToken_signsOut() async {
        transport.enqueueJSON("/login/oauth/access_token", #"{"error":"bad_refresh_token"}"#)
        let store = MemoryCredentialStore(expired)
        let manager = makeManager(store)
        await #expect(throws: GitHubAuthError.signedOut) { try await manager.validAccessToken() }
        #expect(store.current == nil)
        #expect(await manager.isSignedIn == false)
    }

    @Test func tokenManager_refreshIncorrectClientCredentials_signsOut() async {
        transport.enqueueJSON("/login/oauth/access_token", #"{"error":"incorrect_client_credentials"}"#)
        let store = MemoryCredentialStore(expired)
        await #expect(throws: GitHubAuthError.signedOut) { try await makeManager(store).validAccessToken() }
        #expect(store.current == nil)
    }

    @Test func tokenManager_refreshNetworkError_keepsCredentials() async {
        transport.enqueue("/login/oauth/access_token", .failure(.notConnectedToInternet))
        let store = MemoryCredentialStore(expired)
        let manager = makeManager(store)
        do {
            _ = try await manager.validAccessToken()
            Issue.record("expected a network error")
        } catch GitHubAuthError.network {
            // expected
        } catch {
            Issue.record("expected .network, got \(error)")
        }
        #expect(store.current == expired)
        #expect(await manager.isSignedIn)
    }

    @Test func tokenManager_serverError_keepsCredentials() async {
        transport.enqueueJSON("/login/oauth/access_token", status: 502, "<html>bad gateway</html>")
        let store = MemoryCredentialStore(expired)
        await #expect(throws: GitHubAuthError.self) { try await makeManager(store).validAccessToken() }
        #expect(store.current == expired)
    }

    @Test func handleUnauthorized_withoutRefreshToken_signsOut() async {
        let store = MemoryCredentialStore(GitHubCredentials(accessToken: "gho_x", refreshToken: nil, accessExpiresAt: nil, refreshExpiresAt: nil))
        await #expect(throws: GitHubAuthError.signedOut) {
            try await makeManager(store).handleUnauthorized(failedToken: "gho_x")
        }
        #expect(store.current == nil)
    }

    @Test func store_thenSignOut() async throws {
        let store = MemoryCredentialStore()
        let manager = makeManager(store)
        try await manager.store(valid)
        #expect(await manager.isSignedIn)
        #expect(try await manager.validAccessToken() == "gho_valid")
        try await manager.signOut()
        #expect(store.current == nil)
        #expect(await manager.isSignedIn == false)
    }
}
