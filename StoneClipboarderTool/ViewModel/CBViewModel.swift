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
    @Published var selectedItem: CBItem?
    private var modelContext: ModelContext?
    private let clipboardManager = ClipboardManager()
    private var settingsManager: SettingsManager?

    private let defaultFetchLimit = 100
    private var currentFetchOffset = 0

    init() {
        setupClipboardMonitoring()
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        fetchItems()
    }

    func setSettingsManager(_ manager: SettingsManager) {
        self.settingsManager = manager
    }

    func fetchItems(limit: Int? = nil, reset: Bool = false) {
        guard let modelContext = modelContext else { return }

        if reset {
            currentFetchOffset = 0
            items.removeAll()
        }

        let fetchLimit = limit ?? defaultFetchLimit
        var descriptor = FetchDescriptor<CBItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = fetchLimit
        descriptor.fetchOffset = currentFetchOffset

        do {
            let newItems = try modelContext.fetch(descriptor)
            if reset {
                items = newItems
            } else {
                items.append(contentsOf: newItems)
            }
            currentFetchOffset += newItems.count
        } catch {
            print("Failed to fetch items: \(error)")
            if reset { items = [] }
        }
    }

    func addItem(content: String? = nil) {
        guard let modelContext = modelContext else { return }
        let newItem = CBItem(timestamp: Date(), content: content)
        modelContext.insert(newItem)

        do {
            try modelContext.save()
            fetchItems(reset: true)
            performCleanupIfNeeded()
        } catch {
            print("Failed to save item: \(error)")
        }
    }

    func deleteItem(_ item: CBItem) {
        guard let modelContext = modelContext else { return }
        modelContext.delete(item)

        do {
            try modelContext.save()
            fetchItems(reset: true)
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
            fetchItems(reset: true)
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

    func selectItem(_ item: CBItem) {
        selectedItem = item
    }

    private func handleClipboardChange(_ clipboardContent: ClipboardContent) {
        switch clipboardContent {
        case .text(let content):
            addOrUpdateTextItem(content: content)
        case .image(let image):
            addOrUpdateImageItem(image: image)
        case .file(let url, let uti, let data):
            addOrUpdateFileItem(url: url, uti: uti, data: data)
        }
    }

    func addTextItem(content: String) {
        addOrUpdateTextItem(content: content)
    }

    private func addOrUpdateTextItem(content: String) {
        guard let modelContext = modelContext else { return }

        let tempItem = CBItem(timestamp: Date(), content: content, itemType: .text)

        if let existingItem = CBItem.findExistingItem(in: items, matching: tempItem) {
            existingItem.timestamp = Date()
        } else {
            modelContext.insert(tempItem)
        }

        do {
            try modelContext.save()
            fetchItems(reset: true)
            performCleanupIfNeeded()
        } catch {
            print("Failed to save text item: \(error)")
        }
    }

    func addImageItem(image: NSImage) {
        addOrUpdateImageItem(image: image)
    }

    private func addOrUpdateImageItem(image: NSImage) {
        guard let modelContext = modelContext else { return }
        guard let imageData = image.tiffRepresentation else { return }

        let tempItem = CBItem(timestamp: Date(), imageData: imageData, itemType: .image)

        if let existingItem = CBItem.findExistingItem(in: items, matching: tempItem) {
            existingItem.timestamp = Date()
        } else {
            modelContext.insert(tempItem)
        }

        do {
            try modelContext.save()
            fetchItems(reset: true)
            performCleanupIfNeeded()
        } catch {
            print("Failed to save image item: \(error)")
        }
    }

    func addFileItem(url: URL, uti: String, data: Data) {
        addOrUpdateFileItem(url: url, uti: uti, data: data)
    }

    private func addOrUpdateFileItem(url: URL, uti: String, data: Data) {
        guard let modelContext = modelContext else { return }

        let fileName = url.lastPathComponent
        let tempItem = CBItem(
            timestamp: Date(),
            fileData: data,
            fileName: fileName,
            fileUTI: uti,
            itemType: .file
        )

        if let existingItem = CBItem.findExistingItem(in: items, matching: tempItem) {
            existingItem.timestamp = Date()
        } else {
            modelContext.insert(tempItem)
        }

        do {
            try modelContext.save()
            fetchItems(reset: true)
            performCleanupIfNeeded()
        } catch {
            print("Failed to save file item: \(error)")
        }
    }

    func copyItem(_ item: CBItem) {
        clipboardManager.copyItemToClipboard(item)

        guard let modelContext = modelContext else { return }
        item.timestamp = Date()

        do {
            try modelContext.save()
            fetchItems(reset: true)
        } catch {
            print("Failed to update item timestamp: \(error)")
        }
    }

    func saveItemToFile(_ item: CBItem) {
        clipboardManager.saveItemToFile(item)
    }

    func copyAndUpdateItem(_ item: CBItem) {
        clipboardManager.copyItemToClipboard(item)

        guard let modelContext = modelContext else { return }
        item.timestamp = Date()

        do {
            try modelContext.save()
            fetchItems(reset: true)
        } catch {
            print("Failed to update item timestamp: \(error)")
        }
    }

    func updateItemContent(_ item: CBItem, newContent: String) {
        guard let modelContext = modelContext else { return }

        item.content = newContent
        item.contentPreview = newContent.prefix(100).description
        item.timestamp = Date()

        do {
            try modelContext.save()
            fetchItems(reset: true)
        } catch {
            print("Failed to update item content: \(error)")
        }
    }

    func toggleFavorite(_ item: CBItem) {
        guard let modelContext = modelContext else { return }

        item.isFavorite.toggle()

        if item.isFavorite {
            let maxOrderIndex = items.filter { $0.isFavorite }.map { $0.orderIndex }.max() ?? -1
            item.orderIndex = maxOrderIndex + 1
        } else {
            item.orderIndex = 0
        }

        do {
            try modelContext.save()
            fetchItems(reset: true)
        } catch {
            print("Failed to toggle favorite: \(error)")
        }
    }

    func updateFavoriteOrder(_ favorites: [CBItem]) {
        guard let modelContext = modelContext else { return }

        for (index, item) in favorites.enumerated() {
            item.orderIndex = index
        }

        do {
            try modelContext.save()
            fetchItems(reset: true)
        } catch {
            print("Failed to update favorite order: \(error)")
        }
    }

    var favoriteItems: [CBItem] {
        return items.filter { $0.isFavorite }.sorted { $0.orderIndex < $1.orderIndex }
    }

    var recentItems: [CBItem] {
        return items.sorted { $0.timestamp > $1.timestamp }
    }

    func deleteAllItems() {
        guard let modelContext = modelContext else { return }

        for item in items {
            modelContext.delete(item)
        }

        do {
            try modelContext.save()
            fetchItems(reset: true)
        } catch {
            print("Failed to delete all items: \(error)")
        }
    }

    func deleteAllFavorites() {
        guard let modelContext = modelContext else { return }

        for item in items where item.isFavorite {
            item.isFavorite = false
            item.orderIndex = 0
        }

        do {
            try modelContext.save()
            fetchItems(reset: true)
        } catch {
            print("Failed to clear all favorites: \(error)")
        }
    }

    func loadMoreItems() {
        fetchItems()
    }

    private func performCleanupIfNeeded() {
        guard let modelContext = modelContext,
            let settingsManager = settingsManager,
            settingsManager.enableAutoCleanup
        else { return }

        let countDescriptor = FetchDescriptor<CBItem>()
        do {
            let totalCount = try modelContext.fetchCount(countDescriptor)

            if totalCount > settingsManager.maxItemsToKeep {
                let itemsToDelete = totalCount - settingsManager.maxItemsToKeep
                var oldItemsDescriptor = FetchDescriptor<CBItem>(
                    sortBy: [SortDescriptor(\.timestamp, order: .forward)]
                )
                oldItemsDescriptor.fetchLimit = itemsToDelete

                let oldItems = try modelContext.fetch(oldItemsDescriptor)
                let nonFavoriteOldItems = oldItems.filter { !$0.isFavorite }

                for item in nonFavoriteOldItems {
                    modelContext.delete(item)
                }

                try modelContext.save()
            }
        } catch {
            print("Failed to perform cleanup: \(error)")
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
                throw NSError(
                    domain: "CBViewModel", code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Only image files can be opened in Preview"
                    ])
            }
        case .text:
            throw NSError(
                domain: "CBViewModel", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Text items cannot be opened in Preview"])
        }
    }

    private func openImageInPreview(_ item: CBItem) async throws {
        guard let image = item.image else {
            throw NSError(
                domain: "CBViewModel", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No image data available"])
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "clipboard_image_\(UUID().uuidString).png"
        let tempFile = tempDir.appendingPathComponent(fileName)

        guard let tiffData = image.tiffRepresentation,
            let bitmapRep = NSBitmapImageRep(data: tiffData),
            let pngData = bitmapRep.representation(using: .png, properties: [:])
        else {
            throw NSError(
                domain: "CBViewModel", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to PNG"])
        }

        try pngData.write(to: tempFile)
        NSWorkspace.shared.open(tempFile)

        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
            try? FileManager.default.removeItem(at: tempFile)
        }
    }

    private func generateThumbnailData(from image: NSImage) -> Data? {
        let maxSize: CGFloat = 100
        let imageSize = image.size

        // Calculate thumbnail size maintaining aspect ratio
        let aspectRatio = imageSize.width / imageSize.height
        var thumbnailSize: NSSize

        if aspectRatio > 1 {
            thumbnailSize = NSSize(width: maxSize, height: maxSize / aspectRatio)
        } else {
            thumbnailSize = NSSize(width: maxSize * aspectRatio, height: maxSize)
        }

        let thumbnail = NSImage(size: thumbnailSize)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: thumbnailSize))
        thumbnail.unlockFocus()

        return thumbnail.tiffRepresentation
    }

    private func openImageFileInPreview(_ item: CBItem) async throws {
        guard let fileData = item.fileData,
            let fileName = item.fileName
        else {
            throw NSError(
                domain: "CBViewModel", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No file data available"])
        }

        let tempDir = FileManager.default.temporaryDirectory
        let tempFileName = "clipboard_file_\(UUID().uuidString)_\(fileName)"
        let tempFile = tempDir.appendingPathComponent(tempFileName)

        try fileData.write(to: tempFile)
        NSWorkspace.shared.open(tempFile)

        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
            try? FileManager.default.removeItem(at: tempFile)
        }
    }
}
