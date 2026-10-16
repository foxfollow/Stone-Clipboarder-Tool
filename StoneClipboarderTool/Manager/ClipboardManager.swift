//
//  ClipboardManager.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import AppKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

@MainActor
final class ClipboardManager: ObservableObject {
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let pasteboard = NSPasteboard.general

    var onClipboardChange: ((ClipboardContent) -> Void)?
    weak var settingsManager: SettingsManager?
    var modelContext: ModelContext?
    /// Separate context for ExcludedApp queries — lives in the settings container
    private var settingsModelContext: ModelContext?

    // Pause timer properties
    @Published var isPaused: Bool = false
    @Published var pauseEndDate: Date?
    private var pauseTimer: Timer?

    init() {
        lastChangeCount = pasteboard.changeCount
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func setSettingsModelContext(_ context: ModelContext) {
        self.settingsModelContext = context
    }

    private func getActiveAppBundleIdentifier() -> String? {
        guard let activeApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return activeApp.bundleIdentifier
    }

    private func isAppExcluded(_ bundleIdentifier: String) -> Bool {
        guard let context = settingsModelContext ?? modelContext else { return false }
        guard settingsManager?.enableAppExclusion == true else { return false }

        let descriptor = FetchDescriptor<ExcludedApp>(
            predicate: #Predicate { app in
                app.bundleIdentifier == bundleIdentifier
            }
        )

        do {
            let excludedApps = try context.fetch(descriptor)
            return !excludedApps.isEmpty
        } catch {
            ErrorLogger.shared.log("Failed to fetch excluded apps", category: "SwiftData", error: error)
            return false
        }
    }
    
    func startMonitoring() {
        // Scheduled on the main run loop, so the block runs on the main actor.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkClipboard() }
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    /// What gets captured from a pasteboard holding text and/or an image.
    enum CaptureKind: Equatable {
        case text, image, combined
    }

    /// The capture-mode rules, kept pure so they can be tested. Files are
    /// handled before this and always captured.
    nonisolated static func captureKinds(
        for mode: ClipboardCaptureMode, hasText: Bool, hasImage: Bool
    ) -> [CaptureKind] {
        switch mode {
        case .textOnly:
            // Prefer text when both are present (Word also puts a picture of
            // the selection on the pasteboard), but still capture standalone
            // images such as screenshots.
            return hasText ? [.text] : (hasImage ? [.image] : [])
        case .imageOnly:
            return hasImage ? [.image] : (hasText ? [.text] : [])
        case .both:
            return (hasText ? [.text] : []) + (hasImage ? [.image] : [])
        case .bothAsOne:
            if hasText && hasImage { return [.combined] }
            return hasText ? [.text] : (hasImage ? [.image] : [])
        }
    }

    /// Files above this size are skipped, checked before anything is read.
    nonisolated static let maxFileSize = 100 * 1024 * 1024

    /// Runs every 0.5 s: must stay cheap until changeCount differs.
    private func checkClipboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }

        lastChangeCount = pasteboard.changeCount

        // Check if monitoring is paused
        if isPaused {
            return
        }

        // Check if the active app is excluded
        if let bundleId = getActiveAppBundleIdentifier(), isAppExcluded(bundleId) {
            return
        }

        // Files first, so a copied file isn't also captured as its path text.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let fileURL = urls.first,
           fileURL.isFileURL {
            captureFile(at: fileURL)
            return
        }

        // Read the text once; only probe for an image (no decoding) here.
        let text = pasteboard.string(forType: .string).flatMap { $0.isEmpty ? nil : $0 }
        let hasImage = NSImage.canInit(with: pasteboard)
        let captureMode = settingsManager?.clipboardCaptureMode ?? .textOnly

