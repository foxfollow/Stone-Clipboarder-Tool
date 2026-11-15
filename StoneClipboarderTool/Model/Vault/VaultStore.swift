//
//  VaultStore.swift
//  StoneClipboarderTool
//
//  The Passwords vault on disk: one sealed file per entry.
//

import CryptoKit
import Foundation

/// Reads and writes `<root>/<uuid>.sctv` files (see `VaultCrypto`).
///
/// Deliberately not SwiftData: `ModelContainerFactory` deletes a store it
/// can't open, and a SwiftData store keeps its columns in plaintext. Here a
/// damaged file costs one entry, and every byte of content is sealed.
struct VaultStore {
    static let fileExtension = "sctv"

    /// `Application Support/StoneClipboarderTool/Vault` (inside the app's
    /// container when sandboxed).
    static var defaultRoot: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("StoneClipboarderTool", isDirectory: true)
            .appendingPathComponent("Vault", isDirectory: true)
    }

    struct LoadResult {
        /// Sorted for display.
        var entries: [VaultPayload]
        /// Files that didn't open (wrong key, damaged, foreign). Left on disk.
        var unreadableCount: Int
    }

    let root: URL

    init(root: URL = VaultStore.defaultRoot) {
        self.root = root
    }

    /// Whether any entry file exists, without opening them.
    var hasEntries: Bool {
        !entryFiles().isEmpty
    }

    func fileURL(for id: UUID) -> URL {
        root.appendingPathComponent("\(id.uuidString).\(Self.fileExtension)")
    }

    func loadAll(with key: SymmetricKey) -> LoadResult {
        var entries: [VaultPayload] = []
        var unreadable = 0
        for (id, url) in entryFiles() {
            do {
                let data = try Data(contentsOf: url)
                entries.append(try VaultCrypto.open(data, id: id, with: key))
            } catch {
                unreadable += 1
            }
        }
        return LoadResult(entries: VaultPayload.sorted(entries), unreadableCount: unreadable)
    }

    /// Writes (or replaces) the entry's file atomically. The folder is
    /// owner-only; so is the file.
    func save(_ payload: VaultPayload, with key: SymmetricKey) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let sealed = try VaultCrypto.seal(payload, with: key)
        let url = fileURL(for: payload.id)
        try sealed.write(to: url, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func delete(id: UUID) throws {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Fingerprints

    /// `VaultFingerprint`s of every entry, one per line; readable while the
    /// vault is locked.
    var fingerprintsURL: URL {
        root.appendingPathComponent("fingerprints")
    }

    func loadFingerprints() -> Set<String> {
        guard let text = try? String(contentsOf: fingerprintsURL, encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").map(String.init).filter { !$0.isEmpty })
    }

    func saveFingerprints(_ fingerprints: Set<String>) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data(fingerprints.sorted().joined(separator: "\n").utf8).write(to: fingerprintsURL, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fingerprintsURL.path)
    }

    /// Removes every entry file (and the folder).
    func deleteAll() throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        try FileManager.default.removeItem(at: root)
    }

    /// Entry files whose name is a UUID; anything else in the folder is ignored.
    private func entryFiles() -> [(UUID, URL)] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap { url in
            guard url.pathExtension == Self.fileExtension,
                  let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent)
            else { return nil }
            return (id, url)
        }
    }
}
