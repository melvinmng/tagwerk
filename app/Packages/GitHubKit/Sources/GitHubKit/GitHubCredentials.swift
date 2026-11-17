import Foundation

/// GitHub OAuth tokens, stored together as one keychain item so they never get out of sync.
public struct GitHubCredentials: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var accessExpiresAt: Date?
    public var refreshExpiresAt: Date?

    public init(accessToken: String, refreshToken: String?, accessExpiresAt: Date?, refreshExpiresAt: Date?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessExpiresAt = accessExpiresAt
        self.refreshExpiresAt = refreshExpiresAt
    }

    /// True when the access token expires within five minutes. Tokens without expiry never need a refresh.
    public func needsRefresh(now: Date) -> Bool {
        guard let accessExpiresAt else { return false }
        return accessExpiresAt.timeIntervalSince(now) < 300
    }
}

extension GitHubCredentials: CustomStringConvertible, CustomDebugStringConvertible {
    /// Never reveals token values (logs, crash reports, debugger output).
    public var description: String {
        "GitHubCredentials(accessToken: <redacted>, refreshToken: \(refreshToken == nil ? "nil" : "<redacted>"), "
            + "accessExpiresAt: \(accessExpiresAt.map(String.init(describing:)) ?? "nil"))"
    }

    public var debugDescription: String { description }
}

/// Errors of login and token handling.
public enum GitHubAuthError: Error, Equatable, Sendable {
    /// The device code expired before the user confirmed it.
    case expired
    /// The user declined the authorization.
    case denied
    /// No usable credentials; the user has to sign in again.
    case signedOut
    case network(String)
    case server(String)
}

/// Persistence of credentials (keychain in the app, memory in tests).
public protocol CredentialStore: Sendable {
    func load() throws -> GitHubCredentials?
    func save(_ credentials: GitHubCredentials) throws
    func delete() throws
}
