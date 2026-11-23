import Foundation
import SecureStore
import Testing
import TagwerkCore
@testable import Tagwerk

extension BackupKeyStore {
    /// A store that lives in memory, so tests of the backup do not touch the Keychain of the simulator.
    static func inMemory() -> BackupKeyStore {
        final class Box: @unchecked Sendable { var value: String? }
        let box = Box()
        return BackupKeyStore(read: { box.value }, write: { box.value = $0 }, delete: { box.value = nil })
    }
}

struct BackupKeyStoreTests {
    private let secureStore = SecureStore(service: "com.melvinmng.tagwerk.tests.\(UUID().uuidString)")
    private let material = BackupCrypto.KeyMaterial(key: Data(repeating: 7, count: 32), salt: Data(repeating: 3, count: 16), iterations: 1_000)

    @Test func saveAndRead() throws {
        let store = BackupKeyStore(secureStore: secureStore)
        defer { try? store.remove() }
        #expect(store.material() == nil)
        try store.save(material)
        #expect(store.material() == material)
        // Saving again replaces the key (a changed password).
        let changed = BackupCrypto.KeyMaterial(key: Data(repeating: 8, count: 32), salt: Data(repeating: 4, count: 16), iterations: 1_000)
        try store.save(changed)
        #expect(store.material() == changed)
    }

    @Test func remove() throws {
        let store = BackupKeyStore(secureStore: secureStore)
        try store.save(material)
        try store.remove()
        #expect(store.material() == nil)
        // Removing a missing key is no error.
        try store.remove()
    }

    @Test func theKeychainItemHoldsTheKeyAndNeverAPassword() throws {
        let store = BackupKeyStore(secureStore: secureStore)
        defer { try? store.remove() }
        try store.save(material)
        let raw = try #require(try secureStore.string(for: BackupKeyStore.account))
        #expect(!raw.contains("password"))
        #expect(BackupKeyStore.account == "backup.key")
    }

    @Test func anUnreadableItem_isNoKey() throws {
        try secureStore.set("{broken", for: BackupKeyStore.account)
        defer { try? secureStore.remove(BackupKeyStore.account) }
        #expect(BackupKeyStore(secureStore: secureStore).material() == nil)
    }
}
