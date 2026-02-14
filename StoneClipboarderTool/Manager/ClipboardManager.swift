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

enum ClipboardContent {
    case text(String)
    case image(NSImage)
    case file(URL, String, Data) // URL, UTI, Data
    case combined(String, NSImage) // Text + Image together
}

class ClipboardManager: ObservableObject {
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
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
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

        let captureMode = settingsManager?.clipboardCaptureMode ?? .textOnly

        // ALWAYS check for files first to prevent them from being captured as text
        // This is critical to fix the issue where file URLs were being saved as text
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let fileURL = urls.first,
           fileURL.isFileURL {
            handleFileFromURL(fileURL)
            return // Exit early - files are handled, don't process text/image
        }

        // Now handle text and image based on capture mode
        // Note: This only applies to non-file clipboard content
        let hasText = pasteboard.string(forType: .string).map { !$0.isEmpty } ?? false
        let hasImage = NSImage(pasteboard: pasteboard) != nil

        switch captureMode {
        case .textOnly:
            // Prefer text when both text and image are present (e.g., Microsoft Word)
            // But still capture standalone images (e.g., screenshots)
            if hasText && hasImage {
                // Both present - prefer text only
                if let content = pasteboard.string(forType: .string) {
                    onClipboardChange?(.text(content))
                }
            } else if hasText {
                // Only text available
                if let content = pasteboard.string(forType: .string) {
                    onClipboardChange?(.text(content))
                }
            } else if hasImage {
                // Only image available (e.g., screenshots) - capture it
                if let image = NSImage(pasteboard: pasteboard) {
                    onClipboardChange?(.image(image))
                }
            }

        case .imageOnly:
            // Prefer images when both are present
            // But still capture text when there's no image
            if hasText && hasImage {
                // Both present - prefer image only
                if let image = NSImage(pasteboard: pasteboard) {
                    onClipboardChange?(.image(image))
                }
            } else if hasImage {
                // Only image available
                if let image = NSImage(pasteboard: pasteboard) {
                    onClipboardChange?(.image(image))
                }
            } else if hasText {
                // Only text available - capture it
                if let content = pasteboard.string(forType: .string) {
                    onClipboardChange?(.text(content))
                }
            }

        case .both:
            // Capture both text and image if both are present
            // This is useful for apps like Microsoft Word that put both on clipboard
            if hasText && hasImage {
                // First capture text
                if let content = pasteboard.string(forType: .string) {
                    onClipboardChange?(.text(content))
                }
                // Then capture image as a separate item
                if let image = NSImage(pasteboard: pasteboard) {
                    onClipboardChange?(.image(image))
                }
            } else if hasText {
                // Only text available
                if let content = pasteboard.string(forType: .string) {
                    onClipboardChange?(.text(content))
                }
            } else if hasImage {
                // Only image available
                if let image = NSImage(pasteboard: pasteboard) {
                    onClipboardChange?(.image(image))
                }
            }

        case .bothAsOne:
            // Capture text and image together as one combined item
            if hasText && hasImage {
                // Both present - capture as combined item
                if let content = pasteboard.string(forType: .string),
                   let image = NSImage(pasteboard: pasteboard) {
                    onClipboardChange?(.combined(content, image))
                }
            } else if hasText {
                // Only text available
                if let content = pasteboard.string(forType: .string) {
                    onClipboardChange?(.text(content))
                }
            } else if hasImage {
                // Only image available
                if let image = NSImage(pasteboard: pasteboard) {
                    onClipboardChange?(.image(image))
                }
            }
        }
    }
    
    private func handleFileFromURL(_ fileURL: URL) {
        do {
            // Check if file exists and is readable
            guard try fileURL.checkResourceIsReachable() else { return }
            
            // Get file data safely
            let fileData = try Data(contentsOf: fileURL)
            
            // Get UTI from file extension
            let uti = UTType(filenameExtension: fileURL.pathExtension)?.identifier ?? "public.data"
            
            // Safety check for file size (limit to 100MB)
            let maxFileSize = 100 * 1024 * 1024 // 100MB
            guard fileData.count <= maxFileSize else {
                print("File too large: \(fileData.count) bytes")
                return
            }
            
            onClipboardChange?(.file(fileURL, uti, fileData))
        } catch {
            print("Error reading file: \(error.localizedDescription)")
        }
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
    
    @MainActor
    private func createSavePanel() -> NSSavePanel? {
        // Try to create save panel safely
        let savePanel = NSSavePanel()

        // Test if we can access basic properties (will fail in strict sandbox)
        _ = savePanel.canCreateDirectories
        return savePanel
    }
    
    func copyFileToClipboard(data: Data, fileName: String, uti: String) {
        // Create a temporary file to copy to clipboard
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(fileName)
        
        do {
            try data.write(to: tempFile)
            
            pasteboard.clearContents()
            pasteboard.writeObjects([tempFile as NSURL])
            lastChangeCount = pasteboard.changeCount
            
            // Clean up temp file after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                try? FileManager.default.removeItem(at: tempFile)
            }
        } catch {
            print("Error creating temp file for clipboard: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    func saveItemToFile(_ item: CBItem) {
        // Try to create save panel - if it crashes, it's likely a sandbox issue
        guard let savePanel = createSavePanel() else {
            print("Cannot create save panel - check app sandbox entitlements")
            return
        }

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

                    await MainActor.run {
                        print("File saved successfully")
                    }

                } catch {
                    await MainActor.run {
                        print("Error saving file: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    func copyItemToClipboard(_ item: CBItem) {
        switch item.itemType {
        case .text:
            if let content = item.content {
                copyToClipboard(content)
            }
        case .image:
            if let image = item.image {
                copyToClipboard(image)
            }
        case .file:
            if let fileData = item.fileData,
               let fileName = item.fileName,
               let uti = item.fileUTI {
                copyFileToClipboard(data: fileData, fileName: fileName, uti: uti)
            }
        case .combined:
            // Copy both text and image to clipboard
            pasteboard.clearContents()
            var objects: [NSPasteboardWriting] = []

            if let content = item.content {
                objects.append(content as NSPasteboardWriting)
            }
            if let image = item.image {
                objects.append(image)
            }

            if !objects.isEmpty {
                pasteboard.writeObjects(objects)
                lastChangeCount = pasteboard.changeCount
            }
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
            self?.resumeMonitoring()
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
