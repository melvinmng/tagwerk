import Foundation
import GitHubKit
import SecureStore

/// Stores GitHub credentials as one JSON keychain item.
struct KeychainCredentialStore: CredentialStore {
    static let account = "github.credentials"
    private let secureStore: SecureStore

    init(secureStore: SecureStore = SecureStore()) {
        self.secureStore = secureStore
    }

    func load() throws -> GitHubCredentials? {
        guard let json = try secureStore.string(for: Self.account) else { return nil }
        return try JSONDecoder().decode(GitHubCredentials.self, from: Data(json.utf8))
    }

    func save(_ credentials: GitHubCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        try secureStore.set(String(decoding: data, as: UTF8.self), for: Self.account)
    }

    func delete() throws {
        try secureStore.remove(Self.account)
    }
}
