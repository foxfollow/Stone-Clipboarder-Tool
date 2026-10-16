//
//  PasteboardFileStore.swift
//  StoneClipboarderTool
//
//  Temp files behind file items put back on the pasteboard.
//
//  A file on the pasteboard is only a URL; the receiving app reads the file
//  when the user pastes, possibly minutes later. The old code deleted the
//  temp file after 5 s, so a later paste pointed at nothing. Now the latest
//  file stays until the next file copy replaces it. Each copy gets its own
//  folder, so the original file name is kept without collisions.
//

import Foundation

enum PasteboardFileStore {
    static var directory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("StoneClipboarderTool", isDirectory: true)
            .appendingPathComponent("Pasteboard", isDirectory: true)
    }

    /// Writes `data` as `fileName` into a fresh folder and returns the URL to
    /// put on the pasteboard. The files of earlier copies are removed only
    /// after the write succeeds: if it fails, the pasteboard still points at
    /// the previous file and that file must stay. `root` is only overridden
    /// by tests.
    static func write(_ data: Data, fileName: String, root: URL = directory) throws -> URL {
        let fileManager = FileManager.default
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(safeFileName(fileName))
            try data.write(to: url)
            let earlier = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for item in earlier where item.lastPathComponent != folder.lastPathComponent {
                try? fileManager.removeItem(at: item)
            }
            return url
        } catch {
            try? fileManager.removeItem(at: folder)
            throw error
        }
    }

    static func removeAll(root: URL = directory) {
        try? FileManager.default.removeItem(at: root)
    }

    /// Keeps only the last path component so a stored name can't point
    /// outside the folder.
    static func safeFileName(_ name: String) -> String {
        let last = (name as NSString).lastPathComponent
        return ["", ".", "..", "/"].contains(last) ? "Clipboard File" : last
    }
}
