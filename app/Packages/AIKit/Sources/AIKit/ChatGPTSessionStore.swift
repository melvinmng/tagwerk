import Foundation

/// One sign-in attempt: the authorize URL plus the secrets needed to finish it.
public struct ChatGPTLoginAttempt: Sendable {
    public let url: URL
    let state: String
    let nonce: String
    let verifier: String
    let storedClientID: String?

    var isRegistration: Bool { storedClientID == nil }
}

/// Owns the ChatGPT session: hands out valid access tokens and refreshes them.
///
/// At most one refresh runs at a time, because the refresh token rotates: a second refresh with
/// the spent token would fail and sign the user out.
public actor ChatGPTSessionStore {
    private let store: ChatGPTCredentialStore
    private let transport: AIHTTPTransport
    private let now: @Sendable () -> Date
    private var tokens: ChatGPTTokens?
    private var didLoad = false
    private var refreshTask: Task<ChatGPTTokens, Error>?
    /// Incremented on sign-out and sign-in; a refresh that finishes afterwards must not store its tokens.
    private var session = 0

    public init(store: ChatGPTCredentialStore, transport: AIHTTPTransport, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.transport = transport
        self.now = now
    }

    public var isSignedIn: Bool { (try? current()) != nil }

    /// The e-mail address from the ID token, for display only.
    public var accountEmail: String? {
        (try? current())?.idToken.flatMap(ChatGPTAuth.idTokenClaims)?.email
    }

    /// The ChatGPT account the tokens belong to; some ChatGPT endpoints expect it as a header.
    var accountID: String? { (try? current())?.accountID }

    /// A token that is valid for at least five more minutes, refreshing it if needed.
    public func validAccessToken() async throws -> String {
        guard let tokens = try current() else { throw ChatGPTError.notSignedIn }
        guard tokens.needsRefresh(now: now()) else { return tokens.accessToken }
        return try await refreshed().accessToken
    }

    /// Called after HTTP 401. Refreshes unless the failed token was already replaced meanwhile.
    public func handleUnauthorized(failedToken: String) async throws -> String {
        guard let tokens = try current() else { throw ChatGPTError.notSignedIn }
        if tokens.accessToken != failedToken { return tokens.accessToken }
        return try await refreshed().accessToken
    }

    public func save(_ tokens: ChatGPTTokens) throws {
        session += 1
        refreshTask = nil
        self.tokens = tokens
        didLoad = true
        try store.saveTokens(tokens)
    }

    /// Deletes the tokens. The registered client and host ID stay for the next sign-in.
    public func signOut() throws {
        session += 1
        refreshTask?.cancel()
        refreshTask = nil
        try clear()
    }

    // MARK: Sign-in

    /// Prepares a sign-in: PKCE verifier, `state`, `nonce` and the authorize URL.
    public func beginLogin() throws -> ChatGPTLoginAttempt {
        let clientID = try store.loadClientID()
        let hostID: String
        if let stored = try store.loadHostID() {
            hostID = stored
        } else {
            hostID = "urn:uuid:\(UUID().uuidString.lowercased())"
            try store.saveHostID(hostID)
        }
        let verifier = ChatGPTAuth.randomURLSafeString()
        let state = ChatGPTAuth.randomURLSafeString(byteCount: 16)
        let nonce = ChatGPTAuth.randomURLSafeString(byteCount: 16)
        let url = ChatGPTAuth.authorizeURL(
            clientID: clientID, hostID: hostID, state: state, nonce: nonce,
            challenge: ChatGPTAuth.codeChallenge(verifier: verifier)
        )
        return ChatGPTLoginAttempt(url: url, state: state, nonce: nonce, verifier: verifier, storedClientID: clientID)
    }

    /// Exchanges the callback's code for tokens. A failure here never touches an existing session.
    public func completeLogin(callback: URL, attempt: ChatGPTLoginAttempt) async throws {
        let parsed = try ChatGPTAuth.parseCallback(callback, expectedState: attempt.state, isRegistration: attempt.isRegistration)
        if let stored = attempt.storedClientID, let returned = parsed.clientID, returned != stored {
            throw ChatGPTAuthError.clientIDMismatch
        }
        guard let clientID = attempt.storedClientID ?? parsed.clientID else { throw ChatGPTAuthError.missingIssuedClientID }

        let request = ChatGPTAuth.tokenRequest(clientID: clientID, code: parsed.code, verifier: attempt.verifier)
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            throw ChatGPTAuthError.network
        }
        switch ChatGPTAuth.parseTokenResponse(status: response.statusCode, body: data) {
        case .failure(let status, let code):
            throw ChatGPTAuthError.tokenExchangeFailed(status: status, code: code)
        case .tokens(let access, let refresh, let idToken, let expiresIn):
            let claims = idToken.flatMap(ChatGPTAuth.idTokenClaims)
            guard let claims, claims.nonce == attempt.nonce else { throw ChatGPTAuthError.nonceMismatch }
            guard let refresh else { throw ChatGPTAuthError.tokenExchangeFailed(status: 200, code: "missing_refresh_token") }
            // The issued client ID is stored only now, after a successful exchange.
            if attempt.isRegistration { try store.saveClientID(clientID) }
            try save(ChatGPTTokens(
                accessToken: access, refreshToken: refresh, idToken: idToken,
                expiresAt: now().addingTimeInterval(expiresIn ?? ChatGPTAuth.defaultLifetime),
                clientID: clientID, accountID: claims.accountID
            ))
        }
    }

    // MARK: Private

    private func current() throws -> ChatGPTTokens? {
        if !didLoad {
            tokens = try store.loadTokens()
            didLoad = true
        }
        return tokens
    }

    private func refreshed() async throws -> ChatGPTTokens {
        if let running = refreshTask {
            return try await running.value
        }
        guard let old = tokens else { throw ChatGPTError.notSignedIn }
        let transport = self.transport
        let now = self.now
        let startedIn = session
        let task = Task { try await Self.refresh(old, transport: transport, now: now) }
        refreshTask = task
        defer { if session == startedIn { refreshTask = nil } }
        do {
            let fresh = try await task.value
            guard session == startedIn else { throw ChatGPTError.notSignedIn }
            // Keep the rotated tokens in memory even if the keychain write fails: the old refresh token is spent.
            tokens = fresh
            try store.saveTokens(fresh)
            return fresh
        } catch ChatGPTError.notSignedIn {
            if session == startedIn { try? clear() }
            throw ChatGPTError.notSignedIn
        }
    }

    /// Calls the token endpoint. Throws `.notSignedIn` when the server rejects the refresh token
    /// (an OAuth error with HTTP 400 or 401); server errors and transport failures keep the session.
    private static func refresh(_ old: ChatGPTTokens, transport: AIHTTPTransport,
                                now: @Sendable () -> Date) async throws -> ChatGPTTokens {
        let request = ChatGPTAuth.refreshRequest(clientID: old.clientID, refreshToken: old.refreshToken)
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            throw ChatGPTError.network
        }
        switch ChatGPTAuth.parseTokenResponse(status: response.statusCode, body: data) {
        case .tokens(let access, let refresh, let idToken, let expiresIn):
            return ChatGPTTokens(
                accessToken: access,
                refreshToken: refresh ?? old.refreshToken,
                idToken: idToken ?? old.idToken,
                expiresAt: now().addingTimeInterval(expiresIn ?? ChatGPTAuth.defaultLifetime),
                clientID: old.clientID,
                accountID: idToken.flatMap(ChatGPTAuth.idTokenClaims)?.accountID ?? old.accountID
            )
        case .failure(let status, let code):
            if (status == 400 || status == 401) && code != nil { throw ChatGPTError.notSignedIn }
            throw ChatGPTError.server(status, code)
        }
    }

    private func clear() throws {
        tokens = nil
        didLoad = true
        try store.deleteTokens()
    }
}
