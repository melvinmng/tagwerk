import Foundation
import Testing
@testable import AIKit

struct ChatGPTSessionStoreTests {
    let transport = StubAITransport()
    static let tokenPath = "/api/accounts/oauth/token"

    let valid = ChatGPTTokens(accessToken: "at_valid", refreshToken: "rt_valid", idToken: nil,
                              expiresAt: fixedNow.addingTimeInterval(3600), clientID: "oaiapp_1", accountID: nil)
    let expiring = ChatGPTTokens(accessToken: "at_old", refreshToken: "rt_old", idToken: nil,
                                 expiresAt: fixedNow.addingTimeInterval(120), clientID: "oaiapp_1", accountID: nil)
    let refreshReply = #"{"access_token":"at_new","refresh_token":"rt_new","expires_in":7200}"#

    func makeSession(_ store: some ChatGPTCredentialStore) -> ChatGPTSessionStore {
        ChatGPTSessionStore(store: store, transport: transport, now: { fixedNow })
    }

    // MARK: Access tokens and refresh

    @Test func validAccessToken_freshToken_noRefresh() async throws {
        let session = makeSession(InMemoryChatGPTCredentialStore(tokens: valid))
        #expect(try await session.validAccessToken() == "at_valid")
        #expect(transport.requests.isEmpty)
    }

    @Test func validAccessToken_signedOut_throwsNotSignedIn() async {
        let session = makeSession(InMemoryChatGPTCredentialStore())
        await #expect(throws: ChatGPTError.notSignedIn) { try await session.validAccessToken() }
        #expect(await session.isSignedIn == false)
    }

