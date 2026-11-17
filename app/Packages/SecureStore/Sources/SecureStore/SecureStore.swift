import Foundation
import Security

/// Errors from the keychain, carrying the raw `OSStatus`.
public enum SecureStoreError: Error, Equatable, Sendable {
    case unexpectedStatus(Int32)
}

/// Generic-password keychain storage for secrets such as tokens.
/// Items are readable after the first unlock and never leave this device.
public struct SecureStore: Sendable {
    private let service: String

    public init(service: String = "com.melvinmng.tagwerk") {
        self.service = service
    }

    /// Stores `value` for `account`: updates an existing item, otherwise adds a new one.
    public func set(_ value: String, for account: String) throws {
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery(account) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var attributes = baseQuery(account)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw SecureStoreError.unexpectedStatus(addStatus) }
        default:
            throw SecureStoreError.unexpectedStatus(updateStatus)
        }
    }

    /// Returns the stored value, or `nil` when no item exists.
    public func string(for account: String) throws -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw SecureStoreError.unexpectedStatus(status)
        }
    }

    /// Deletes the item; a missing item is not an error.
    public func remove(_ account: String) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
