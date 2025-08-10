//
//  ClipboardManager.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

enum ClipboardContent {
    case text(String)
    case image(NSImage)
    case file(URL, String, Data) // URL, UTI, Data
}

class ClipboardManager: ObservableObject {
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let pasteboard = NSPasteboard.general
    
    var onClipboardChange: ((ClipboardContent) -> Void)?
    
    init() {
        lastChangeCount = pasteboard.changeCount
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
        
        // Check for files first (highest priority)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let fileURL = urls.first,
           fileURL.isFileURL {
            handleFileFromURL(fileURL)
        }
        // Check for images (medium priority)
        else if let image = NSImage(pasteboard: pasteboard) {
            onClipboardChange?(.image(image))
        }
        // Check for text (lowest priority)
        else if let content = pasteboard.string(forType: .string), !content.isEmpty {
            onClipboardChange?(.text(content))
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
    
    private func createSavePanel() -> NSSavePanel? {
        // Try to create save panel safely
        let savePanel = NSSavePanel()
        
        // Test if we can access basic properties (will fail in strict sandbox)
        do {
            _ = savePanel.canCreateDirectories
            return savePanel
        } catch {
            return nil
        }
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
    
    func saveItemToFile(_ item: CBItem) {
        // Ensure we're on main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.saveItemToFile(item)
            }
            return
        }
        
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
        }
        
        // Present save panel
        savePanel.begin { result in
            guard result == .OK, let url = savePanel.url else { return }
            
            // Perform file writing on background queue
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    switch item.itemType {
                    case .text:
                        let content = item.content ?? ""
                        try content.write(to: url, atomically: true, encoding: .utf8)
                        
                    case .image:
                        guard let image = item.image,
                              let tiffData = image.tiffRepresentation,
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
                        guard let fileData = item.fileData else { return }
                        try fileData.write(to: url)
                    }
                    
                    DispatchQueue.main.async {
                        print("File saved successfully")
                    }
                    
                } catch {
                    DispatchQueue.main.async {
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
        }
    }
}
