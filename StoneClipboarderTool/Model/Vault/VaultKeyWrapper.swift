//
//  VaultKeyWrapper.swift
//  StoneClipboarderTool
//
//  The vault key sealed with the user's Passwords password.
//

import CommonCrypto
import CryptoKit
import Foundation

/// With "Require a password" on, the Keychain holds the vault key only in
/// this wrapped form:
///
///     "SCTW" | version (1 byte) | PBKDF2 rounds (UInt32, big endian) |
///     salt (16 bytes) | AES.GCM.SealedBox.combined of the 32-byte key
///
/// The wrapping key is PBKDF2-HMAC-SHA256 of the password; the header is
/// authenticated data. Nothing else can open it: a forgotten password
/// means the vault is lost, which Settings says before it is set.
enum VaultKeyWrapper {
    static let magic = Data("SCTW".utf8)
    static let version: UInt8 = 1
    /// OWASP's 2023 figure for PBKDF2-HMAC-SHA256; about a third of a
    /// second on Apple silicon, run off the main thread.
    static let defaultRounds: UInt32 = 600_000
    static let saltLength = 16

    enum Failure: Error, Equatable {
        case notWrapped
        case unsupportedVersion(UInt8)
        case wrongPassword
        case derivationFailed
        case emptyPassword
    }

    private static var headerLength: Int { magic.count + 1 + 4 + saltLength }

    static func isWrapped(_ data: Data) -> Bool {
        data.count > headerLength && data.prefix(magic.count) == magic
    }

    static func wrap(
        _ key: SymmetricKey, password: String, rounds: UInt32 = defaultRounds, salt: Data? = nil
    ) throws -> Data {
        guard !password.isEmpty else { throw Failure.emptyPassword }
        let salt = salt ?? randomSalt()
        var header = magic + Data([version])
        var bigEndianRounds = rounds.bigEndian
        header.append(Data(bytes: &bigEndianRounds, count: 4))
        header.append(salt)

        let wrappingKey = try deriveKey(password: password, salt: salt, rounds: rounds)
        let box = try AES.GCM.seal(VaultCrypto.keyData(key), using: wrappingKey, authenticating: header)
        guard let combined = box.combined else { throw Failure.derivationFailed }
        return header + combined
    }

    static func unwrap(_ data: Data, password: String) throws -> SymmetricKey {
        guard isWrapped(data) else { throw Failure.notWrapped }
        let bytes = [UInt8](data)
        let fileVersion = bytes[magic.count]
        guard fileVersion == version else { throw Failure.unsupportedVersion(fileVersion) }
        let roundsStart = magic.count + 1
        let rounds = bytes[roundsStart..<roundsStart + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        let salt = Data(bytes[(roundsStart + 4)..<headerLength])
        let header = Data(bytes[0..<headerLength])

        let wrappingKey = try deriveKey(password: password, salt: salt, rounds: rounds)
        do {
            let box = try AES.GCM.SealedBox(combined: Data(bytes[headerLength...]))
            let keyData = try AES.GCM.open(box, using: wrappingKey, authenticating: header)
            return try VaultCrypto.key(from: keyData)
        } catch {
            throw Failure.wrongPassword
        }
    }

    /// PBKDF2-HMAC-SHA256 of the password in Unicode normal form C, so the
    /// same password typed on another keyboard layout derives the same key.
    static func deriveKey(password: String, salt: Data, rounds: UInt32) throws -> SymmetricKey {
        let passwordBytes = Array(password.precomposedStringWithCanonicalMapping.utf8)
        let saltBytes = [UInt8](salt)
        var derived = [UInt8](repeating: 0, count: VaultCrypto.keyByteCount)
        let status = passwordBytes.withUnsafeBufferPointer { passwordBuffer in
            passwordBuffer.withMemoryRebound(to: Int8.self) { passwordChars in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2), passwordChars.baseAddress, passwordBytes.count,
                    saltBytes, saltBytes.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                    &derived, derived.count)
            }
        }
        guard status == kCCSuccess else { throw Failure.derivationFailed }
        return SymmetricKey(data: derived)
    }

    private static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: saltLength)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }
}
