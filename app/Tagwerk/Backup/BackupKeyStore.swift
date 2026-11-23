import Foundation
import SecureStore
import TagwerkCore

/// The key of the backup password in the Keychain of this iPhone (after first unlock, this device only), so the automatic
/// backup can encrypt without asking. The password itself is never stored. The key is not part of any backup: on another iPhone
/// the password is asked for when a file is opened.
struct BackupKeyStore {
    static let account = "backup.key"

    private struct Stored: Codable {
        var key: Data
        var salt: Data
        var iterations: Int
    }

    private let read: () throws -> String?
    private let write: (String) throws -> Void
    private let delete: () throws -> Void

    init(secureStore: SecureStore = SecureStore()) {
        read = { try secureStore.string(for: Self.account) }
        write = { try secureStore.set($0, for: Self.account) }
        delete = { try secureStore.remove(Self.account) }
    }

    /// Any other storage, for tests.
    init(read: @escaping () throws -> String?, write: @escaping (String) throws -> Void, delete: @escaping () throws -> Void) {
        self.read = read
        self.write = write
        self.delete = delete
    }

    /// The stored key with its salt and iteration count; `nil` without a key or when the item cannot be read.
    func material() -> BackupCrypto.KeyMaterial? {
        guard let json = (try? read()) ?? nil, let stored = try? JSONDecoder().decode(Stored.self, from: Data(json.utf8)) else { return nil }
        return BackupCrypto.KeyMaterial(key: stored.key, salt: stored.salt, iterations: stored.iterations)
    }

    func save(_ material: BackupCrypto.KeyMaterial) throws {
        let data = try JSONEncoder().encode(Stored(key: material.key, salt: material.salt, iterations: material.iterations))
        try write(String(decoding: data, as: UTF8.self))
    }

    func remove() throws {
        try delete()
    }
}
