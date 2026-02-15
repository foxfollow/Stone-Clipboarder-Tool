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

    /// Prepare a CBItem for Quick Look by writing its data to a temporary file.
    func prepareItem(_ item: CBItem) -> Bool {
        // Clean up previous temp files
        cleanupTempFiles()

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoneClipboarderQL_\(UUID().uuidString)")

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            tempDirectory = tempDir
        } catch {
            return false
        }

        switch item.itemType {
        case .text:
            guard let content = item.content else { return false }
            let fileURL = tempDir.appendingPathComponent("Clipboard Text.txt")
            do {
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                previewURL = fileURL
                return true
            } catch {
                return false
            }

        case .image:
            guard let imageData = item.imageData else { return false }
            let fileURL = tempDir.appendingPathComponent("Clipboard Image.png")
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
            let fileName = item.fileName ?? "Clipboard File"
            let fileURL = tempDir.appendingPathComponent(fileName)
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
                let fileURL = tempDir.appendingPathComponent("Clipboard Image.png")
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
                let fileURL = tempDir.appendingPathComponent("Clipboard Text.txt")
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
    func hidePreview() {
        if QLPreviewPanel.sharedPreviewPanelExists() {
            let panel = QLPreviewPanel.shared()!
            if panel.isVisible {
                panel.orderOut(nil)
            }
        }
        cleanupTempFiles()
    }

    /// Whether the preview panel is currently visible.
    var isPreviewVisible: Bool {
        guard QLPreviewPanel.sharedPreviewPanelExists() else { return false }
        return QLPreviewPanel.shared()!.isVisible
    }

    // MARK: - QLPreviewPanelDataSource

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return MainActor.assumeIsolated {
            previewURL != nil ? 1 : 0
        }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
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
    }

    deinit {
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }
}
