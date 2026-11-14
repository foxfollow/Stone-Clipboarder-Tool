//
//  QPPreviewPanel.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 14.02.2026.
//

import AppKit
import QuickLookUI

/// Manages native macOS QLPreviewPanel for QuickPicker spacebar preview.
/// Writes CBItem data to temporary files so Quick Look can display them.
@MainActor
class QPQuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {

    private var previewURL: URL?
    private var tempDirectory: URL?
    /// The folder of a decrypted Passwords entry; removed as soon as its
    /// preview closes (see `removeSecretFiles`).
    private var secretDirectory: URL?
    private static let secretPrefix = "Secret_"

    // Stable directory under Application Support so external apps (Preview.app) can always find the file.
    private static var previewsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("StoneClipboarderTool")
            .appendingPathComponent("Previews")
    }

    /// Prepare a CBItem for Quick Look by writing its data to a stable file.
    func prepareItem(_ item: CBItem) -> Bool {
        // Clean up previous session files before creating a new one
        cleanupTempFiles()

        let tempDir = QPQuickLookCoordinator.previewsDirectory
            .appendingPathComponent("Session_\(UUID().uuidString)")

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            tempDirectory = tempDir
        } catch {
            return false
        }

        switch item.itemType {
        case .text:
            guard let content = item.content else { return false }
            let fileURL = tempDir.appendingPathComponent(item.textExportFileName)
            do {
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                previewURL = fileURL
                return true
            } catch {
                return false
            }

        case .image:
            guard let imageData = item.imageData else { return false }
            let fileURL = tempDir.appendingPathComponent(item.imageExportFileName)
            do {
                // Convert to PNG for best Quick Look compatibility
                if let image = NSImage(data: imageData),
                   let pngData = image.pngRepresentation {
                    try pngData.write(to: fileURL)
                } else {
                    try imageData.write(to: fileURL)
                }
                previewURL = fileURL
                return true
            } catch {
                return false
            }

        case .file:
            guard let fileData = item.fileData else { return false }
            let fileName = item.fileExportFileName
            let fileURL = tempDir.appendingPathComponent(PasteboardFileStore.safeFileName(fileName))
            do {
                try fileData.write(to: fileURL)
                previewURL = fileURL
                return true
            } catch {
                return false
            }

        case .combined:
            // For combined items, prioritize image preview
            if let imageData = item.imageData {
                let fileURL = tempDir.appendingPathComponent(item.imageExportFileName)
                do {
                    if let image = NSImage(data: imageData),
                       let pngData = image.pngRepresentation {
                        try pngData.write(to: fileURL)
                    } else {
                        try imageData.write(to: fileURL)
                    }
                    previewURL = fileURL
                    return true
                } catch {
                    return false
                }
            } else if let content = item.content {
                let fileURL = tempDir.appendingPathComponent(item.textExportFileName)
                do {
                    try content.write(to: fileURL, atomically: true, encoding: .utf8)
                    previewURL = fileURL
                    return true
                } catch {
                    return false
                }
            }
            return false
        }
    }

    /// Writes a decrypted Passwords entry for Quick Look, which only reads
    /// files. The copy lives in an owner-only `Secret_<uuid>` folder that is
    /// removed when the preview closes, the vault locks, the picker closes,
    /// the next entry is shown, and at launch and quit — unlike history
    /// previews, which stay 10 minutes for "Open with…".
    func prepareSecret(_ content: QPPreviewContent) -> Bool {
        removeSecretFiles()
        cleanupTempFiles()
        let fileManager = FileManager.default
        let folder = Self.previewsDirectory.appendingPathComponent(Self.secretPrefix + UUID().uuidString)
        do {
            try fileManager.createDirectory(
                at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            return false
        }
        secretDirectory = folder

        guard let (data, name) = Self.secretFile(for: content) else {
            removeSecretFiles()
            return false
        }
        let url = folder.appendingPathComponent(PasteboardFileStore.safeFileName(name))
        guard fileManager.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            removeSecretFiles()
            return false
        }
        previewURL = url
        return true
    }

    /// What Quick Look gets for an entry: the image (PNG) of an image or
    /// text + image, the file as is, otherwise the text.
    static func secretFile(for content: QPPreviewContent) -> (Data, String)? {
        let base = content.title.map { PasteboardFileStore.safeFileName($0) }
        switch content.itemType {
        case .file:
            guard let data = content.fileData else { return nil }
            return (data, content.fileName ?? "File")
        case .image, .combined:
            if let imageData = content.imageData {
                let png = NSImage(data: imageData)?.pngRepresentation ?? imageData
                return (png, (base ?? "Image") + ".png")
            }
            fallthrough
        case .text:
            guard let text = content.content else { return nil }
            return (Data(text.utf8), (base ?? "Password") + ".txt")
        }
    }

    /// Deletes the decrypted copy of a Passwords entry, if any.
    func removeSecretFiles() {
        guard let folder = secretDirectory else { return }
        try? FileManager.default.removeItem(at: folder)
        secretDirectory = nil
        if previewURL?.path.hasPrefix(folder.path) == true {
            previewURL = nil
        }
    }

    /// Fills the screen with the open Quick Look panel, or back.
    func toggleFullScreen() {
        guard isPreviewVisible, let panel = QLPreviewPanel.shared() else { return }
        if panel.isInFullScreenMode {
            panel.exitFullScreenMode(options: nil)
        } else {
            panel.enterFullScreenMode(nil, withOptions: nil)
        }
    }

    /// Show or update the QLPreviewPanel.
    func showPreview() {
        guard previewURL != nil else { return }

        let panel = QLPreviewPanel.shared()!
        panel.dataSource = self
        panel.delegate = self

        if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
            // Already visible — just reload with new data
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }

        panel.reloadData()
    }

    /// Hide the QLPreviewPanel if visible.
    /// Does NOT delete the session file — Preview.app or other external apps may still have it open.
    /// The file is cleaned up when the next preview is prepared, or on app launch.
    func hidePreview() {
        if QLPreviewPanel.sharedPreviewPanelExists(),
           let panel = QLPreviewPanel.shared(),
           panel.isVisible {
            panel.orderOut(nil)
        }
        tempDirectory = nil
        previewURL = nil
    }

    /// Whether the preview panel is currently visible.
    var isPreviewVisible: Bool {
        guard QLPreviewPanel.sharedPreviewPanelExists() else { return false }
        return QLPreviewPanel.shared()!.isVisible
    }

    // MARK: - QLPreviewPanelDataSource

    nonisolated func numberOfPreviewItems(in _: QLPreviewPanel!) -> Int {
        return MainActor.assumeIsolated {
            previewURL != nil ? 1 : 0
        }
    }

    nonisolated func previewPanel(_: QLPreviewPanel!, previewItemAt _: Int) -> (any QLPreviewItem)! {
        return MainActor.assumeIsolated {
            previewURL as? QLPreviewItem
        }
    }

    // MARK: - Cleanup

    func cleanupTempFiles() {
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
            tempDirectory = nil
        }
        previewURL = nil
        QPQuickLookCoordinator.cleanupOldPreviewSessions()
    }

    /// How long a preview copy may outlive its preview. Long enough for
    /// "Open with…" from the Quick Look panel to hand the file to another app;
    /// short, because these are plain copies of clipboard items (text as .txt).
    static let previewSessionLifetime: TimeInterval = 10 * 60

    /// Removes session directories older than `previewSessionLifetime`.
    static func cleanupOldPreviewSessions() {
        let dir = previewsDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles
        ) else { return }
        let cutoff = Date().addingTimeInterval(-previewSessionLifetime)
        for url in contents {
            // A decrypted Passwords copy left by a crash goes at once.
            if url.lastPathComponent.hasPrefix(secretPrefix) {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if created < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Removes every preview copy. Called when the app quits.
    static func removeAllPreviewSessions() {
        try? FileManager.default.removeItem(at: previewsDirectory)
    }

    deinit {
        // Session files are intentionally kept alive so external apps (Preview.app) can still access them.
        // Cleanup happens in cleanupTempFiles() before the next preview, or via cleanupOldPreviewSessions().
    }
}
