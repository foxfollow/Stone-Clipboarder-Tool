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
    // Non-favorite items on disk. Favorites are tracked separately and never
    // counted against this number, so they can't be auto-cleaned.
    @Published var totalItemCount: Int = 0
    @Published var favoriteItemCount: Int = 0

    var inMemoryItemCount: Int { items.count }

    private var _modelContext: ModelContext?

    var modelContext: ModelContext? {
        return _modelContext
    }
    private let clipboardManager = ClipboardManager()
    private var settingsManager: SettingsManager?

    /// Rows shown before the first scroll, and the fewest a refresh reloads.
    private let initialBatchSize = 30
    /// Rows appended per `loadMoreItems()`.
    private let pageSize = 100
    /// False once a page came back short: `items` holds the whole history.
    private var canLoadMore = true

    // Memory management
    nonisolated(unsafe) private var memoryCleanupTimer: Timer?
    private var lastAccessTimes: [PersistentIdentifier: Date] = [:]

    init() {
        setupClipboardMonitoring()
        startMemoryCleanupTimer()
    }

    func setModelContext(_ context: ModelContext) {
        self._modelContext = context
        clipboardManager.setModelContext(context)
    }

    func setSettingsManager(_ manager: SettingsManager) {
        self.settingsManager = manager
        clipboardManager.settingsManager = manager
        startMemoryCleanupTimer()

        // Trigger cleanup when maxItemsToKeep changes
        if manager.enableAutoCleanup {
            performItemCountCleanup()
        }
    }

    func getClipboardManager() -> ClipboardManager {
        return clipboardManager
    }

    /// Loads history rows, newest first.
    /// - reset: replace `items` with a fresh fetch of `limit` rows. The default
    ///   keeps at least as many rows as are loaded now, so a refresh after a
    ///   copy doesn't collapse a list the user has scrolled down.
    /// - otherwise: append the next page (`limit` defaults to `pageSize`).
    func fetchItems(limit: Int? = nil, reset: Bool = false) {
        if reset {
            reloadItems(limit: limit ?? max(initialBatchSize, items.count))
        } else {
            loadNextPage(size: limit ?? pageSize)
        }
    }

    private func reloadItems(limit: Int) {
        guard let modelContext = _modelContext else { return }

        var descriptor = FetchDescriptor<CBItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        do {
            let fetched = try modelContext.fetch(descriptor)
            items = fetched
            canLoadMore = fetched.count == limit
            trackFirstAccess(of: fetched)
        } catch {
            ErrorLogger.shared.log("Failed to fetch recent items", category: "SwiftData", error: error)
            items = []
        }
        refreshItemCounts()
    }

    private func loadNextPage(size: Int) {
        guard let modelContext = _modelContext, !isLoadingMore, canLoadMore else { return }
        isLoadingMore = true

        // One turn later, so a scroll-triggered call doesn't mutate the list
        // from inside the appearing row's callback.
        Task { [weak self] in
            guard let self else { return }
            defer { self.isLoadingMore = false }

            var descriptor = FetchDescriptor<CBItem>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            // Deletes remove rows from `items` and every other change reloads
            // it, so `items` is always the newest N rows and its count is the
            // right offset; a separate counter drifted after each delete.
            descriptor.fetchOffset = self.items.count
            descriptor.fetchLimit = size

            do {
                let page = try modelContext.fetch(descriptor)
                // A copy saved while this page was pending shifts rows down
                // by one; skip anything already loaded.
                let loaded = Set(self.items.map(\.persistentModelID))
                let fresh = page.filter { !loaded.contains($0.persistentModelID) }
                self.items.append(contentsOf: fresh)
                self.canLoadMore = page.count == size
                self.trackFirstAccess(of: fresh)
            } catch {
                ErrorLogger.shared.log("Failed to fetch items (pagination)", category: "SwiftData", error: error)
            }
        }
    }

    /// Starts the inactivity clock for rows seen for the first time. Rows
    /// already tracked keep their time: reloading the list is not access.
    private func trackFirstAccess(of fetched: [CBItem]) {
        let now = Date()
        for item in fetched where lastAccessTimes[item.persistentModelID] == nil {
            lastAccessTimes[item.persistentModelID] = now
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
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to save item", category: "SwiftData", error: error)
        }
    }

    func deleteItem(_ item: CBItem) {
        guard let modelContext = _modelContext else { return }

        // Clear selection if this item is selected
        if selectedItem?.id == item.id {
            selectedItem = nil
            NotificationCenter.default.post(name: .init("ClearClipboardSelection"), object: nil)
        }

        // Tell PinManager so any open pin for this item closes.
        NotificationCenter.default.post(
            name: .clipboardItemDeleted, object: item.persistentModelID
        )

        // Remove from published array so SwiftUI drops the view
        items.removeAll { $0.id == item.id }

        // Defer context deletion to next run loop so SwiftUI finishes layout first
        DispatchQueue.main.async { [weak self] in
            modelContext.delete(item)
            do {
                try modelContext.save()
                self?.refreshItemCounts()
            } catch {
                modelContext.rollback()
                ErrorLogger.shared.log("Failed to delete item", category: "SwiftData", error: error)
                self?.fetchItems(reset: true)
            }
        }
    }

    func deleteItems(at offsets: IndexSet, from sourceItems: [CBItem]) {
        guard let modelContext = _modelContext else { return }

        let idsToDelete = Set(offsets.map { sourceItems[$0].id })
        let itemsToDelete = offsets.map { sourceItems[$0] }

        // Notify PinManager so pins referencing the about-to-be-deleted
        // items close themselves.
        for item in itemsToDelete {
            NotificationCenter.default.post(
                name: .clipboardItemDeleted, object: item.persistentModelID
            )
        }

        // Clear selection if deleted item is selected
        if let sel = selectedItem, idsToDelete.contains(sel.id) {
            selectedItem = nil
            NotificationCenter.default.post(name: .init("ClearClipboardSelection"), object: nil)
        }

        // Remove from published array so SwiftUI drops views
        items.removeAll { idsToDelete.contains($0.id) }

        // Defer context deletion to next run loop
        DispatchQueue.main.async { [weak self] in
            for item in itemsToDelete {
                modelContext.delete(item)
            }
            do {
                try modelContext.save()
                self?.refreshItemCounts()
            } catch {
                modelContext.rollback()
                ErrorLogger.shared.log("Failed to delete items", category: "SwiftData", error: error)
                self?.fetchItems(reset: true)
            }
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
        case .image(let imageData):
            addOrUpdateImageItem(imageData: imageData)
        case .file(let url, let uti, let data):
            addOrUpdateFileItem(url: url, uti: uti, data: data)
        case .combined(let content, let imageData):
            addOrUpdateCombinedItem(content: content, imageData: imageData)
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
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to save text item", category: "SwiftData", error: error)
        }
    }

    private func addOrUpdateImageItem(imageData: Data) {
        guard let modelContext = _modelContext else { return }

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
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to save image item", category: "SwiftData", error: error)
        }
    }

    private func addOrUpdateCombinedItem(content: String, imageData: Data) {
        guard let modelContext = _modelContext else { return }

        let tempItem = CBItem(
            timestamp: Date(),
            content: content,
            imageData: imageData,
            itemType: .combined
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
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to save combined item", category: "SwiftData", error: error)
        }
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
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to save file item", category: "SwiftData", error: error)
        }
    }

    func copyItem(_ item: CBItem) {
        copyAndUpdateItem(item)
    }

    /// Puts the item on the pasteboard and moves it to the top of the history.
    /// Returns false when the item had nothing to copy.
    @discardableResult
    func copyAndUpdateItem(_ item: CBItem) -> Bool {
        guard clipboardManager.copyItemToClipboard(item) else { return false }

        markItemAccessed(item)
        guard let modelContext = _modelContext else { return true }
        item.timestamp = Date()

        do {
            try modelContext.save()
            fetchItems(reset: true)
        } catch {
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to update item timestamp", category: "SwiftData", error: error)
        }
        return true
    }

    func saveItemToFile(_ item: CBItem) {
        clipboardManager.saveItemToFile(item)
    }

    func openInPreview(item: CBItem) {
        Task {
            do {
                try await openInPreviewAsync(item: item)
            } catch {
                ErrorLogger.shared.log("Failed to open item in Preview", category: "ExternalOpen", error: error)
            }
        }
    }

    private func openInPreviewAsync(item: CBItem) async throws {
        switch item.itemType {
        case .image, .combined:
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
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to update item content", category: "SwiftData", error: error)
        }
    }

    func toggleFavorite(_ item: CBItem) {
        guard let modelContext = _modelContext else { return }

        item.isFavorite.toggle()

        if item.isFavorite {
            // Fetch all favorites from database to get accurate max order index
            let descriptor = FetchDescriptor<CBItem>(
                predicate: #Predicate { $0.isFavorite }
            )

            do {
                let allFavorites = try modelContext.fetch(descriptor)
                let maxOrderIndex = allFavorites.map { $0.orderIndex }.max() ?? -1
                item.orderIndex = maxOrderIndex + 1
            } catch {
                ErrorLogger.shared.log("Failed to fetch favorites for order index", category: "SwiftData", error: error)
                // Fallback to in-memory items if fetch fails
                let maxOrderIndex = items.filter { $0.isFavorite }.map { $0.orderIndex }.max() ?? -1
                item.orderIndex = maxOrderIndex + 1
            }
        } else {
            item.orderIndex = 0
        }

        do {
            try modelContext.save()
            fetchItems(reset: true)
        } catch {
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to toggle favorite", category: "SwiftData", error: error)
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
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to update favorite order", category: "SwiftData", error: error)
        }
    }

    var favoriteItems: [CBItem] {
        guard let modelContext = _modelContext else { return [] }

        let descriptor = FetchDescriptor<CBItem>(
            predicate: #Predicate { $0.isFavorite },
            sortBy: [SortDescriptor(\.orderIndex, order: .forward)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            ErrorLogger.shared.log("Failed to fetch favorite items", category: "SwiftData", error: error)
            return []
        }
    }

    var recentItems: [CBItem] {
        return items.sorted { $0.timestamp > $1.timestamp }
    }

    func deleteAllItems() {
        guard let modelContext = _modelContext else { return }

        // 1. Clear all UI state synchronously so SwiftUI stops referencing items
        selectedItem = nil
        items = []
        NotificationCenter.default.post(name: .init("ClearClipboardSelection"), object: nil)
        // Tell PinManager — `object: nil` means "all items wiped".
        NotificationCenter.default.post(name: .clipboardItemDeleted, object: nil)

        // 2. Defer actual context deletion to the NEXT run loop iteration.
        //    This gives SwiftUI a full layout pass to drop views that reference
        //    CBItem objects. Deleting in the same pass causes "backing data
        //    detached" crashes because views still hold stale references.
        DispatchQueue.main.async { [weak self] in
            do {
                let allItems = try modelContext.fetch(FetchDescriptor<CBItem>())
                for item in allItems {
                    modelContext.delete(item)
                }
                try modelContext.save()
                self?.refreshItemCounts()
            } catch {
                modelContext.rollback()
                ErrorLogger.shared.log("Failed to delete all items", category: "SwiftData", error: error)
                self?.fetchItems(reset: true)
            }
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
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to clear all favorites", category: "SwiftData", error: error)
        }
    }

    func loadMoreItems() {
        fetchItems()
    }

    func refreshItemCounts() {
        guard let modelContext = _modelContext else { return }
        do {
            let nonFavDescriptor = FetchDescriptor<CBItem>(
                predicate: #Predicate { !$0.isFavorite }
            )
            let favDescriptor = FetchDescriptor<CBItem>(
                predicate: #Predicate { $0.isFavorite }
            )
            totalItemCount = try modelContext.fetchCount(nonFavDescriptor)
            favoriteItemCount = try modelContext.fetchCount(favDescriptor)
        } catch {
            ErrorLogger.shared.log("Failed to fetch item count", category: "SwiftData", error: error)
        }
    }

    func performManualCleanup() {
        guard let settingsManager = settingsManager else { return }

        // Always enforce maxItemsToKeep during manual cleanup, regardless of toggle
        performItemCountCleanupCore(maxItems: settingsManager.maxItemsToKeep)

        // Always run memory cleanup during manual cleanup, regardless of toggle
        performMemoryCleanupCore()

        // Reset in-memory items to only the most recent batch
        fetchItems(limit: initialBatchSize, reset: true)
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

        performMemoryCleanupCore()
    }

    private func performMemoryCleanupCore() {
        guard let settingsManager = settingsManager else { return }

        let now = Date()
        let maxInactiveTime = TimeInterval(settingsManager.maxInactiveTime * 60)
        var itemsToCleanup: [CBItem] = []

        for item in items {
            if item.isFavorite {
                continue
            }

            if let lastAccess = lastAccessTimes[item.persistentModelID],
               now.timeIntervalSince(lastAccess) > maxInactiveTime {
                itemsToCleanup.append(item)
            }
        }

        for item in itemsToCleanup {
            cleanupItemMemory(item)
        }

        let cutoffTime = now.addingTimeInterval(-maxInactiveTime)
        lastAccessTimes = lastAccessTimes.filter { $1 > cutoffTime }

        ErrorLogger.shared.debug("Memory cleanup: released \(itemsToCleanup.count) inactive items (favorites preserved)", category: "Memory")
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
        guard let settingsManager = settingsManager,
            settingsManager.enableAutoCleanup
        else { return }

        performItemCountCleanupCore(maxItems: settingsManager.maxItemsToKeep)
    }

    private func performItemCountCleanupCore(maxItems: Int) {
        guard let modelContext = _modelContext else { return }

        // The cap applies only to non-favorites. Favorites sit outside the
        // limit and are never auto-deleted.
        let nonFavPredicate = #Predicate<CBItem> { !$0.isFavorite }
        let countDescriptor = FetchDescriptor<CBItem>(predicate: nonFavPredicate)
        do {
            let nonFavCount = try modelContext.fetchCount(countDescriptor)

            guard nonFavCount > maxItems else { return }

            let itemsToDelete = nonFavCount - maxItems
            var oldItemsDescriptor = FetchDescriptor<CBItem>(
                predicate: nonFavPredicate,
                sortBy: [SortDescriptor(\.timestamp, order: .forward)]
            )
            oldItemsDescriptor.fetchLimit = itemsToDelete

            let nonFavoriteOldItems = try modelContext.fetch(oldItemsDescriptor)

            guard !nonFavoriteOldItems.isEmpty else { return }

            // Clear UI references BEFORE detaching backing data so SwiftUI
            // doesn't render views holding the to-be-detached items. This
            // prevents "backing data detached from context" crashes when a
            // currently-viewed item is auto-cleaned.
            let idsToDelete = Set(nonFavoriteOldItems.map { $0.id })

            if let sel = selectedItem, idsToDelete.contains(sel.id) {
                selectedItem = nil
                NotificationCenter.default.post(name: .init("ClearClipboardSelection"), object: nil)
            }

            for item in nonFavoriteOldItems {
                NotificationCenter.default.post(
                    name: .clipboardItemDeleted, object: item.persistentModelID
                )
            }

            items.removeAll { idsToDelete.contains($0.id) }

            // Defer context deletion to the next run loop iteration so SwiftUI
            // gets a full layout pass to drop views before the backing data
            // is invalidated (mirrors deleteItem/deleteAllItems).
            let deletedCount = nonFavoriteOldItems.count
            DispatchQueue.main.async { [weak self] in
                for item in nonFavoriteOldItems {
                    modelContext.delete(item)
                }
                do {
                    try modelContext.save()
                    self?.fetchItems(reset: true)
                    ErrorLogger.shared.debug(
                        "Cleanup: removed \(deletedCount) old items, keeping under \(maxItems) limit",
                        category: "Cleanup")
                } catch {
                    modelContext.rollback()
                    ErrorLogger.shared.log("Failed to save item count cleanup", category: "SwiftData", error: error)
                    self?.fetchItems(reset: true)
                }
            }
        } catch {
            ErrorLogger.shared.log("Failed to perform item count cleanup", category: "SwiftData", error: error)
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
        // Use a unique name to avoid conflicts
        let tempFileName = "clipboard_file_\(UUID().uuidString)_\(fileName)"
        let tempFile = tempDir.appendingPathComponent(tempFileName)

        try fileData.write(to: tempFile)
        NSWorkspace.shared.open(tempFile)

        // Clean up after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 60.0) {
            try? FileManager.default.removeItem(at: tempFile)
        }
    }

    func openInPreview(_ item: CBItem) {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL: URL

        if let image = item.image ?? item.filePreviewImage {
            // It's an image (or file with image preview)
            let fileName = "clipboard_image_\(UUID().uuidString).png"
            fileURL = tempDir.appendingPathComponent(fileName)

            guard let tiffData = image.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
                return
            }

            try? pngData.write(to: fileURL)
        } else if item.itemType == .file, let data = item.fileData, let name = item.fileName {
            // It's a file
            let tempName = "clipboard_file_\(UUID().uuidString)_\(name)"
            fileURL = tempDir.appendingPathComponent(tempName)
            try? data.write(to: fileURL)
        } else {
            return
        }

        NSWorkspace.shared.open(fileURL)

        DispatchQueue.main.asyncAfter(deadline: .now() + 60.0) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func openInTextEdit(_ item: CBItem) {
        guard let text = item.content, !text.isEmpty else { return }

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "clipboard_text_\(UUID().uuidString).txt"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            
            // Try to open specifically with TextEdit, fallback to default for .txt
            if let textEditURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open([fileURL], withApplicationAt: textEditURL, configuration: config)
            } else {
                NSWorkspace.shared.open(fileURL)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 60.0) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            ErrorLogger.shared.log("Failed to open text in TextEdit", category: "ExternalOpen", error: error)
        }
    }

    deinit {
        memoryCleanupTimer?.invalidate()
    }
}
