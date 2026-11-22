import Foundation
import Testing
@testable import TagwerkCore

struct BackupCryptoTests {
    /// A key with few iterations, so most tests do not wait for the real cost of a derivation.
    private func material(_ password: String = "correct horse", iterations: Int = 1_000) -> BackupCrypto.KeyMaterial {
        let salt = Data((0..<16).map { UInt8($0 * 7 + 3) })
        return BackupCrypto.KeyMaterial(key: BackupCrypto.deriveKey(password: password, salt: salt, iterations: iterations),
                                        salt: salt, iterations: iterations)
    }

    private let plain = Data("{\n  \"format\": \"tagwerk-backup\"\n}".utf8)

    @Test func roundTrip_encryptDecrypt() throws {
        let key = material()
        let file = try BackupCrypto.encrypt(plain, with: key)
        #expect(BackupCrypto.isEncrypted(file))
        #expect(file.range(of: plain) == nil)
        #expect(try BackupCrypto.decrypt(file, key: key.key) == plain)
        #expect(try BackupCrypto.decrypt(try BackupCrypto.encrypt(Data(), with: key), key: key.key).isEmpty)
    }

    @Test func roundTrip_withTheKeyDerivedFromTheTypedPassword() throws {
        let key = material("ein längeres Passwort")
        let file = try BackupCrypto.encrypt(plain, with: key)
        let header = try #require(BackupCrypto.header(of: file))
        let typed = BackupCrypto.deriveKey(password: "ein längeres Passwort", salt: header.salt, iterations: header.iterations)
        #expect(try BackupCrypto.decrypt(file, key: typed) == plain)
        // The same letters composed differently (typed on another keyboard) give the same key.
        let decomposed = "ein la\u{0308}ngeres Passwort"
        #expect(BackupCrypto.deriveKey(password: decomposed, salt: header.salt, iterations: header.iterations) == typed)
    }

    @Test func decrypt_wrongKey_throwsWrongPassword() throws {
        let file = try BackupCrypto.encrypt(plain, with: material())
        let other = material("another password")
        #expect(throws: BackupCrypto.CryptoError.wrongPassword) { try BackupCrypto.decrypt(file, key: other.key) }
        #expect(throws: BackupCrypto.CryptoError.wrongPassword) { try BackupCrypto.decrypt(file, key: Data()) }
    }

    @Test func decrypt_tamperedCiphertext_throws() throws {
        let key = material()
        var file = try BackupCrypto.encrypt(plain, with: key)
        file[file.count - 20] ^= 0x01
        #expect(throws: BackupCrypto.CryptoError.damaged) { try BackupCrypto.decrypt(file, key: key.key) }
        let truncated = try BackupCrypto.encrypt(plain, with: key).prefix(60)
        #expect(throws: BackupCrypto.CryptoError.damaged) { try BackupCrypto.decrypt(Data(truncated), key: key.key) }
    }

    @Test func decrypt_tamperedHeader_throws() throws {
        let key = material()
        let file = try BackupCrypto.encrypt(plain, with: key)
        // Same length, other iteration count: the header is part of what the tag covers.
        let text = String(decoding: file, as: UTF8.self)
        let changed = Data(text.replacingOccurrences(of: "\"iterations\":1000", with: "\"iterations\":1001").utf8)
        #expect(changed != file)
        #expect(throws: BackupCrypto.CryptoError.damaged) { try BackupCrypto.decrypt(changed, key: key.key) }
    }

    @Test func encrypt_twice_differs() throws {
        let key = material()
        #expect(try BackupCrypto.encrypt(plain, with: key) != BackupCrypto.encrypt(plain, with: key))
    }

    @Test func deriveKey_sameSalt_sameKey() {
        let salt = Data(repeating: 9, count: 16)
        let first = BackupCrypto.deriveKey(password: "same password", salt: salt, iterations: 1_000)
        #expect(first == BackupCrypto.deriveKey(password: "same password", salt: salt, iterations: 1_000))
        #expect(first != BackupCrypto.deriveKey(password: "same password", salt: Data(repeating: 8, count: 16), iterations: 1_000))
        #expect(first != BackupCrypto.deriveKey(password: "other password", salt: salt, iterations: 1_000))
        #expect(first.count == 32)
    }

    @Test func deriveKey_matchesTheKnownPBKDF2Vector() {
        // RFC 7914, section 11: PBKDF2-HMAC-SHA-256, P = "passwd", S = "salt", c = 1, dkLen = 64; the first 32 bytes.
        let key = BackupCrypto.deriveKey(password: "passwd", salt: Data("salt".utf8), iterations: 1)
        let expected = "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc"
        #expect(key.map { String(format: "%02x", $0) }.joined() == expected)
    }

    @Test func deriveKey_shortPassword_throws() {
        #expect(throws: BackupCrypto.CryptoError.passwordTooShort) { try BackupCrypto.deriveKey(password: "1234567") }
        #expect(throws: BackupCrypto.CryptoError.passwordTooShort) { try BackupCrypto.deriveKey(password: "") }
    }

    @Test func deriveKey_withAPassword_usesTheDocumentedCostAndAFreshSalt() throws {
        let first = try BackupCrypto.deriveKey(password: "12345678")
        let second = try BackupCrypto.deriveKey(password: "12345678")
        #expect(first.iterations == BackupCrypto.iterations && first.salt.count == 16 && first.key.count == 32)
        #expect(first.salt != second.salt && first.key != second.key)
    }

    @Test func header_ofPlainJSON_isNil() {
        let json = Data("{\n  \"format\" : \"tagwerk-backup\",\n  \"schemaVersion\" : 2\n}".utf8)
        #expect(BackupCrypto.header(of: json) == nil)
        #expect(!BackupCrypto.isEncrypted(json))
        #expect(!BackupCrypto.isEncrypted(Data()))
        #expect(!BackupCrypto.isEncrypted(Data("not json at all".utf8)))
        #expect(!BackupCrypto.isEncrypted(Data("{\"format\":\"tagwerk-backup\"}\nrest".utf8)))
    }

    @Test func header_ofAnEncryptedFile_namesSaltAndIterations() throws {
        let key = material()
        let header = try #require(BackupCrypto.header(of: try BackupCrypto.encrypt(plain, with: key)))
        #expect(header.salt == key.salt && header.iterations == key.iterations)
    }

    @Test func header_withAnAbsurdIterationCount_isRefused() throws {
        let file = try BackupCrypto.encrypt(plain, with: material())
        let text = String(decoding: file, as: UTF8.self).replacingOccurrences(of: "\"iterations\":1000", with: "\"iterations\":9999999999")
        #expect(BackupCrypto.header(of: Data(text.utf8)) == nil)
    }

    @Test func unsupportedVersion_throws() throws {
        let key = material()
        let file = try BackupCrypto.encrypt(plain, with: key)
        let text = String(decoding: file, as: UTF8.self).replacingOccurrences(of: "\"version\":1", with: "\"version\":7")
        #expect(throws: BackupCrypto.CryptoError.unsupportedVersion(7)) { try BackupCrypto.decrypt(Data(text.utf8), key: key.key) }
    }
}
