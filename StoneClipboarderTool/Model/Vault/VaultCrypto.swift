//
//  VaultCrypto.swift
//  StoneClipboarderTool
//
//  Seals and opens vault entry files.
//

import CryptoKit
import Foundation

/// File format of one vault entry:
///
///     "SCTV" | version (1 byte) | AES.GCM.SealedBox.combined
///
/// The sealed box holds the JSON of a `VaultPayload`. The header and the
/// entry's id are authenticated data, so a file can't be renamed into another
/// entry's place or downgraded without failing to open.
enum VaultCrypto {
    static let magic = Data("SCTV".utf8)
    static let version: UInt8 = 1
    static let keyByteCount = 32

    enum Failure: Error, Equatable {
        case notAVaultFile
        case unsupportedVersion(UInt8)
        /// Wrong key, tampered bytes, or a file that belongs to another id.
        case cannotOpen
        case invalidKey
    }

    /// A fresh random 256-bit key.
    static func makeKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    static func key(from data: Data) throws -> SymmetricKey {
        guard data.count == keyByteCount else { throw Failure.invalidKey }
        return SymmetricKey(data: data)
    }

    static func keyData(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    static func seal(_ payload: VaultPayload, with key: SymmetricKey) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let plaintext = try encoder.encode(payload)
        let header = header()
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: header + associatedData(for: payload.id))
        guard let combined = box.combined else { throw Failure.cannotOpen }
        return header + combined
    }

    /// Opens a file written by `seal`. `id` is the entry the file is stored
    /// as; a file sealed for another id doesn't open.
    static func open(_ data: Data, id: UUID, with key: SymmetricKey) throws -> VaultPayload {
        let headerLength = magic.count + 1
        guard data.count > headerLength, data.prefix(magic.count) == magic else { throw Failure.notAVaultFile }
        let fileVersion = data[data.startIndex + magic.count]
        guard fileVersion == version else { throw Failure.unsupportedVersion(fileVersion) }

        let header = data.prefix(headerLength)
        let plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(combined: data.dropFirst(headerLength))
            plaintext = try AES.GCM.open(box, using: key, authenticating: header + associatedData(for: id))
        } catch {
            throw Failure.cannotOpen
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let payload = try decoder.decode(VaultPayload.self, from: plaintext)
        guard payload.id == id else { throw Failure.cannotOpen }
        return payload
    }

    private static func header() -> Data {
        magic + Data([version])
    }

    private static func associatedData(for id: UUID) -> Data {
        Data(id.uuidString.utf8)
    }
}
