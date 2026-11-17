import AIKit
import Foundation
import SecureStore

/// Stores the ChatGPT tokens as one JSON keychain item. Client ID and host ID are separate items
/// that survive sign-out.
struct KeychainChatGPTCredentialStore: ChatGPTCredentialStore {
    static let tokensAccount = "chatgpt.tokens"
    static let clientIDAccount = "chatgpt.client-id"
    static let hostIDAccount = "chatgpt.host-id"
    private let secureStore: SecureStore

    init(secureStore: SecureStore = SecureStore()) {
        self.secureStore = secureStore
    }

    func loadTokens() throws -> ChatGPTTokens? {
        guard let json = try secureStore.string(for: Self.tokensAccount) else { return nil }
        return try JSONDecoder().decode(ChatGPTTokens.self, from: Data(json.utf8))
    }

    func saveTokens(_ tokens: ChatGPTTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        try secureStore.set(String(decoding: data, as: UTF8.self), for: Self.tokensAccount)
    }

    func deleteTokens() throws {
        try secureStore.remove(Self.tokensAccount)
    }

    func loadClientID() throws -> String? { try secureStore.string(for: Self.clientIDAccount) }
    func saveClientID(_ clientID: String) throws { try secureStore.set(clientID, for: Self.clientIDAccount) }
    func loadHostID() throws -> String? { try secureStore.string(for: Self.hostIDAccount) }
    func saveHostID(_ hostID: String) throws { try secureStore.set(hostID, for: Self.hostIDAccount) }
}
