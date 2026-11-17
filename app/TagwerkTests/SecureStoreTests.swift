import Foundation
import Testing
import SecureStore

/// Runs against the real keychain of the hosted app, each test with its own service.
struct SecureStoreTests {
    let store = SecureStore(service: "com.melvinmng.tagwerk.tests.\(UUID().uuidString)")

    @Test func set_thenRead_returnsValue() throws {
        defer { try? store.remove("account") }
        try store.set("wert-1", for: "account")
        #expect(try store.string(for: "account") == "wert-1")
    }

    @Test func set_twice_overwritesWithoutError() throws {
        defer { try? store.remove("account") }
        try store.set("alt", for: "account")
        try store.set("neu", for: "account")
        #expect(try store.string(for: "account") == "neu")
    }

    @Test func read_missing_returnsNil() throws {
        #expect(try store.string(for: "missing") == nil)
    }

    @Test func remove_missing_doesNotThrow() throws {
        try store.remove("missing")
    }

    @Test func remove_thenRead_returnsNil() throws {
        try store.set("wert", for: "account")
        try store.remove("account")
        #expect(try store.string(for: "account") == nil)
    }

    @Test func accounts_areIndependent() throws {
        defer { try? store.remove("a"); try? store.remove("b") }
        try store.set("eins", for: "a")
        try store.set("zwei", for: "b")
        #expect(try store.string(for: "a") == "eins")
        #expect(try store.string(for: "b") == "zwei")
    }
}
