//
//  ExternalOpener.swift
//  StoneClipboarderTool
//
//  Opens clipboard content in other apps — images in Preview, files in their
//  default app, text in TextEdit — through a short-lived temp file.
//

import AppKit

@MainActor
enum ExternalOpener {
    /// How long a temp copy is kept: enough for the other app to open it,
    /// short enough not to leave clipboard content lying around.
    static let tempFileLifetime: TimeInterval = 60

    nonisolated static var directory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("StoneClipboarderTool", isDirectory: true)
            .appendingPathComponent("Open", isDirectory: true)
    }

    /// Removes every temp copy. The timer in `writeTempFile` doesn't fire if
    /// the app quits or crashes first, so this runs at quit and at launch.
    /// `root` is only overridden by tests.
    static func removeAllTempFiles(root: URL = directory) {
        try? FileManager.default.removeItem(at: root)
    }

    /// Opens image data in the default image viewer (Preview), as PNG.
    @discardableResult
    static func openImage(_ data: Data, fileName: String = "Clipboard Image.png") -> Bool {
        guard let png = pngData(from: data) else {
            ErrorLogger.shared.log("Failed to convert image to PNG", category: "ExternalOpen")
            return false
        }
        guard let url = writeTempFile(png, fileName: fileName) else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    /// Opens a file under its original name in its default app.
    @discardableResult
    static func openFile(_ data: Data, fileName: String) -> Bool {
        guard let url = writeTempFile(data, fileName: fileName) else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    /// Opens text in TextEdit, or the default app for .txt without it.
    @discardableResult
    static func openTextInTextEdit(_ text: String, fileName: String = "Clipboard Text.txt") -> Bool {
        guard !text.isEmpty, let url = writeTempFile(Data(text.utf8), fileName: fileName) else {
            return false
        }
        if let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
        return true
    }

    /// PNG bytes for any image encoding NSImage understands.
    static func pngData(from data: Data) -> Data? {
        if let rep = NSBitmapImageRep(data: data) {
            return rep.representation(using: .png, properties: [:])
        }
        return NSImage(data: data)?.pngRepresentation
    }

    /// Each file gets its own folder, so the name the other app shows stays
    /// readable (the item's title, the original file name, "Clipboard
    /// Image.png") without
    /// collisions. The folder is removed after `tempFileLifetime`.
    private static func writeTempFile(_ data: Data, fileName: String) -> URL? {
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(PasteboardFileStore.safeFileName(fileName))
            try data.write(to: url)
            DispatchQueue.main.asyncAfter(deadline: .now() + tempFileLifetime) {
                try? FileManager.default.removeItem(at: folder)
            }
            return url
        } catch {
            ErrorLogger.shared.log("Failed to write a temp file to open", category: "ExternalOpen", error: error)
            return nil
        }
    }
}
