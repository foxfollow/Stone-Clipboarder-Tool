//
//  CBViewModel.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import AppKit
import Combine
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
    /// Favorites in their user-defined order. Cached because views read it on
    /// every render and hotkeys on every press; reloaded with `items`.
    @Published private(set) var favoriteItems: [CBItem] = []

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

    /// Compiled regex rules and their stamp; rebuilt when the categories
    /// change. Items whose `classificationStamp` differs get classified again.
    private(set) var classifierRuleset = ContentClassifier.Ruleset.empty
    private var categoriesObserver: AnyCancellable?
    private var autoOCRObserver: AnyCancellable?
    private var reclassifyTask: Task<Void, Never>?
    private var reclassifyGeneration = 0

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

        // Only a change to the regex rules changes the stamp; toggles, icons
        // and colors don't trigger a rescan.
        categoriesObserver = manager.$itemCategories
            .map { categories in categories.compactMap(\.regexRule) }
            .removeDuplicates()
            .combineLatest(manager.$analyzeImages.removeDuplicates())
            .sink { [weak self] rules, analyzeImages in
                MainActor.assumeIsolated {
                    self?.updateClassifierRules(rules, analyzeImages: analyzeImages)
                }
            }

        // Turning automatic OCR off also cancels what it queued.
        autoOCRObserver = manager.$recognizeTextInNewImages
            .removeDuplicates()
            .dropFirst()
            .filter { !$0 }
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.cancelTextRecognition(state: CBItem.TextRecognition.pending)
                }
            }
    }

    /// Swaps the rules and, when the stamp changed, rescans the history.
    func updateClassifierRules(_ rules: [ContentClassifier.RegexRule], analyzeImages: Bool = true) {
        let ruleset = ContentClassifier.Ruleset(rules: rules, analyzeImages: analyzeImages)
        guard ruleset.stamp != classifierRuleset.stamp || analyzeImages != classifierRuleset.analyzeImages else {
            return
        }
        classifierRuleset = ruleset
        reclassifyIfNeeded()
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
        reloadFavorites()
        refreshItemCounts()
    }

    private func reloadFavorites() {
        guard let modelContext = _modelContext else { return }
        let descriptor = FetchDescriptor<CBItem>(
            predicate: #Predicate { $0.isFavorite },
            sortBy: [SortDescriptor(\.orderIndex, order: .forward)]
        )
        do {
            favoriteItems = try modelContext.fetch(descriptor)
        } catch {
            ErrorLogger.shared.log("Failed to fetch favorite items", category: "SwiftData", error: error)
            favoriteItems = []
        }
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

    /// Bumped with every `.clipboardItemDeleted`, so a search suspended
    /// between pages can tell its matches may include a deleted item.
    private var deletionGeneration = 0

    /// Posts `.clipboardItemDeleted` (`nil`: everything). The context
    /// deletion must follow on a later main-queue turn.
    private func announceDeletion(of id: PersistentIdentifier?) {
        deletionGeneration += 1
        NotificationCenter.default.post(name: .clipboardItemDeleted, object: id)
    }

    func deleteItem(_ item: CBItem) {
        guard let modelContext = _modelContext else { return }

        // Clear selection if this item is selected
        if selectedItem?.id == item.id {
            selectedItem = nil
            NotificationCenter.default.post(name: .clearClipboardSelection, object: nil)
        }

        // Tell PinManager so any open pin for this item closes.
        announceDeletion(of: item.persistentModelID)

        // Remove from published arrays so SwiftUI drops the view
        items.removeAll { $0.id == item.id }
        favoriteItems.removeAll { $0.id == item.id }

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
            announceDeletion(of: item.persistentModelID)
        }

        // Clear selection if deleted item is selected
        if let sel = selectedItem, idsToDelete.contains(sel.id) {
            selectedItem = nil
            NotificationCenter.default.post(name: .clearClipboardSelection, object: nil)
        }

        // Remove from published arrays so SwiftUI drops views
        items.removeAll { idsToDelete.contains($0.id) }
        favoriteItems.removeAll { idsToDelete.contains($0.id) }

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
        clipboardManager.onClipboardChange = { [weak self] content, source in
            Task { @MainActor in
                self?.handleClipboardChange(content, source: source)
            }
        }
    }

    func startClipboardMonitoring() {
        clipboardManager.startMonitoring()
    }

    private func handleClipboardChange(_ clipboardContent: ClipboardContent, source: CaptureSource?) {
        switch clipboardContent {
        case .text(let content):
            addOrUpdateTextItem(content: content, source: source)
        case .image(let imageData):
            addOrUpdateImageItem(imageData: imageData, source: source)
        case .file(let url, let uti, let data):
            addOrUpdateFileItem(url: url, uti: uti, data: data, source: source)
        case .combined(let content, let imageData):
            addOrUpdateCombinedItem(content: content, imageData: imageData, source: source)
        }
    }

    func addTextItem(content: String, source: CaptureSource? = nil) {
        addOrUpdateTextItem(content: content, source: source)
    }

    private func addOrUpdateTextItem(content: String, source: CaptureSource?) {
        let key = CBItem.ContentKey(type: .text, content: content)
        insertOrBump(key, source: source, errorMessage: "Failed to save text item") {
            CBItem(timestamp: Date(), content: content, itemType: .text)
        }
    }

    private func addOrUpdateImageItem(imageData: Data, source: CaptureSource?) {
        let key = CBItem.ContentKey(type: .image, imageData: imageData)
        insertOrBump(key, source: source, errorMessage: "Failed to save image item") {
            CBItem(timestamp: Date(), imageData: imageData, itemType: .image)
        }
    }

    private func addOrUpdateCombinedItem(content: String, imageData: Data, source: CaptureSource?) {
        let key = CBItem.ContentKey(type: .combined, content: content, imageData: imageData)
        insertOrBump(key, source: source, errorMessage: "Failed to save combined item") {
            CBItem(timestamp: Date(), content: content, imageData: imageData, itemType: .combined)
        }
    }

    private func addOrUpdateFileItem(url: URL, uti: String?, data: Data?, source: CaptureSource?) {
        let name = url.lastPathComponent
        let key = CBItem.ContentKey(type: .file, fileData: data, fileName: name)
        insertOrBump(key, source: source, errorMessage: "Failed to save file item") {
            CBItem(timestamp: Date(), fileData: data, fileName: name, fileUTI: uti, itemType: .file)
        }
    }

    /// Moves an existing identical item to the top, or inserts a new one.
    /// `makeItem` runs only for new content: building a CBItem decodes the
    /// image and renders its thumbnail. A new item is classified right away;
    /// either way the item remembers the latest source app.
    private func insertOrBump(
        _ key: CBItem.ContentKey, source: CaptureSource?, errorMessage: String, makeItem: () -> CBItem
    ) {
        guard let modelContext = _modelContext else { return }

        let item: CBItem
        if let existing = existingItem(matching: key) {
            existing.timestamp = Date()
            item = existing
        } else {
            item = makeItem()
            item.classify(with: classifierRuleset)
            if item.hasAnalyzableImage {
                // OCR runs once, for new images only (unless asked for all).
                if settingsManager?.recognizeTextInNewImages ?? true {
                    item.textRecognitionState = CBItem.TextRecognition.pending
                }
                if item.needsVisualPass(classifierRuleset) || item.wantsTextRecognition {
                    // Text is classified; the image waits for the background pass.
                    item.classificationStamp = 0
                }
            }
            modelContext.insert(item)
        }
        if let source {
            item.sourceAppBundleID = source.bundleID
            item.sourceAppName = source.name
        }

        do {
            try modelContext.save()
            fetchItems(reset: true)
            performCleanupIfNeeded()
            if item.classificationStamp != classifierRuleset.stamp && reclassifyTask == nil {
                reclassifyIfNeeded()
            }
        } catch {
            modelContext.rollback()
            ErrorLogger.shared.log(errorMessage, category: "SwiftData", error: error)
        }
    }

    /// Image candidates compared per lookup. Bounds the external data
    /// loaded: many screenshots share one size, no other inline column tells
    /// them apart, and each comparison reads an image blob. An identical
    /// image older than the newest 25 of its size is saved again.
    private let imageCandidateLimit = 25

    /// An item with the same content anywhere in the history, not only among
    /// the loaded rows. Inline columns (text preview; file name and byte
    /// size; image size) select the candidates, newest first, and only
    /// those are compared in full. Text and file candidates are almost
    /// always the item itself; image candidates are capped.
    func existingItem(matching key: CBItem.ContentKey) -> CBItem? {
        guard let modelContext = _modelContext else { return nil }

        let newestFirst = [SortDescriptor(\CBItem.timestamp, order: .reverse)]
        var descriptor: FetchDescriptor<CBItem>
        switch key.type {
        // Predicate values stay optional to match the optional columns.
        case .text, .combined:
            let preview = key.preview
            guard preview != nil else { return nil }
            descriptor = FetchDescriptor(predicate: #Predicate { $0.contentPreview == preview }, sortBy: newestFirst)
        case .image:
            let size = key.imageSize
            guard size != nil else { return nil }
            descriptor = FetchDescriptor(predicate: #Predicate { $0.imageSize == size }, sortBy: newestFirst)
            descriptor.fetchLimit = imageCandidateLimit
        case .file:
            let name = key.fileName
            guard name != nil, let byteCount = key.fileData.map({ Int64($0.count) }) else { return nil }
            descriptor = FetchDescriptor(
                predicate: #Predicate { $0.fileName == name && $0.fileSize == byteCount }, sortBy: newestFirst)
        }

        do {
            return try modelContext.fetch(descriptor).first { $0.hasSameContent(as: key) }
        } catch {
            ErrorLogger.shared.log("Failed to look up a duplicate item", category: "SwiftData", error: error)
            return nil
        }
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

    /// Sets or clears (`nil`, empty or whitespace) the item's title. Doesn't
    /// touch the timestamp: naming an item isn't using it.
    func setTitle(_ item: CBItem, to title: String?) {
        guard let modelContext = _modelContext else { return }

        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTitle = (trimmed?.isEmpty ?? true) ? nil : trimmed
        guard item.title != newTitle else { return }
        item.title = newTitle

        do {
            try modelContext.save()
            fetchItems(reset: true)
        } catch {
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to update item title", category: "SwiftData", error: error)
        }
    }

    /// Moves a favorite `offset` places in the favorites order (clamped to
    /// the ends), then numbers every favorite 0…n-1 so `orderIndex` stays
    /// gap-free. ⌃⇧1…0 and the Favorites lists follow this order.
    func moveFavorite(_ item: CBItem, by offset: Int) {
        guard let modelContext = _modelContext, item.isFavorite, offset != 0 else { return }

        var ordered = favoriteItems
        guard let from = ordered.firstIndex(where: { $0.persistentModelID == item.persistentModelID })
        else { return }
        let to = min(max(from + offset, 0), ordered.count - 1)
        guard to != from else { return }

        ordered.remove(at: from)
        ordered.insert(item, at: to)
        for (index, favorite) in ordered.enumerated() where favorite.orderIndex != index {
            favorite.orderIndex = index
        }

        do {
            try modelContext.save()
            fetchItems(reset: true)
        } catch {
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to reorder favorites", category: "SwiftData", error: error)
        }
    }

    /// Newest first. `items` is kept in that order by every fetch and change.
    var recentItems: [CBItem] {
        items
    }

    func deleteAllItems() {
        guard let modelContext = _modelContext else { return }

        // 1. Clear all UI state synchronously so SwiftUI stops referencing items
        selectedItem = nil
        items = []
        favoriteItems = []
        NotificationCenter.default.post(name: .clearClipboardSelection, object: nil)
        // Tell PinManager — `object: nil` means "all items wiped".
        announceDeletion(of: nil)

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

    func loadMoreItems() {
        fetchItems()
    }

    // MARK: - Read-only queries (Quick Picker, search)

    private static let newestFirst = [SortDescriptor(\CBItem.timestamp, order: .reverse)]

    /// A newest-first slice of the whole history.
    func historyPage(offset: Int, limit: Int) -> [CBItem] {
        guard let modelContext = _modelContext else { return [] }
        var descriptor = FetchDescriptor<CBItem>(sortBy: Self.newestFirst)
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            ErrorLogger.shared.log("Failed to fetch a history page", category: "SwiftData", error: error)
            return []
        }
    }

    /// Every item of the given types, newest first. Filtered in memory:
    /// SwiftData predicates can't reliably test the enum-typed `itemType`.
    func items(ofTypes types: Set<CBItemType>) -> [CBItem] {
        guard let modelContext = _modelContext else { return [] }
        do {
            return try modelContext.fetch(FetchDescriptor<CBItem>(sortBy: Self.newestFirst))
                .filter { types.contains($0.itemType) }
        } catch {
            ErrorLogger.shared.log("Failed to fetch items by type", category: "SwiftData", error: error)
            return []
        }
    }

    private static let searchPageSize = 200

    /// Items matching `query` anywhere in the history (optionally only the
    /// given types), newest first, at most `limit`. Scans the store in pages
    /// until enough matches are found, so older items are found too. Pauses
    /// between pages so a long scan doesn't freeze the UI; returns `[]` when
    /// the calling task is cancelled.
    func searchItems(matching query: String, types: Set<CBItemType>? = nil, limit: Int = 300) async -> [CBItem] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let includingImageText = searchesImageText
        return await searchItems(types: types, limit: limit) {
            $0.matchesSearch(query, includingImageText: includingImageText)
        }
    }

    /// Items passing `filter` (chip, `is:`/`app:`/`lang:` tokens, free text)
    /// anywhere in the history, newest first, at most `limit`.
    func searchItems(filter: ItemFilter, types: Set<CBItemType>? = nil, limit: Int = 300) async -> [CBItem] {
        guard !filter.isEmpty else { return [] }
        return await searchItems(types: types, limit: limit, where: filter.matches)
    }

    private func searchItems(
        types: Set<CBItemType>?, limit: Int, where isMatch: @escaping (CBItem) -> Bool
    ) async -> [CBItem] {
        guard limit > 0 else { return [] }

        while true {
            // A deletion announced earlier has its context deletion queued
            // already; the pause lets it run before the scan.
            guard await pauseBetweenPages() else { return [] }
            let generation = deletionGeneration
            guard let results = await scanHistory(types: types, limit: limit, where: isMatch) else { return [] }
            if generation == deletionGeneration { return results }
            // An item was announced deleted during a pause and may be among
            // the matches: scan again once its deletion has run.
        }
    }

    /// nil when cancelled.
    private func scanHistory(
        types: Set<CBItemType>?, limit: Int, where isMatch: (CBItem) -> Bool
    ) async -> [CBItem]? {
        let pageSize = Self.searchPageSize
        var results: [CBItem] = []
        // Items inserted during a pause shift the offsets; skip repeats.
        var seen = Set<PersistentIdentifier>()
        var offset = 0
        while results.count < limit {
            let page = historyPage(offset: offset, limit: pageSize)
            for item in page where types?.contains(item.itemType) ?? true {
                guard seen.insert(item.persistentModelID).inserted else { continue }
                if isMatch(item) {
                    results.append(item)
                    if results.count == limit { break }
                }
            }
            if page.count < pageSize || results.count == limit { break }
            offset += pageSize
            guard await pauseBetweenPages() else { return nil }
        }
        return results
    }

    /// Gives the run loop a turn (input, drawing, queued deletions). False
    /// when the task is cancelled.
    private func pauseBetweenPages() async -> Bool {
        do {
            try await Task.sleep(for: .milliseconds(1))
            return true
        } catch {
            return false
        }
    }

    struct ItemTypeCounts: Equatable {
        /// Text and text + image items.
        var text = 0
        /// Images and text + image items.
        var images = 0
        var files = 0
    }

    private var cachedTypeCounts: ItemTypeCounts?

    /// Per-type counts for the Quick Picker tabs. Needs a full scan (no
    /// predicate on `itemType`), so it's cached until the history changes.
    func itemTypeCounts() -> ItemTypeCounts {
        if let cachedTypeCounts { return cachedTypeCounts }
        guard let modelContext = _modelContext else { return ItemTypeCounts() }

        var counts = ItemTypeCounts()
        var facets: [CBItemType: FacetCounts] = [:]
        do {
            for item in try modelContext.fetch(FetchDescriptor<CBItem>()) {
                facets[item.itemType, default: FacetCounts()].add(item)
                switch item.itemType {
                case .text: counts.text += 1
                case .image: counts.images += 1
                case .file: counts.files += 1
                case .combined:
                    counts.text += 1
                    counts.images += 1
                }
            }
        } catch {
            ErrorLogger.shared.log("Failed to count items by type", category: "SwiftData", error: error)
            return counts
        }
        cachedTypeCounts = counts
        cachedFacets = facets
        return counts
    }

    private var cachedFacets: [CBItemType: FacetCounts]?

    /// Changes whenever the counts may have: the Quick Picker reloads its
    /// chips on it (a capture or rescan while it's open).
    @Published private(set) var countsRevision = 0

    /// "Find images by the text in them".
    private var searchesImageText: Bool { settingsManager?.searchImageText ?? true }

    /// Category, language and source-app counts over the given types (nil =
    /// all), for the Quick Picker's chips. Shares the cached full scan with
    /// `itemTypeCounts()`.
    func facetCounts(ofTypes types: Set<CBItemType>?) -> FacetCounts {
        if cachedFacets == nil { cachedTypeCounts = nil; _ = itemTypeCounts() }
        guard let cachedFacets else { return FacetCounts() }
        return cachedFacets
            .filter { types?.contains($0.key) ?? true }
            .values
            .reduce(FacetCounts(), +)
    }

    // MARK: - Classification

    /// Classifies, in the background, every item stamped with other rules
    /// (or none: items from before categories). Restarts when called again.
    func reclassifyIfNeeded() {
        reclassifyTask?.cancel()
        reclassifyGeneration += 1
        let generation = reclassifyGeneration
        reclassifyTask = Task { [weak self] in
            await self?.reclassifyStaleItems()
            // A newer pass may have replaced this one meanwhile.
            if self?.reclassifyGeneration == generation {
                self?.reclassifyTask = nil
            }
        }
    }

    /// Pages of 100 items that are out of date: stamped with other rules,
    /// waiting for OCR, or not at `CBItem.visualTarget` (the visual pass
    /// switched on, off, or changed version). Text-like items are
    /// classified on the main actor in small batches with a run-loop turn
    /// between them. Images that need Vision go to `ImageClassifier` off
    /// the main thread, a few at a time, read through a throwaway
    /// background context so their bytes don't stay loaded in the main
    /// one. Every item leaves the pass up to date (failed Vision requests
    /// are marked for the next launch), so the pass always ends. Returns
    /// how many items were classified.
    @discardableResult
    func reclassifyStaleItems() async -> Int {
        guard let modelContext = _modelContext else { return 0 }
        let ruleset = classifierRuleset
        let stamp = ruleset.stamp
        let pending = CBItem.TextRecognition.pending
        let queued = CBItem.TextRecognition.queued
        let visualTarget = CBItem.visualTarget(for: ruleset)
        // Failed images wait for the next launch while the pass is on; when
        // it's off they're cleared like the rest.
        let failedVisual = ruleset.analyzeImages ? -ImageClassifier.visualVersion : Int.min
        var classified = 0
        updatePendingTextRecognitionCount()
        defer { updatePendingTextRecognitionCount() }

        func needsVision(_ item: CBItem) -> Bool {
            item.needsVisualPass(ruleset) || (item.hasAnalyzableImage && item.wantsTextRecognition)
        }
        /// Not deleted, here or (saved) in another turn.
        func isAlive(_ item: CBItem) -> Bool { item.modelContext != nil && !item.isDeleted }

        pages: while !Task.isCancelled {
            var descriptor = FetchDescriptor<CBItem>(predicate: #Predicate {
                $0.classificationStamp != stamp || $0.textRecognitionState == pending
                    || $0.textRecognitionState == queued
                    || ($0.visualAnalysisVersion != visualTarget && $0.visualAnalysisVersion != failedVisual)
            })
            descriptor.fetchLimit = Self.reclassifyPageSize
            let page: [CBItem]
            do {
                page = try modelContext.fetch(descriptor)
            } catch {
                ErrorLogger.shared.log("Failed to fetch items to classify", category: "SwiftData", error: error)
                break
            }
            guard !page.isEmpty else { break }

            if await !classifyWithoutVision(page.filter { !needsVision($0) }, ruleset: ruleset, in: modelContext) {
                break
            }
            classified += page.count

            var images = page.filter(needsVision)
            while !images.isEmpty {
                let chunk = Array(images.prefix(Self.imageChunkSize))
                images.removeFirst(chunk.count)
                // State may have changed during a pause (Stop, the user's OCR).
                let live = chunk.filter { isAlive($0) && needsVision($0) }
                let settled = chunk.filter { isAlive($0) && !needsVision($0) }
                settled.forEach { $0.classify(with: ruleset) }
                let requests = live.map {
                    ImageRequest(
                        id: $0.persistentModelID, analyzeVisual: $0.needsVisualPass(ruleset),
                        recognizeText: $0.wantsTextRecognition)
                }
                let results = requests.isEmpty
                    ? [:] : await Self.analyzeImages(requests, container: modelContext.container)
                guard !Task.isCancelled else { break pages }
                for (item, request) in zip(live, requests) where isAlive(item) {
                    var result = results[request.id]
                        ?? .failed(analyzeVisual: request.analyzeVisual, recognizeText: request.recognizeText)
                    if request.recognizeText && !item.wantsTextRecognition {
                        // Stopped, or the user's OCR came first: keep theirs.
                        result.recognizedText = nil
                        result.foundText = false
                        result.failedText = false
                    }
                    item.classify(with: ruleset, image: result)
                }
                guard saveCategories(in: modelContext) else { break pages }
                updatePendingTextRecognitionCount()
            }
            guard await pauseBetweenPages() else { break }
        }

        if classified > 0 {
            fetchItems(reset: true)
        }
        return classified
    }

    /// Classifies `items` 20 at a time with a run-loop turn between
    /// batches. False when saving failed or the task was cancelled.
    private func classifyWithoutVision(
        _ items: [CBItem], ruleset: ContentClassifier.Ruleset, in modelContext: ModelContext
    ) async -> Bool {
        var start = 0
        while start < items.count {
            let batch = items[start..<min(start + Self.textBatchSize, items.count)]
            start += batch.count
            for item in batch where item.modelContext != nil && !item.isDeleted {
                if item.classificationStamp == ruleset.stamp && !item.hasAnalyzableImage && !item.wantsTextRecognition {
                    // Only the image switch changed: no need to read the text again.
                    item.visualAnalysisVersion = CBItem.visualTarget(for: ruleset)
                } else {
                    item.classify(with: ruleset)
                }
            }
            guard saveCategories(in: modelContext) else { return false }
            guard await pauseBetweenPages() else { return false }
        }
        return true
    }

    private static let reclassifyPageSize = 100
    private static let imageChunkSize = 4
    /// Text-like items classified per main-actor turn during a rescan.
    private static let textBatchSize = 20

    private func saveCategories(in modelContext: ModelContext) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to save item categories", category: "SwiftData", error: error)
            return false
        }
    }

    private struct ImageRequest {
        let id: PersistentIdentifier
        let analyzeVisual: Bool
        let recognizeText: Bool
    }

    /// Runs `ImageClassifier` on a utility-priority thread with its own
    /// context, so the image bytes are released when it ends.
    nonisolated private static func analyzeImages(
        _ requests: [ImageRequest], container: ModelContainer
    ) async -> [PersistentIdentifier: ImageClassifier.Result] {
        await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            var results: [PersistentIdentifier: ImageClassifier.Result] = [:]
            for request in requests {
                let id = request.id
                let descriptor = FetchDescriptor<CBItem>(predicate: #Predicate { $0.persistentModelID == id })
                // A failed fetch is left out (retried later); an item
                // without image bytes is unreadable for good.
                guard let item = try? context.fetch(descriptor).first else { continue }
                guard let data = item.analyzableImageData else {
                    results[id] = .unreadable(analyzeVisual: request.analyzeVisual, recognizeText: request.recognizeText)
                    continue
                }
                results[id] = ImageClassifier.classify(
                    data, analyzeVisual: request.analyzeVisual, recognizeText: request.recognizeText)
            }
            return results
        }.value
    }

    // MARK: - Text recognition

    /// Images "Recognize Text in All Images" queued and Vision hasn't read
    /// yet: the progress Settings shows, which its Stop cancels. New images
    /// waiting for automatic OCR aren't counted; they're read right away.
    @Published private(set) var pendingTextRecognitionCount = 0

    private func updatePendingTextRecognitionCount() {
        guard let modelContext = _modelContext else { return }
        let queued = CBItem.TextRecognition.queued
        let count = (try? modelContext.fetchCount(
            FetchDescriptor<CBItem>(predicate: #Predicate { $0.textRecognitionState == queued }))) ?? 0
        if count != pendingTextRecognitionCount { pendingTextRecognitionCount = count }
    }

    /// Images OCR never ran on, for "Recognize Text in All Images…".
    func imagesWithoutTextRecognition() -> Int {
        unrecognizedImages().count
    }

    private func unrecognizedImages() -> [CBItem] {
        guard let modelContext = _modelContext else { return [] }
        let notRequested = CBItem.TextRecognition.notRequested
        // Filtered in memory: `itemType` can't be tested in a predicate, and
        // `imageSize` is nil on old or undecodable images. Only inline
        // columns are read, no content.
        let descriptor = FetchDescriptor<CBItem>(predicate: #Predicate { $0.textRecognitionState == notRequested })
        do {
            return try modelContext.fetch(descriptor).filter(\.hasAnalyzableImage)
        } catch {
            ErrorLogger.shared.log("Failed to count images for OCR", category: "SwiftData", error: error)
            return []
        }
    }

    /// Queues OCR for every image it never ran on; the background pass does
    /// the work, a few images at a time.
    func recognizeTextInAllImages() {
        guard let modelContext = _modelContext else { return }
        let images = unrecognizedImages()
        guard !images.isEmpty else { return }
        images.forEach { $0.textRecognitionState = CBItem.TextRecognition.queued }
        guard saveCategories(in: modelContext) else { return }
        fetchItems(reset: true)
        updatePendingTextRecognitionCount()
        if reclassifyTask == nil { reclassifyIfNeeded() }
    }

    /// Stops a "Recognize Text in All Images" run: what it queued and hasn't
    /// read goes back to not requested.
    func stopTextRecognition() {
        cancelTextRecognition(state: CBItem.TextRecognition.queued)
    }

    /// Puts images in `state` (queued, or pending when automatic OCR is
    /// switched off) back to not requested.
    private func cancelTextRecognition(state: Int) {
        guard let modelContext = _modelContext else { return }
        do {
            let descriptor = FetchDescriptor<CBItem>(predicate: #Predicate { $0.textRecognitionState == state })
            for item in try modelContext.fetch(descriptor) {
                item.textRecognitionState = CBItem.TextRecognition.notRequested
            }
            try modelContext.save()
            fetchItems(reset: true)
        } catch {
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to stop text recognition", category: "SwiftData", error: error)
        }
        updatePendingTextRecognitionCount()
    }

    /// Failed Vision requests get another try: called once at launch,
    /// before the first rescan.
    func retryFailedImageAnalysis() {
        guard let modelContext = _modelContext else { return }
        let failed = -ImageClassifier.visualVersion
        do {
            let descriptor = FetchDescriptor<CBItem>(predicate: #Predicate { $0.visualAnalysisVersion == failed })
            let items = try modelContext.fetch(descriptor)
            guard !items.isEmpty else { return }
            items.forEach { $0.visualAnalysisVersion = 0 }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to reset image analysis", category: "SwiftData", error: error)
        }
    }

    /// Keeps text the user's OCR (⌥⏎, "Extract Text") found in an image on
    /// that image, so search finds it, and adds the categories the text
    /// brings (Text in Image, Link, …). Ignores items deleted meanwhile.
    func rememberRecognizedText(_ text: String, forItemWithID id: PersistentIdentifier) {
        guard let modelContext = _modelContext else { return }
        var descriptor = FetchDescriptor<CBItem>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        do {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let item = try modelContext.fetch(descriptor).first, !item.isDeleted,
                  item.hasAnalyzableImage else { return }
            // Only the OCR text: barcode payloads live in `barcodeText`.
            item.setRecognizedText(text)
            item.textRecognitionState = CBItem.TextRecognition.found
            let previousStamp = item.classificationStamp
            item.classify(with: classifierRuleset)
            // Still due for the background pass (a new capture's visual
            // pass, or other rules): keep it due.
            if previousStamp != classifierRuleset.stamp {
                item.classificationStamp = previousStamp
            }

            try modelContext.save()
            fetchItems(reset: true)
        } catch {
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to save recognized text", category: "SwiftData", error: error)
        }
    }

    /// "Forget recorded apps": clears the source app of every item.
    func clearSourceApps() {
        guard let modelContext = _modelContext else { return }
        do {
            let descriptor = FetchDescriptor<CBItem>(predicate: #Predicate { $0.sourceAppBundleID != nil })
            for item in try modelContext.fetch(descriptor) {
                item.sourceAppBundleID = nil
                item.sourceAppName = nil
            }
            try modelContext.save()
            fetchItems(reset: true)
        } catch {
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to clear source apps", category: "SwiftData", error: error)
        }
    }

    /// Recounts favorites and non-favorites (cheap fetchCounts) and drops the
    /// cached per-type counts. Every change to the history ends up here.
    func refreshItemCounts() {
        cachedTypeCounts = nil
        cachedFacets = nil
        countsRevision &+= 1
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
        releaseInactiveMemory()

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

        releaseInactiveMemory()
    }

    /// Frees what inactive items hold in memory: their decoded thumbnails,
    /// and — once none of them is in use — the rows loaded by scrolling past
    /// the first batch (they reload on the next scroll). Favorites keep their
    /// thumbnails. Never modifies the store: this used to nil `thumbnailData`,
    /// which the next save deleted from disk, only to re-render it from the
    /// full image on the next display.
    func releaseInactiveMemory() {
        guard let settingsManager = settingsManager else { return }

        let now = Date()
        let maxInactiveTime = TimeInterval(settingsManager.maxInactiveTime * 60)
        let isInactive: (CBItem) -> Bool = { item in
            guard let lastAccess = self.lastAccessTimes[item.persistentModelID] else { return true }
            return now.timeIntervalSince(lastAccess) > maxInactiveTime
        }

        let inactive = items.filter { !$0.isFavorite && isInactive($0) }
        CBItem.evictThumbnails(for: inactive.map(\.persistentModelID))

        var trimmed = 0
        if items.count > initialBatchSize,
           items.dropFirst(initialBatchSize).allSatisfy({ isInactive($0) && $0.id != selectedItem?.id }) {
            trimmed = items.count - initialBatchSize
            items.removeLast(trimmed)
            canLoadMore = true
        }

        let cutoffTime = now.addingTimeInterval(-maxInactiveTime)
        lastAccessTimes = lastAccessTimes.filter { $1 > cutoffTime }

        ErrorLogger.shared.debug(
            "Memory cleanup: released \(inactive.count) thumbnails, \(trimmed) scrolled rows (favorites preserved)",
            category: "Memory")
    }

    /// After a saved copy: enforce the item cap. The check is a fetchCount, so
    /// run it every time rather than guessing from `items.count`. Memory
    /// cleanup has its own timer.
    private func performCleanupIfNeeded() {
        performItemCountCleanup()
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
                NotificationCenter.default.post(name: .clearClipboardSelection, object: nil)
            }

            for item in nonFavoriteOldItems {
                announceDeletion(of: item.persistentModelID)
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

    /// Opens the item in the app that fits it: an image (or the image of a
    /// text + image item) in Preview, a file — whatever its type — in its
    /// default app. Text items use `openInTextEdit`.
    func openInPreview(_ item: CBItem) {
        switch item.itemType {
        case .image, .combined:
            if let data = item.imageData { ExternalOpener.openImage(data, fileName: item.imageExportFileName) }
        case .file:
            // The file itself, under its name. This used to render the file's
            // *icon* to a PNG for any non-image file (e.g. a PDF).
            if let data = item.fileData { ExternalOpener.openFile(data, fileName: item.fileExportFileName) }
        case .text:
            break
        }
    }

    func openInTextEdit(_ item: CBItem) {
        guard let text = item.content else { return }
        ExternalOpener.openTextInTextEdit(text, fileName: item.textExportFileName)
    }

    deinit {
        memoryCleanupTimer?.invalidate()
    }
}
