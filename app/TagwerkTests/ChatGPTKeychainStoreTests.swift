import AIKit
import Foundation
import SecureStore
import Testing
@testable import Tagwerk

struct KeychainChatGPTCredentialStoreTests {
    let secureStore = SecureStore(service: "com.melvinmng.tagwerk.tests.\(UUID().uuidString)")
    var store: KeychainChatGPTCredentialStore { KeychainChatGPTCredentialStore(secureStore: secureStore) }
    let tokens = ChatGPTTokens(accessToken: "at_test", refreshToken: "rt_test", idToken: nil,
                               expiresAt: Date(timeIntervalSince1970: 100), clientID: "oaiapp_test", accountID: nil)

    @Test func tokens_areOneKeychainEntry() throws {
        defer { try? store.deleteTokens() }
        try store.saveTokens(tokens)
        let raw = try #require(try secureStore.string(for: KeychainChatGPTCredentialStore.tokensAccount))
        #expect(raw.contains("at_test"))
        #expect(raw.contains("rt_test"))
        #expect(try store.loadTokens() == tokens)
    }

    @Test func deleteTokens_keepsClientAndHostID() throws {
        defer {
            try? secureStore.remove(KeychainChatGPTCredentialStore.clientIDAccount)
            try? secureStore.remove(KeychainChatGPTCredentialStore.hostIDAccount)
        }
        try store.saveTokens(tokens)
        try store.saveClientID("oaiapp_test")
        try store.saveHostID("urn:uuid:test")
        try store.deleteTokens()
        #expect(try store.loadTokens() == nil)
        #expect(try store.loadClientID() == "oaiapp_test")
        #expect(try store.loadHostID() == "urn:uuid:test")
    }
}
