import CommonCrypto
import CryptoKit
import Foundation

/// Optional password encryption of a backup file (#188, DS6b). Pure functions on `Data`, no Keychain and no file access.
///
/// A password is turned into a 256-bit key with PBKDF2-HMAC-SHA256 and a random salt. The file holds one line of JSON with the
/// parameters (`format`, `version`, `salt`, `iterations`, `nonce`, `check`), a line break and the AES-256-GCM ciphertext followed
/// by its tag. The header line is authenticated as additional data, so a changed header makes the file fail to open. The password
/// itself is never stored or written anywhere; `check` is a short keyed digest that tells a wrong password from a damaged file.
public enum BackupCrypto {
    public static let format = "tagwerk-backup-encrypted"
    public static let version = 1
    public static let iterations = 600_000
    public static let minimumPasswordLength = 8
    /// A file asks for at most this many iterations; a higher number would let a manipulated file keep the phone busy.
    public static let maximumIterations = 5_000_000
    public static let saltLength = 16
    public static let keyLength = 32

    public struct KeyMaterial: Sendable, Equatable {
        public let key: Data
        public let salt: Data
        public let iterations: Int

        public init(key: Data, salt: Data, iterations: Int) {
            self.key = key
            self.salt = salt
            self.iterations = iterations
        }
    }

    public enum CryptoError: Error, Equatable {
        case wrongPassword
        case damaged
        case unsupportedVersion(Int)
        case passwordTooShort
    }

    /// What the first line of an encrypted file says; all of it is public.
    struct Header: Codable, Equatable {
        var format: String
        var version: Int
        var salt: Data
        var iterations: Int
        var nonce: Data
        var check: Data
    }

    // MARK: Key

    /// Derives a 256-bit key from the password with a fresh random salt. Throws `.passwordTooShort` below the minimum length.
    public static func deriveKey(password: String) throws -> KeyMaterial {
        guard password.count >= minimumPasswordLength else { throw CryptoError.passwordTooShort }
        let salt = randomBytes(saltLength)
        return KeyMaterial(key: deriveKey(password: password, salt: salt, iterations: iterations), salt: salt, iterations: iterations)
    }

    /// The key a password gives for a known salt and iteration count (to open a file). The password is normalised, so the same
    /// letters typed on another keyboard give the same key.
    public static func deriveKey(password: String, salt: Data, iterations: Int) -> Data {
        let passwordBytes = Array(password.precomposedStringWithCanonicalMapping.utf8)
        var derived = [UInt8](repeating: 0, count: keyLength)
        let status = salt.withUnsafeBytes { saltBuffer in
            passwordBytes.withUnsafeBufferPointer { passwordBuffer in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordBuffer.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) },
                                     passwordBytes.count, saltBuffer.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(max(1, iterations)), &derived, derived.count)
            }
        }
        precondition(status == kCCSuccess, "PBKDF2 failed")
        return Data(derived)
    }

    // MARK: Encrypting and decrypting

    /// AES-256-GCM with a random nonce: the encrypted file.
    public static func encrypt(_ plain: Data, with material: KeyMaterial) throws -> Data {
        let nonce = AES.GCM.Nonce()
        let header = Header(format: format, version: version, salt: material.salt, iterations: material.iterations,
                            nonce: Data(nonce), check: keyCheck(material.key))
        let headerLine = try encodeHeader(header)
        let sealed = try AES.GCM.seal(plain, using: SymmetricKey(data: material.key), nonce: nonce, authenticating: headerLine)
        return headerLine + Data([0x0A]) + sealed.ciphertext + sealed.tag
    }

    /// Salt and iteration count of an encrypted file, to derive the key from a typed password. `nil` for a file that is not encrypted
    /// or whose header is out of range.
    public static func header(of file: Data) -> (salt: Data, iterations: Int)? {
        guard let parts = split(file), let header = parts.header,
              header.salt.count == saltLength, (1...maximumIterations).contains(header.iterations) else { return nil }
        return (header.salt, header.iterations)
    }

    public static func isEncrypted(_ file: Data) -> Bool {
        split(file)?.header?.format == format
    }

    /// Opens a file with the key. Throws `.wrongPassword` for a key that is not the one of the file, `.damaged` when the file was
    /// changed, `.unsupportedVersion` for a newer envelope.
    public static func decrypt(_ file: Data, key: Data) throws -> Data {
        guard let parts = split(file), let header = parts.header, header.format == format else { throw CryptoError.damaged }
        guard header.version == version else { throw CryptoError.unsupportedVersion(header.version) }
        guard key.count == keyLength else { throw CryptoError.wrongPassword }
        guard constantTimeEqual(header.check, keyCheck(key)) else { throw CryptoError.wrongPassword }
        guard parts.body.count >= 16, let nonce = try? AES.GCM.Nonce(data: header.nonce) else { throw CryptoError.damaged }
        let ciphertext = parts.body.dropLast(16), tag = parts.body.suffix(16)
        do {
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            return try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: parts.headerLine)
        } catch {
            throw CryptoError.damaged
        }
    }

    // MARK: Layout

    private struct Parts {
        let headerLine: Data
        let header: Header?
        let body: Data
    }

    /// The header line (up to the first line break) and what follows it. `nil` without a line break.
    private static func split(_ file: Data) -> Parts? {
        guard file.first == UInt8(ascii: "{"), let newline = file.firstIndex(of: 0x0A) else { return nil }
        let line = file[file.startIndex..<newline]
        // The header is short; a long first line is another kind of file.
        guard line.count < 1024 else { return nil }
        return Parts(headerLine: Data(line), header: try? JSONDecoder().decode(Header.self, from: line),
                     body: Data(file[file.index(after: newline)...]))
    }

    private static func encodeHeader(_ header: Header) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(header)
    }

    /// A short keyed digest of the key; a wrong password changes it, so it is told apart from a damaged file.
    private static func keyCheck(_ key: Data) -> Data {
        let digest = HMAC<SHA256>.authenticationCode(for: Data("tagwerk-backup-key-check".utf8), using: SymmetricKey(data: key))
        return Data(digest.prefix(16))
    }

    private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private static func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}
