import Foundation

/// Hands out valid access tokens and refreshes them. At most one refresh runs at a time,
/// because GitHub refresh tokens are single-use: a second parallel refresh would sign the user out.
public actor TokenManager {
    /// Refresh errors after which the stored credentials are unusable.
    static let signOutErrors: Set<String> = ["bad_refresh_token", "incorrect_client_credentials"]

    private let store: CredentialStore
    private let client: DeviceFlowClient
    private let now: @Sendable () -> Date
    private var credentials: GitHubCredentials?
    private var didLoad = false
    private var refreshTask: Task<GitHubCredentials, Error>?

    public init(store: CredentialStore, client: DeviceFlowClient, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.client = client
        self.now = now
    }

    public var isSignedIn: Bool {
        get async { (try? current()) != nil }
    }

    /// A token that is valid for at least five more minutes, refreshing it if needed.
    public func validAccessToken() async throws -> String {
        guard let credentials = try current() else { throw GitHubAuthError.signedOut }
        guard credentials.needsRefresh(now: now()), credentials.refreshToken != nil else {
            return credentials.accessToken
        }
        return try await refreshed().accessToken
    }

    /// Called after HTTP 401. Refreshes unless the failed token was already replaced meanwhile.
    public func handleUnauthorized(failedToken: String) async throws -> String {
        guard let credentials = try current() else { throw GitHubAuthError.signedOut }
        if credentials.accessToken != failedToken { return credentials.accessToken }
        guard credentials.refreshToken != nil else {
            try clear()
            throw GitHubAuthError.signedOut
        }
        return try await refreshed().accessToken
    }

    public func store(_ credentials: GitHubCredentials) async throws {
        try store.save(credentials)
        self.credentials = credentials
        didLoad = true
    }

    public func signOut() async throws {
        refreshTask?.cancel()
        refreshTask = nil
        try clear()
    }

    // MARK: Private

    private func current() throws -> GitHubCredentials? {
        if !didLoad {
            credentials = try store.load()
            didLoad = true
        }
        return credentials
    }

    private func refreshed() async throws -> GitHubCredentials {
        if let running = refreshTask {
            return try await mapRefreshErrors { try await running.value }
        }
        guard let refreshToken = credentials?.refreshToken else { throw GitHubAuthError.signedOut }
        let client = self.client
        let task = Task { try await client.refresh(refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let fresh = try await task.value
            try store.save(fresh)
            credentials = fresh
            return fresh
        } catch GitHubAuthError.server(let code) where Self.signOutErrors.contains(code) {
            try? clear()
            throw GitHubAuthError.signedOut
        }
    }

    /// Callers that joined a running refresh see the same outcome as the caller that started it.
    private func mapRefreshErrors(_ operation: () async throws -> GitHubCredentials) async throws -> GitHubCredentials {
        do {
            return try await operation()
        } catch GitHubAuthError.server(let code) where Self.signOutErrors.contains(code) {
            throw GitHubAuthError.signedOut
        }
    }

    private func clear() throws {
        credentials = nil
        didLoad = true
        try store.delete()
    }
}