        for kind in Self.captureKinds(for: captureMode, hasText: text != nil, hasImage: hasImage) {
            switch kind {
            case .text:
                if let text { onClipboardChange?(.text(text)) }
            case .image:
                if let data = pasteboardImageData() { onClipboardChange?(.image(data)) }
            case .combined:
                if let text, let data = pasteboardImageData() {
                    onClipboardChange?(.combined(text, data))
                } else if let text {
                    onClipboardChange?(.text(text))
                }
            }
        }
    }

    /// Image bytes as the source app provided them: PNG, else TIFF, else
    /// whatever NSImage can read (PDF, JPEG, …) re-encoded as TIFF. Keeping
    /// the original encoding stores a Retina screenshot in a few MB instead of
    /// an uncompressed TIFF many times that size, and identical copies stay
    /// byte-identical for deduplication.
    private func pasteboardImageData() -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        if let tiff = pasteboard.data(forType: .tiff) { return tiff }
        return NSImage(pasteboard: pasteboard)?.tiffRepresentation
    }

    private func captureFile(at url: URL) {
        let fileURL = url.resolvingSymlinksInPath()
        let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        // Folders, packages (.app) and unreachable URLs have no single blob to store.
        guard values?.isRegularFile == true else { return }
        if let size = values?.fileSize, size > Self.maxFileSize {
            ErrorLogger.shared.debug("Skipped copied file over the size limit (\(size) bytes)", category: "Clipboard")
            return
        }

        let uti = UTType(filenameExtension: fileURL.pathExtension)?.identifier ?? "public.data"
        // Up to 100 MB: read off the main thread (this runs from the poll
        // timer), then hand the item over on the main actor.
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let data = try Data(contentsOf: fileURL)
                await self?.deliver(.file(url, uti, data))
            } catch {
                ErrorLogger.shared.log("Failed to read copied file", category: "Clipboard", error: error)
            }
        }
    }

    private func deliver(_ content: ClipboardContent) {
        onClipboardChange?(content)
    }

    func copyToClipboard(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }
    
    func copyToClipboard(_ image: NSImage) {
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        lastChangeCount = pasteboard.changeCount
    }
    
    /// Puts a file on the pasteboard. The file stays on disk until the next
    /// file copy — see PasteboardFileStore.
    @discardableResult
    func copyFileToClipboard(data: Data, fileName: String) -> Bool {
        do {
            let fileURL = try PasteboardFileStore.write(data, fileName: fileName)
            pasteboard.clearContents()
            pasteboard.writeObjects([fileURL as NSURL])
            lastChangeCount = pasteboard.changeCount
            return true
        } catch {
            ErrorLogger.shared.log("Failed to create temp file for clipboard", category: "Clipboard", error: error)
            return false
        }
    }

    func saveItemToFile(_ item: CBItem) {
        let savePanel = NSSavePanel()

        // Configure save panel based on item type
        switch item.itemType {
        case .text:
            savePanel.allowedContentTypes = [.plainText]
            savePanel.nameFieldStringValue = "clipboard_text.txt"

        case .image:
            savePanel.allowedContentTypes = [.png, .jpeg]
            savePanel.nameFieldStringValue = "clipboard_image.png"

        case .file:
            if let fileName = item.fileName {
                savePanel.nameFieldStringValue = fileName
                if let uti = item.fileUTI, let utType = UTType(uti) {
                    savePanel.allowedContentTypes = [utType]
                }
            } else {
                savePanel.nameFieldStringValue = "clipboard_file"
            }

        case .combined:
            // For combined items, save as a folder or prompt user
            savePanel.allowedContentTypes = [.folder]
            savePanel.nameFieldStringValue = "clipboard_combined"
            savePanel.canCreateDirectories = true
        }

        // Extract Sendable data from item before async closure
        let itemType = item.itemType
        let content = item.content
        let fileData = item.fileData

        // For images, extract tiff data synchronously
        let imageTiffData = item.image?.tiffRepresentation

        // Present save panel with @Sendable closure
        savePanel.begin { @MainActor result in
            guard result == .OK, let url = savePanel.url else { return }

            // Perform file writing on background queue
            Task.detached {
                do {
                    switch itemType {
                    case .text:
                        let textContent = content ?? ""
                        try textContent.write(to: url, atomically: true, encoding: .utf8)

                    case .image:
                        guard let tiffData = imageTiffData,
                              let bitmapRep = NSBitmapImageRep(data: tiffData) else { return }

                        let imageData: Data?
                        if url.pathExtension.lowercased() == "png" {
                            imageData = bitmapRep.representation(using: .png, properties: [:])
                        } else {
                            imageData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
                        }

                        guard let data = imageData else { return }
                        try data.write(to: url)

                    case .file:
                        guard let data = fileData else { return }
                        try data.write(to: url)

                    case .combined:
                        // Save both text and image in a folder
                        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

                        // Save text file
                        if let textContent = content {
                            let textFile = url.appendingPathComponent("text.txt")
                            try textContent.write(to: textFile, atomically: true, encoding: .utf8)
                        }

                        // Save image file
                        if let tiffData = imageTiffData,
                           let bitmapRep = NSBitmapImageRep(data: tiffData),
                           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                            let imageFile = url.appendingPathComponent("image.png")
                            try pngData.write(to: imageFile)
                        }
                    }

                    ErrorLogger.shared.debug("Item saved to file", category: "SaveToFile")
                } catch {
                    ErrorLogger.shared.log("Failed to save item to file", category: "SaveToFile", error: error)
                }
            }
        }
    }
    
    /// Puts the item on the pasteboard. Returns false when it has nothing to
    /// copy (missing content or undecodable image data).
    @discardableResult
    func copyItemToClipboard(_ item: CBItem) -> Bool {
        switch item.itemType {
        case .text:
            guard let content = item.content, !content.isEmpty else { return false }
            copyToClipboard(content)
            return true
        case .image:
            guard let image = item.image else { return false }
            copyToClipboard(image)
            return true
        case .file:
            guard let fileData = item.fileData, let fileName = item.fileName else { return false }
            return copyFileToClipboard(data: fileData, fileName: fileName)
        case .combined:
            // Copy both text and image to clipboard
            var objects: [NSPasteboardWriting] = []
            if let content = item.content, !content.isEmpty {
                objects.append(content as NSPasteboardWriting)
            }
            if let image = item.image {
                objects.append(image)
            }
            guard !objects.isEmpty else { return false }
            pasteboard.clearContents()
            pasteboard.writeObjects(objects)
            lastChangeCount = pasteboard.changeCount
            return true
        }
    }

    // MARK: - Pause Timer Methods

    /// Pause clipboard monitoring for a specified duration
    /// - Parameter seconds: Duration in seconds to pause monitoring
    func pauseMonitoring(for seconds: Int) {
        // Cancel any existing pause timer
        pauseTimer?.invalidate()

        // Set pause state
        isPaused = true
        pauseEndDate = Date().addingTimeInterval(TimeInterval(seconds))

        // Schedule timer to resume monitoring
        pauseTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumeMonitoring() }
        }
    }

    /// Resume clipboard monitoring immediately
    func resumeMonitoring() {
        pauseTimer?.invalidate()
        pauseTimer = nil
        isPaused = false
        pauseEndDate = nil
    }

    /// Get remaining pause time in seconds
    var remainingPauseTime: TimeInterval {
        guard let endDate = pauseEndDate, isPaused else { return 0 }
        let remaining = endDate.timeIntervalSinceNow
        return max(0, remaining)
    }
}
