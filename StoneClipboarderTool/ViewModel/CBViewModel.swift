//
//  CBViewModel.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import AppKit
import Foundation
import SwiftData
import SwiftUI

@MainActor
class CBViewModel: ObservableObject {
    @Published var items: [CBItem] = []
    @Published var selectedItem: CBItem?
    @Published var isLoadingMore = false

    private var _modelContext: ModelContext?

    var modelContext: ModelContext? {
        return _modelContext
    }
    private let clipboardManager = ClipboardManager()
    private var settingsManager: SettingsManager?

    private let defaultFetchLimit = 100
    private var currentFetchOffset = 0

    // Memory management
    private var memoryCleanupTimer: Timer?
    private var lastAccessTimes: [PersistentIdentifier: Date] = [:]

    init() {
        setupClipboardMonitoring()
        startMemoryCleanupTimer()
    }

    func setModelContext(_ context: ModelContext) {
        self._modelContext = context
        fetchItems()
    }

    func setSettingsManager(_ manager: SettingsManager) {
        self.settingsManager = manager
        startMemoryCleanupTimer()

        // Trigger cleanup when maxItemsToKeep changes
        if manager.enableAutoCleanup {
            performItemCountCleanup()
        }
    }

    func fetchItems(limit: Int? = nil, reset: Bool = false) {
        guard let modelContext = _modelContext else { return }

        if reset {
            currentFetchOffset = 0
            items.removeAll()
        } else {
            isLoadingMore = true
        }

        let fetchLimit = limit ?? defaultFetchLimit
        var descriptor = FetchDescriptor<CBItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = fetchLimit
        descriptor.fetchOffset = currentFetchOffset

        // Always preload last 10 items immediately for instant display
        if reset {
            // First, get the most recent 30 items synchronously for instant display
            var recentDescriptor = FetchDescriptor<CBItem>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            recentDescriptor.fetchLimit = 30

            do {
                let recentItems = try modelContext.fetch(recentDescriptor)
                
                // Deduplicate items based on persistentModelID
                var uniqueItems: [CBItem] = []
                var seenIds = Set<PersistentIdentifier>()
                
                for item in recentItems {
                    if !seenIds.contains(item.persistentModelID) {
                        uniqueItems.append(item)
                        seenIds.insert(item.persistentModelID)
                    }
                }
                
                self.items = uniqueItems
                self.currentFetchOffset = uniqueItems.count

                // Track access times for memory management
                for item in uniqueItems {
                    self.lastAccessTimes[item.persistentModelID] = Date()
                }

                // Don't automatically load more - only load when user actually scrolls
                // The 30 items are enough for immediate use
            } catch {
                print("Failed to fetch recent items: \(error)")
                self.items = []
            }
        } else {
            // For pagination, use async to avoid blocking UI
            Task {
                do {
                    let newItems = try modelContext.fetch(descriptor)
                    await MainActor.run {
                        // Deduplicate new items and check against existing items
                        var existingIds = Set(self.items.map { $0.persistentModelID })
                        var uniqueNewItems: [CBItem] = []
                        
                        for item in newItems {
                            if !existingIds.contains(item.persistentModelID) {
                                uniqueNewItems.append(item)
                                existingIds.insert(item.persistentModelID)
                            }
                        }
                        
                        self.items.append(contentsOf: uniqueNewItems)
                        self.isLoadingMore = false
                        self.currentFetchOffset += newItems.count

                        // Track access times for memory management
                        for item in uniqueNewItems {
                            self.lastAccessTimes[item.persistentModelID] = Date()
                        }
                    }
                } catch {
                    await MainActor.run {
                        print("Failed to fetch items: \(error)")
                        self.isLoadingMore = false
                    }
                }
            }
        }
    }

    func addItem(content: String? = nil) {
        guard let modelContext = _modelContext else { return }
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
        guard let modelContext = _modelContext else { return }
        modelContext.delete(item)

        do {
            try modelContext.save()
            fetchItems(reset: true)
        } catch {
            print("Failed to delete item: \(error)")
        }
    }

