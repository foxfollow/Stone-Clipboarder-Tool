//
//  VaultKeyProvider.swift
//  StoneClipboarderTool
//
//  Where the Passwords vault key lives.
//

import CryptoKit
import Foundation
import Security

/// Stores one secret blob: the vault key (raw, or wrapped with the vault
/// password) or the fingerprint key. Calls may block (a Keychain access
/// prompt), so VaultManager makes them off the main thread.
protocol VaultKeyProvider: Sendable {
    /// nil when nothing is stored yet.
    func readKeyData() throws -> Data?
    /// Stores or replaces the blob.
    func writeKeyData(_ data: Data) throws
    /// Removes it ("Delete All Passwords").
    func deleteKey() throws
}

extension VaultKeyProvider {
    /// A raw 256-bit key, created and stored when none is there yet. Never
    /// replaces a key it failed to read: only a missing key is created.
    func loadOrCreateKey() throws -> SymmetricKey {
        if let data = try readKeyData() {
            return try VaultCrypto.key(from: data)
        }
        let key = VaultCrypto.makeKey()
        try writeKeyData(VaultCrypto.keyData(key))
        return key
    }
}

/// The key as a generic password in the user's login keychain.
///
/// Release builds are ad-hoc signed without entitlements, so the
/// data-protection keychain (and keys bound to Touch ID through
/// `SecAccessControl`) isn't available; the file-based login keychain is.
/// Its access list names this app's signature, so macOS asks once after an
/// update before handing the key to the new build. The Touch ID gate is
/// `VaultAuthenticator`, checked before this is called.
struct KeychainVaultKeyProvider: VaultKeyProvider {
    static let service = "d3f0ld.StoneClipboarderTool.vault"
    static let account = "vault-key"
    /// The HMAC key of `VaultFingerprint`.
    static let fingerprintAccount = "vault-fingerprint-key"

    enum Failure: Error, Equatable {
        case keychain(OSStatus)
    }

    let service: String
    let account: String

    init(service: String = KeychainVaultKeyProvider.service, account: String = KeychainVaultKeyProvider.account) {
        self.service = service
        self.account = account
    }

    func writeKeyData(_ data: Data) throws {
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            try store(data)
        default:
            throw Failure.keychain(status)
        }
    }

    func deleteKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.keychain(status) }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func readKeyData() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw Failure.keychain(status)
        }
    }

    private func store(_ data: Data) throws {
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        attributes[kSecAttrLabel as String] = "Stone Clipboarder Passwords"
        attributes[kSecAttrDescription as String] = account == Self.fingerprintAccount
            ? "Recognizes copies of saved passwords" : "Encryption key of the Passwords vault"
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychain(status) }
    }
}

/// A key that lives only in memory: unit tests and demo mode, which must
/// never touch the user's keychain.
final class InMemoryVaultKeyProvider: VaultKeyProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    /// Set by tests to make reads fail.
    var failure: Error?

    init(key: SymmetricKey? = nil) {
        data = key.map(VaultCrypto.keyData)
    }

    var hasKey: Bool {
        lock.withLock { data != nil }
    }

    /// What is stored (tests check raw vs wrapped).
    var storedData: Data? {
        lock.withLock { data }
    }

    func readKeyData() throws -> Data? {
        try lock.withLock {
            if let failure { throw failure }
            return data
        }
    }

    func writeKeyData(_ data: Data) throws {
        lock.withLock { self.data = data }
    }

    func deleteKey() throws {
        lock.withLock { data = nil }
    }
}
