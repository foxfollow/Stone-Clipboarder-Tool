//
//  VaultFingerprint.swift
//  StoneClipboarderTool
//
//  Recognizes a copy of something already in the Passwords vault without
//  opening the vault.
//

import CryptoKit
import Foundation

/// HMAC-SHA256 of an entry's content under a separate fingerprint key.
///
/// The vault key is only in memory while the vault is unlocked, but a
/// password copied again must stay out of the history even while it is
/// locked. The fingerprints of all entries are kept in `VaultStore`'s
/// `fingerprints` file; a new capture is fingerprinted the same way and
/// checked against them. Without the key (Keychain) a fingerprint says
/// nothing about the content. Same content rules as
/// `VaultPayload.hasSameContent`: the title doesn't count.
enum VaultFingerprint {
    static func of(_ payload: VaultPayload, key: SymmetricKey) -> String {
        hmac(
            canonical(
                type: payload.itemType, content: payload.content, imageData: payload.imageData,
                fileData: payload.fileData, fileName: payload.fileName),
            key: key)
    }

    static func of(_ capture: ClipboardContent, key: SymmetricKey) -> String {
        let data: Data
        switch capture {
        case .text(let text):
            data = canonical(type: .text, content: text)
        case .image(let image):
            data = canonical(type: .image, imageData: image)
        case .file(let url, _, let file):
            data = canonical(type: .file, fileData: file, fileName: url.lastPathComponent)
        case .combined(let text, let image):
            data = canonical(type: .combined, content: text, imageData: image)
        }
        return hmac(data, key: key)
    }

    static func canonical(
        type: CBItemType, content: String? = nil, imageData: Data? = nil, fileData: Data? = nil,
        fileName: String? = nil
    ) -> Data {
        var data = Data(type.rawValue.utf8)
        func append(_ part: Data?) {
            // Length-prefixed, so ("ab", "c") and ("a", "bc") differ.
            let bytes = part ?? Data()
            var length = UInt64(bytes.count).bigEndian
            data.append(Data(bytes: &length, count: MemoryLayout<UInt64>.size))
            data.append(bytes)
        }
        switch type {
        case .text:
            append(content.map { Data($0.utf8) })
        case .image:
            append(imageData)
        case .file:
            append(fileName.map { Data($0.utf8) })
            append(fileData)
        case .combined:
            append(content.map { Data($0.utf8) })
            append(imageData)
        }
        return data
    }

    private static func hmac(_ data: Data, key: SymmetricKey) -> String {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: key)).base64EncodedString()
    }
}
