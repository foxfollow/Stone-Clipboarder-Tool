//
//  VaultKeyProvider.swift
//  StoneClipboarderTool
//
//  Where the Passwords vault key lives.
//

import CryptoKit
import Foundation
import Security

/// Hands out the vault's 256-bit key. Calls may block (a Keychain access
/// prompt), so VaultManager makes them off the main thread.
protocol VaultKeyProvider: Sendable {
    /// The stored key, or a new one that is stored first. Never replaces a
    /// key it failed to read: only a missing key is created.
    func loadOrCreateKey() throws -> SymmetricKey
    /// Removes the key ("Delete All Passwords").
    func deleteKey() throws
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

    enum Failure: Error, Equatable {
        case keychain(OSStatus)
    }

    let service: String
    let account: String

    init(service: String = KeychainVaultKeyProvider.service, account: String = KeychainVaultKeyProvider.account) {
        self.service = service
        self.account = account
    }

    func loadOrCreateKey() throws -> SymmetricKey {
        if let data = try readKeyData() {
            return try VaultCrypto.key(from: data)
        }
        let key = VaultCrypto.makeKey()
        try store(VaultCrypto.keyData(key))
        return key
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

    private func readKeyData() throws -> Data? {
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
        attributes[kSecAttrDescription as String] = "Encryption key of the Passwords vault"
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychain(status) }
    }
}

/// A key that lives only in memory: unit tests and demo mode, which must
/// never touch the user's keychain.
final class InMemoryVaultKeyProvider: VaultKeyProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var key: SymmetricKey?
    /// Set by tests to make the next load fail.
    var failure: Error?

    init(key: SymmetricKey? = nil) {
        self.key = key
    }

    var hasKey: Bool {
        lock.withLock { key != nil }
    }

    func loadOrCreateKey() throws -> SymmetricKey {
        try lock.withLock {
            if let failure { throw failure }
            if let key { return key }
            let created = VaultCrypto.makeKey()
            key = created
            return created
        }
    }

    func deleteKey() throws {
        lock.withLock { key = nil }
    }
}
