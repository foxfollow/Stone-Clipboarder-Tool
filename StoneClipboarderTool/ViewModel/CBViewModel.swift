//
//  CBViewModel.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import Foundation
import SwiftData
import SwiftUI
import AppKit

@MainActor
class CBViewModel: ObservableObject {
    @Published var items: [CBItem] = []
    private var modelContext: ModelContext?
    private let clipboardManager = ClipboardManager()

    init() {
        setupClipboardMonitoring()
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        fetchItems()
    }

    func fetchItems() {
        guard let modelContext = modelContext else { return }
        let descriptor = FetchDescriptor<CBItem>(sortBy: [
            SortDescriptor(\.timestamp, order: .reverse)
        ])
        do {
            items = try modelContext.fetch(descriptor)
        } catch {
            print("Failed to fetch items: \(error)")
            items = []
        }
    }

    func addItem(content: String? = nil) {
        guard let modelContext = modelContext else { return }
        let newItem = CBItem(timestamp: Date(), content: content)
        modelContext.insert(newItem)
        do {
            try modelContext.save()
            fetchItems()
        } catch {
            print("Failed to save item: \(error)")
        }
    }

    func deleteItem(_ item: CBItem) {
        guard let modelContext = modelContext else { return }
        modelContext.delete(item)
        do {
            try modelContext.save()
            fetchItems()
        } catch {
            print("Failed to delete item: \(error)")
        }
    }

    func deleteItems(at offsets: IndexSet, from items: [CBItem]) {
        guard let modelContext = modelContext else { return }
        for index in offsets {
            modelContext.delete(items[index])
        }
        do {
            try modelContext.save()
            fetchItems()
        } catch {
            print("Failed to delete items: \(error)")
        }
    }
    
    private func setupClipboardMonitoring() {
        clipboardManager.onClipboardChange = { [weak self] content in
            Task { @MainActor in
                self?.handleClipboardChange(content)
            }
        }
    }
    
    func startClipboardMonitoring() {
        clipboardManager.startMonitoring()
    }
    
    func stopClipboardMonitoring() {
        clipboardManager.stopMonitoring()
    }
    
    private func handleClipboardChange(_ clipboardContent: ClipboardContent) {
        switch clipboardContent {
        case .text(let content):
            // Avoid duplicates by checking if the latest item has the same content
            if let lastItem = items.first, lastItem.itemType == .text, lastItem.content == content {
                return
            }
            addTextItem(content: content)
        case .image(let image):
            // For images, always save since comparing image data is expensive
            addImageItem(image: image)
        case .file(let url, let uti, let data):
            // For files, always save since comparing file data could be expensive
            addFileItem(url: url, uti: uti, data: data)
        }
    }
    
    func addTextItem(content: String) {
        guard let modelContext = modelContext else { return }
        let newItem = CBItem(timestamp: Date(), content: content, itemType: .text)
        modelContext.insert(newItem)
        do {
            try modelContext.save()
            fetchItems()
        } catch {
            print("Failed to save text item: \(error)")
        }
    }
    
    func addImageItem(image: NSImage) {
        guard let modelContext = modelContext else { return }
        guard let imageData = image.tiffRepresentation else { return }
        
        let newItem = CBItem(timestamp: Date(), imageData: imageData, itemType: .image)
        modelContext.insert(newItem)
        do {
            try modelContext.save()
            fetchItems()
        } catch {
            print("Failed to save image item: \(error)")
        }
    }
    
    func addFileItem(url: URL, uti: String, data: Data) {
        guard let modelContext = modelContext else { return }
        
        let fileName = url.lastPathComponent
        let newItem = CBItem(
            timestamp: Date(),
            fileData: data,
            fileName: fileName,
            fileUTI: uti,
            itemType: .file
        )
        
        modelContext.insert(newItem)
        do {
            try modelContext.save()
            fetchItems()
        } catch {
            print("Failed to save file item: \(error)")
        }
    }
    
    func copyItem(_ item: CBItem) {
        clipboardManager.copyItemToClipboard(item)
        
        // Update timestamp to move it to top
        guard let modelContext = modelContext else { return }

        item.timestamp = Date()
        
        do {
            try modelContext.save()
            fetchItems()
        } catch {
            print("Failed to update item timestamp: \(error)")
        }

    }
    
    func saveItemToFile(_ item: CBItem) {
        clipboardManager.saveItemToFile(item)
    }
    
    func copyAndUpdateItem(_ item: CBItem) {
        
        // Copy to clipboard based on item type
        clipboardManager.copyItemToClipboard(item)
        
        guard let modelContext = modelContext else { return }
        // Update timestamp to move it to top
        item.timestamp = Date()
        
        do {
            try modelContext.save()
            fetchItems()
        } catch {
            print("Failed to update item timestamp: \(error)")
        }
    }
    
    func updateItemContent(_ item: CBItem, newContent: String) {
        guard let modelContext = modelContext else { return }
        
        // Update the item's content
        item.content = newContent
        item.timestamp = Date() // Update timestamp to move it to top
        
        do {
            try modelContext.save()
            fetchItems()
        } catch {
            print("Failed to update item content: \(error)")
        }
    }
    
    func deleteAllItems() {
        guard let modelContext = modelContext else { return }
        
        // Delete all items
        for item in items {
            modelContext.delete(item)
        }
        
        do {
            try modelContext.save()
            fetchItems()
        } catch {
            print("Failed to delete all items: \(error)")
        }
    }
    
    func openInPreview(item: CBItem) async throws {
        switch item.itemType {
        case .image:
            try await openImageInPreview(item)
        case .file:
            if item.isImageFile {
                try await openImageFileInPreview(item)
            } else {
                throw NSError(domain: "CBViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Only image files can be opened in Preview"])
            }
        case .text:
            throw NSError(domain: "CBViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Text items cannot be opened in Preview"])
        }
    }
    
    private func openImageInPreview(_ item: CBItem) async throws {
        guard let image = item.image else {
            throw NSError(domain: "CBViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No image data available"])
        }
        
        // Create temporary file for the image
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "clipboard_image_\(UUID().uuidString).png"
        let tempFile = tempDir.appendingPathComponent(fileName)
        
        // Convert image to PNG data
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "CBViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to PNG"])
        }
        
        // Write to temporary file
        try pngData.write(to: tempFile)
        
        // Open in Preview.app
        NSWorkspace.shared.open(tempFile)
        
        // Clean up temp file after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
            try? FileManager.default.removeItem(at: tempFile)
        }
    }
    
    private func openImageFileInPreview(_ item: CBItem) async throws {
        guard let fileData = item.fileData,
              let fileName = item.fileName else {
            throw NSError(domain: "CBViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No file data available"])
        }
        
        // Create temporary file with original extension
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileName = "clipboard_file_\(UUID().uuidString)_\(fileName)"
        let tempFile = tempDir.appendingPathComponent(tempFileName)
        
        // Write file data to temporary file
        try fileData.write(to: tempFile)
        
        // Open in Preview.app
        NSWorkspace.shared.open(tempFile)
        
        // Clean up temp file after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
            try? FileManager.default.removeItem(at: tempFile)
        }
    }
}