    func deleteItems(at offsets: IndexSet, from items: [CBItem]) {
        guard let modelContext = _modelContext else { return }
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
        lastAccessTimes[item.persistentModelID] = Date()
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
        guard let modelContext = _modelContext else { return }

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
        guard let modelContext = _modelContext else { return }
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

    func addFileItem(url: URL, uti: String?, data: Data?) {
        addOrUpdateFileItem(url: url, uti: uti, data: data)
    }

    private func addOrUpdateFileItem(url: URL, uti: String?, data: Data?) {
        guard let modelContext = _modelContext else { return }

        let tempItem = CBItem(
            timestamp: Date(), fileData: data, fileName: url.lastPathComponent, fileUTI: uti,
            itemType: .file)

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
        copyAndUpdateItem(item)
    }

    func copyAndUpdateItem(_ item: CBItem) {
        clipboardManager.copyItemToClipboard(item)

        guard let modelContext = _modelContext else { return }
        item.timestamp = Date()

        markItemAccessed(item)

        do {
            try modelContext.save()
            fetchItems(reset: true)
        } catch {
            print("Failed to update item: \(error)")
        }
    }

    func saveItemToFile(_ item: CBItem) {
        clipboardManager.saveItemToFile(item)
    }

    func openInPreview(item: CBItem) {
        Task {
            do {
                try await openInPreviewAsync(item: item)
            } catch {
                print("Failed to open in preview: \(error)")
            }
        }
    }

    private func openInPreviewAsync(item: CBItem) async throws {
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

    func updateItemContent(_ item: CBItem, newContent: String) {
        guard let modelContext = _modelContext else { return }

        item.content = newContent
        item.contentPreview = newContent.prefix(100).description
        item.timestamp = Date()

        markItemAccessed(item)

        do {
            try modelContext.save()
            fetchItems(reset: true)
        } catch {
            print("Failed to update item content: \(error)")
        }
    }

    func toggleFavorite(_ item: CBItem) {
        guard let modelContext = _modelContext else { return }

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
        guard let modelContext = _modelContext else { return }

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
        guard let modelContext = _modelContext else { return }

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
        guard let modelContext = _modelContext else { return }

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

    func performManualCleanup() {
        guard let settingsManager = settingsManager else { return }

        if settingsManager.enableAutoCleanup {
            performItemCountCleanup()
        }

        if settingsManager.enableMemoryCleanup {
            performMemoryCleanup()
        }
    }

    // MARK: - Memory Management

    private func startMemoryCleanupTimer() {
        guard let settingsManager = settingsManager,
            settingsManager.enableMemoryCleanup
        else { return }

        let interval = TimeInterval(settingsManager.memoryCleanupInterval * 60)
        memoryCleanupTimer?.invalidate()
        memoryCleanupTimer = Timer.scheduledTimer(
            withTimeInterval: interval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.performMemoryCleanup()
            }
        }
    }

    private func performMemoryCleanup() {
        guard let settingsManager = settingsManager,
            settingsManager.enableMemoryCleanup
        else { return }

        let now = Date()
        let maxInactiveTime = TimeInterval(settingsManager.maxInactiveTime * 60)
        var itemsToCleanup: [CBItem] = []

        for item in items {
            if let lastAccess = lastAccessTimes[item.persistentModelID] {
                if now.timeIntervalSince(lastAccess) > maxInactiveTime {
                    itemsToCleanup.append(item)
                }
            }
        }

        for item in itemsToCleanup {
            cleanupItemMemory(item)
        }

        let cutoffTime = now.addingTimeInterval(-maxInactiveTime)
        lastAccessTimes = lastAccessTimes.filter { $1 > cutoffTime }

        print("Memory cleanup: Released \(itemsToCleanup.count) inactive items")
    }

    private func cleanupItemMemory(_ item: CBItem) {
        item.thumbnailData = nil
        lastAccessTimes.removeValue(forKey: item.persistentModelID)
    }

    private func performCleanupIfNeeded() {
        guard let settingsManager = settingsManager else { return }

        // Perform item count cleanup if enabled (check every 10 new items)
        if settingsManager.enableAutoCleanup && items.count % 10 == 0 {
            performItemCountCleanup()
        }

        // Perform memory cleanup if enabled (check every 100 items)
        if settingsManager.enableMemoryCleanup && items.count % 100 == 0 {
            Task {
                await Task.detached {
                    await MainActor.run {
                        self.performMemoryCleanup()
                    }
                }.value
            }
        }
    }

    private func performItemCountCleanup() {
        guard let modelContext = _modelContext,
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

                // Refresh items after cleanup
                fetchItems(reset: true)

                print(
                    "Auto-cleanup: Removed \(nonFavoriteOldItems.count) old items, keeping under \(settingsManager.maxItemsToKeep) limit"
                )
            }
        } catch {
            print("Failed to perform item count cleanup: \(error)")
        }
    }

    func markItemAccessed(_ item: CBItem) {
        lastAccessTimes[item.persistentModelID] = Date()
    }

    func openFileInExternalApp(_ item: CBItem) throws {
        guard item.itemType == .file else {
            throw NSError(
                domain: "CBViewModel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Item is not a file"])
        }

        guard let fileData = item.fileData else {
            throw NSError(
                domain: "CBViewModel",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No file data available"])
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = item.fileName ?? "unknown_file"
        let tempFileName = "clipboard_file_\(UUID().uuidString)_\(fileName)"
        let tempFile = tempDir.appendingPathComponent(tempFileName)

        try fileData.write(to: tempFile)
        NSWorkspace.shared.open(tempFile)

        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
            try? FileManager.default.removeItem(at: tempFile)
        }
    }

    deinit {
        memoryCleanupTimer?.invalidate()
    }
}
