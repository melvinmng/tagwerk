import Foundation
import Synchronization

/// The ChatGPT session tokens, stored together as one keychain entry so they never get out of sync.
public struct ChatGPTTokens: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var idToken: String?
    public var expiresAt: Date
    public var clientID: String
    public var accountID: String?

    public init(accessToken: String, refreshToken: String, idToken: String?, expiresAt: Date,
                clientID: String, accountID: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.expiresAt = expiresAt
        self.clientID = clientID
        self.accountID = accountID
    }

    /// True when the access token expires within five minutes.
    public func needsRefresh(now: Date) -> Bool {
        expiresAt.timeIntervalSince(now) < 300
    }
}

extension ChatGPTTokens: CustomStringConvertible, CustomDebugStringConvertible {
    /// Never reveals token values (logs, crash reports, debugger output).
    public var description: String {
        "ChatGPTTokens(accessToken: <redacted>, refreshToken: <redacted>, expiresAt: \(expiresAt))"
    }

    public var debugDescription: String { description }
}

/// Persistence of the ChatGPT session (keychain in the app, memory in tests).
///
/// The tokens are one entry that sign-out deletes. The issued `client_id` and the
/// `ext_agent_host_id` are separate entries that survive sign-out, so a later sign-in
/// re-authorizes the same registered client instead of registering a new one.
public protocol ChatGPTCredentialStore: Sendable {
    func loadTokens() throws -> ChatGPTTokens?
    func saveTokens(_ tokens: ChatGPTTokens) throws
    func deleteTokens() throws
    func loadClientID() throws -> String?
    func saveClientID(_ clientID: String) throws
    func loadHostID() throws -> String?
    func saveHostID(_ hostID: String) throws
}

/// Credential store in memory, for tests and the simulator demo mode.
public final class InMemoryChatGPTCredentialStore: ChatGPTCredentialStore {
    private struct State {
        var tokens: ChatGPTTokens?
        var clientID: String?
        var hostID: String?
        var tokenSaves = 0
        var clientIDSaves = 0
    }

    private let state: Mutex<State>

    public init(tokens: ChatGPTTokens? = nil, clientID: String? = nil, hostID: String? = nil) {
        state = Mutex(State(tokens: tokens, clientID: clientID, hostID: hostID))
    }

    public var tokens: ChatGPTTokens? { state.withLock { $0.tokens } }
    public var tokenSaveCount: Int { state.withLock { $0.tokenSaves } }
    public var clientIDSaveCount: Int { state.withLock { $0.clientIDSaves } }

    /// Replaces the tokens without counting a save.
    public func setTokens(_ tokens: ChatGPTTokens?) { state.withLock { $0.tokens = tokens } }

    public func loadTokens() throws -> ChatGPTTokens? { tokens }
    public func saveTokens(_ tokens: ChatGPTTokens) throws {
        state.withLock { $0.tokens = tokens; $0.tokenSaves += 1 }
    }
    public func deleteTokens() throws { state.withLock { $0.tokens = nil } }
    public func loadClientID() throws -> String? { state.withLock { $0.clientID } }
    public func saveClientID(_ clientID: String) throws {
        state.withLock { $0.clientID = clientID; $0.clientIDSaves += 1 }
    }
    public func loadHostID() throws -> String? { state.withLock { $0.hostID } }
    public func saveHostID(_ hostID: String) throws { state.withLock { $0.hostID = hostID } }
}
