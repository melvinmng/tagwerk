import Foundation

struct ChatGPTSession: Codable {
    var clientID: String
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

struct ChatGPTSignInAttempt: Sendable {
    let url: URL
    let state: String
    let verifier: String
    let isRegistration: Bool
}

/// Keeps the ChatGPT plan session in the Keychain and refreshes the rotating tokens.
actor ChatGPTSessionStore {
    static let shared = ChatGPTSessionStore()

    private let sessionAccount = "chatgpt-session"
    private let hostIDAccount = "chatgpt-host-id"
    private let clientIDAccount = "chatgpt-client-id"

    var isSignedIn: Bool { loadSession() != nil }

    func beginSignIn() -> ChatGPTSignInAttempt {
        let clientID = Secrets.load(account: clientIDAccount)
        let verifier = ChatGPTAuth.randomURLSafeString()
        let state = ChatGPTAuth.randomURLSafeString(byteCount: 16)
        let url = ChatGPTAuth.authorizeURL(
            clientID: clientID, hostID: hostID(), state: state,
            nonce: ChatGPTAuth.randomURLSafeString(byteCount: 16),
            challenge: ChatGPTAuth.codeChallenge(verifier: verifier)
        )
        return ChatGPTSignInAttempt(url: url, state: state, verifier: verifier, isRegistration: clientID == nil)
    }

    func completeSignIn(callbackURL: URL, attempt: ChatGPTSignInAttempt) async throws {
        let callback = try ChatGPTAuth.parseCallback(callbackURL, expectedState: attempt.state, isRegistration: attempt.isRegistration)
        let storedClientID = Secrets.load(account: clientIDAccount)
        if let storedClientID, let returned = callback.clientID, returned != storedClientID {
            throw ChatGPTAuthError.serverError("abweichende client_id im Rücksprung")
        }
        guard let clientID = storedClientID ?? callback.clientID else { throw ChatGPTAuthError.missingIssuedClientID }
        try Secrets.save(clientID, account: clientIDAccount)
        let request = ChatGPTAuth.tokenRequest(clientID: clientID, code: callback.code, verifier: attempt.verifier)
        try await exchange(request, clientID: clientID)
    }

    /// Returns a usable access token, refreshing it when it expires within a minute.
    func validAccessToken() async throws -> String? {
        guard let session = loadSession() else { return nil }
        if session.expiresAt.timeIntervalSinceNow > 60 { return session.accessToken }
        return try await refresh().accessToken
    }

    /// Forces a refresh and reports whether the refresh token was rotated.
    func forceRefresh() async throws -> Bool {
        guard let before = loadSession() else { throw ChatGPTAuthError.serverError("nicht angemeldet") }
        let after = try await refresh()
        return after.refreshToken != before.refreshToken
    }

    func signOut() {
        try? Secrets.save("", account: sessionAccount)
    }

    private func refresh() async throws -> ChatGPTSession {
        guard let session = loadSession() else { throw ChatGPTAuthError.serverError("nicht angemeldet") }
        let request = ChatGPTAuth.refreshRequest(clientID: session.clientID, refreshToken: session.refreshToken)
        return try await exchange(request, clientID: session.clientID, previousRefreshToken: session.refreshToken)
    }

    @discardableResult
    private func exchange(_ request: URLRequest, clientID: String, previousRefreshToken: String? = nil) async throws -> ChatGPTSession {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard status == 200, let access = json["access_token"] as? String else {
            let message = json["error_description"] as? String ?? json["error"] as? String ?? "HTTP \(status)"
            if json["error"] as? String == "invalid_grant" { signOut() }
            throw ChatGPTAuthError.serverError(message)
        }
        let session = ChatGPTSession(
            clientID: clientID,
            accessToken: access,
            refreshToken: json["refresh_token"] as? String ?? previousRefreshToken ?? "",
            expiresAt: Date().addingTimeInterval(json["expires_in"] as? TimeInterval ?? 3600)
        )
        // Store immediately: the refresh token rotates and the old one becomes invalid.
        try Secrets.save(String(decoding: try JSONEncoder().encode(session), as: UTF8.self), account: sessionAccount)
        return session
    }

    private func loadSession() -> ChatGPTSession? {
        guard let raw = Secrets.load(account: sessionAccount), !raw.isEmpty else { return nil }
        return try? JSONDecoder().decode(ChatGPTSession.self, from: Data(raw.utf8))
    }

    private func hostID() -> String {
        if let existing = Secrets.load(account: hostIDAccount) { return existing }
        let created = "urn:uuid:\(UUID().uuidString.lowercased())"
        try? Secrets.save(created, account: hostIDAccount)
        return created
    }
}
