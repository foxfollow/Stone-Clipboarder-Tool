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

    /// Writes `data` as `fileName` into a fresh folder, removing the files of
    /// earlier copies, and returns the URL to put on the pasteboard.
    /// `root` is only overridden by tests.
    static func write(_ data: Data, fileName: String, root: URL = directory) throws -> URL {
        removeAll(root: root)
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(safeFileName(fileName))
        try data.write(to: url)
        return url
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