    @Test func validAccessToken_expiringSoon_refreshesOnce_evenWithTwoCallers() async throws {
        transport.enqueue(Self.tokenPath, .gated(200, refreshReply))
        transport.enqueueJSON(Self.tokenPath, status: 400, #"{"error":"invalid_grant"}"#)
        let store = InMemoryChatGPTCredentialStore(tokens: expiring)
        let session = makeSession(store)

        async let first = session.validAccessToken()
        async let second = session.validAccessToken()
        try await Task.sleep(for: .milliseconds(50))
        transport.release()
        let tokens = try await [first, second]

        #expect(tokens == ["at_new", "at_new"])
        #expect(transport.requests(to: Self.tokenPath).count == 1)
        #expect(store.tokens?.refreshToken == "rt_new")
        #expect(store.tokenSaveCount == 1)
    }

    @Test func refresh_sendsStoredClientIDAndRefreshToken() async throws {
        transport.enqueueJSON(Self.tokenPath, refreshReply)
        _ = try await makeSession(InMemoryChatGPTCredentialStore(tokens: expiring)).validAccessToken()
        let fields = try #require(transport.requests.first).bodyFields
        #expect(fields.contains("client_id=oaiapp_1"))
        #expect(fields.contains("refresh_token=rt_old"))
    }

    @Test func refresh_withoutNewRefreshToken_keepsOldOne() async throws {
        transport.enqueueJSON(Self.tokenPath, #"{"access_token":"at_new","expires_in":7200}"#)
        let store = InMemoryChatGPTCredentialStore(tokens: expiring)
        _ = try await makeSession(store).validAccessToken()
        #expect(store.tokens?.refreshToken == "rt_old")
        #expect(store.tokens?.expiresAt == fixedNow.addingTimeInterval(7200))
    }

    @Test func refresh_withoutExpiresIn_defaultsToOneHour() async throws {
        transport.enqueueJSON(Self.tokenPath, #"{"access_token":"at_new","refresh_token":"rt_new"}"#)
        let store = InMemoryChatGPTCredentialStore(tokens: expiring)
        _ = try await makeSession(store).validAccessToken()
        #expect(store.tokens?.expiresAt == fixedNow.addingTimeInterval(3600))
    }

    @Test func refresh_invalidGrant_signsOut() async {
        transport.enqueueJSON(Self.tokenPath, status: 400, #"{"error":"invalid_grant","error_description":"spent"}"#)
        let store = InMemoryChatGPTCredentialStore(tokens: expiring)
        let session = makeSession(store)
        await #expect(throws: ChatGPTError.notSignedIn) { try await session.validAccessToken() }
        #expect(store.tokens == nil)
        #expect(await session.isSignedIn == false)
    }

    @Test func refresh_otherOAuthErrorWith401_signsOut() async {
        transport.enqueueJSON(Self.tokenPath, status: 401, #"{"error":{"code":"refresh_token_expired","message":"x"}}"#)
        let store = InMemoryChatGPTCredentialStore(tokens: expiring)
        await #expect(throws: ChatGPTError.notSignedIn) { try await makeSession(store).validAccessToken() }
        #expect(store.tokens == nil)
    }

    @Test func refresh_serverError_keepsSession() async {
        transport.enqueueJSON(Self.tokenPath, status: 503, #"{"error":"temporarily_unavailable"}"#)
        let store = InMemoryChatGPTCredentialStore(tokens: expiring)
        await #expect(throws: ChatGPTError.server(503, "temporarily_unavailable")) {
            try await makeSession(store).validAccessToken()
        }
        #expect(store.tokens == expiring)
    }

    @Test func refresh_networkError_keepsSession() async {
        transport.enqueue(Self.tokenPath, .failure(.notConnectedToInternet))
        let store = InMemoryChatGPTCredentialStore(tokens: expiring)
        let session = makeSession(store)
        await #expect(throws: ChatGPTError.network) { try await session.validAccessToken() }
        #expect(store.tokens == expiring)
        #expect(await session.isSignedIn)
    }

    @Test func refresh_keychainWriteFails_keepsRotatedTokensInMemory() async throws {
        transport.enqueueJSON(Self.tokenPath, refreshReply)
        let store = FailingTokenWriteStore()
        store.inner.setTokens(expiring)
        let session = makeSession(store)
        await #expect(throws: (any Error).self) { try await session.validAccessToken() }
        #expect(try await session.validAccessToken() == "at_new")
        #expect(transport.requests.count == 1)
    }

    @Test func handleUnauthorized_refreshesCurrentToken() async throws {
        transport.enqueueJSON(Self.tokenPath, refreshReply)
        let session = makeSession(InMemoryChatGPTCredentialStore(tokens: valid))
        #expect(try await session.handleUnauthorized(failedToken: "at_valid") == "at_new")
    }

    @Test func handleUnauthorized_tokenAlreadyReplaced_noSecondRefresh() async throws {
        transport.enqueueJSON(Self.tokenPath, refreshReply)
        let session = makeSession(InMemoryChatGPTCredentialStore(tokens: valid))
        let first = try await session.handleUnauthorized(failedToken: "at_valid")
        let second = try await session.handleUnauthorized(failedToken: "at_valid")
        #expect(first == "at_new")
        #expect(second == "at_new")
        #expect(transport.requests.count == 1)
    }

    @Test func signOutDuringRefresh_doesNotStoreTokens() async throws {
        transport.enqueue(Self.tokenPath, .gated(200, refreshReply))
        let store = InMemoryChatGPTCredentialStore(tokens: expiring)
        let session = makeSession(store)

        let pending = Task { try await session.validAccessToken() }
        try await Task.sleep(for: .milliseconds(50))
        try await session.signOut()
        transport.release()

        await #expect(throws: ChatGPTError.notSignedIn) { try await pending.value }
        #expect(store.tokens == nil)
        #expect(await session.isSignedIn == false)
    }

    @Test func signOut_keepsClientIDAndHostID() async throws {
        let store = InMemoryChatGPTCredentialStore(tokens: valid, clientID: "oaiapp_1", hostID: "urn:uuid:h")
        try await makeSession(store).signOut()
        #expect(store.tokens == nil)
        #expect(try store.loadClientID() == "oaiapp_1")
        #expect(try store.loadHostID() == "urn:uuid:h")
    }

    @Test func tokens_areOneKeychainEntry() async throws {
        transport.enqueueJSON(Self.tokenPath, refreshReply)
        let store = InMemoryChatGPTCredentialStore(tokens: expiring)
        _ = try await makeSession(store).validAccessToken()
        // Access token, refresh token and expiry are written together in one save.
        #expect(store.tokenSaveCount == 1)
        #expect(store.tokens?.accessToken == "at_new")
        #expect(store.tokens?.refreshToken == "rt_new")
        #expect(store.clientIDSaveCount == 0)
    }

    // MARK: Login

    func loginReply(nonce: String, access: String = "at_login") -> String {
        let idToken = makeJWT(["nonce": nonce, "email": "person@example.com",
                               "https://api.openai.com/auth": ["chatgpt_account_id": "acct-1"]])
        return #"{"access_token":"\#(access)","refresh_token":"rt_login","id_token":"\#(idToken)","expires_in":3600}"#
    }

    func callbackURL(_ attempt: ChatGPTLoginAttempt, clientID: String? = "oaiapp_new") -> URL {
        var components = URLComponents(string: "http://127.0.0.1:1455/auth/callback")!
        components.queryItems = [URLQueryItem(name: "code", value: "code1"), URLQueryItem(name: "state", value: attempt.state)]
            + (clientID.map { [URLQueryItem(name: "client_id", value: $0)] } ?? [])
        return components.url!
    }

    @Test func beginLogin_firstTime_isRegistrationAndCreatesHostID() async throws {
        let store = InMemoryChatGPTCredentialStore()
        let attempt = try await makeSession(store).beginLogin()
        #expect(attempt.isRegistration)
        let hostID = try #require(try store.loadHostID())
        #expect(hostID.hasPrefix("urn:uuid:"))
        let again = try await makeSession(store).beginLogin()
        #expect(again.url.absoluteString.contains(hostID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!))
    }

    @Test func beginLogin_withStoredClientID_reauthorizes() async throws {
        let store = InMemoryChatGPTCredentialStore(clientID: "oaiapp_1", hostID: "urn:uuid:h")
        let attempt = try await makeSession(store).beginLogin()
        #expect(!attempt.isRegistration)
        #expect(attempt.url.absoluteString.contains("client_id=oaiapp_1"))
    }

    @Test func completeLogin_storesClientIDAndTokens() async throws {
        let store = InMemoryChatGPTCredentialStore()
        let session = makeSession(store)
        let attempt = try await session.beginLogin()
        transport.enqueueJSON(Self.tokenPath, loginReply(nonce: attempt.nonce))

        try await session.completeLogin(callback: callbackURL(attempt), attempt: attempt)

        #expect(try store.loadClientID() == "oaiapp_new")
        #expect(store.tokens?.accessToken == "at_login")
        #expect(store.tokens?.clientID == "oaiapp_new")
        #expect(store.tokens?.accountID == "acct-1")
        #expect(await session.accountEmail == "person@example.com")
        #expect(try await session.validAccessToken() == "at_login")
        let fields = try #require(transport.requests.first).bodyFields
        #expect(fields.contains("code_verifier=\(attempt.verifier)"))
    }

    @Test func nonceClaim_mismatch_rejectsLogin() async throws {
        let store = InMemoryChatGPTCredentialStore()
        let session = makeSession(store)
        let attempt = try await session.beginLogin()
        transport.enqueueJSON(Self.tokenPath, loginReply(nonce: "other"))

        await #expect(throws: ChatGPTAuthError.nonceMismatch) {
            try await session.completeLogin(callback: callbackURL(attempt), attempt: attempt)
        }
        #expect(store.tokens == nil)
        #expect(try store.loadClientID() == nil)
    }

    @Test func clientID_notStoredWhenExchangeFails() async throws {
        let store = InMemoryChatGPTCredentialStore()
        let session = makeSession(store)
        let attempt = try await session.beginLogin()
        transport.enqueueJSON(Self.tokenPath, status: 400, #"{"error":"invalid_request"}"#)

        await #expect(throws: ChatGPTAuthError.tokenExchangeFailed(status: 400, code: "invalid_request")) {
            try await session.completeLogin(callback: callbackURL(attempt), attempt: attempt)
        }
        #expect(try store.loadClientID() == nil)
    }

    @Test func login_invalidGrant_keepsExistingSession() async throws {
        let store = InMemoryChatGPTCredentialStore(tokens: valid, clientID: "oaiapp_1", hostID: "urn:uuid:h")
        let session = makeSession(store)
        let attempt = try await session.beginLogin()
        transport.enqueueJSON(Self.tokenPath, status: 400, #"{"error":"invalid_grant"}"#)

        await #expect(throws: ChatGPTAuthError.tokenExchangeFailed(status: 400, code: "invalid_grant")) {
            try await session.completeLogin(callback: callbackURL(attempt, clientID: nil), attempt: attempt)
        }
        #expect(store.tokens == valid)
        #expect(await session.isSignedIn)
    }

    @Test func completeLogin_differentClientIDThanStored_rejected() async throws {
        let store = InMemoryChatGPTCredentialStore(clientID: "oaiapp_1", hostID: "urn:uuid:h")
        let session = makeSession(store)
        let attempt = try await session.beginLogin()

        await #expect(throws: ChatGPTAuthError.clientIDMismatch) {
            try await session.completeLogin(callback: callbackURL(attempt, clientID: "oaiapp_other"), attempt: attempt)
        }
        #expect(transport.requests.isEmpty)
    }
}
