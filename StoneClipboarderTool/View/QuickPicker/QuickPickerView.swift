//
//  QuickPickerView.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 13.08.2025.
//

import AppKit
import ApplicationServices
import SwiftData
import SwiftUI
import Vision

enum QPTab: Hashable, CaseIterable, Identifiable {
    case all
    case favorites
    case text
    case images
    case files

    var id: Self { self }

    var next: QPTab {
        let cases = QPTab.allCases
        guard let i = cases.firstIndex(of: self) else { return .all }
        return cases[(i + 1) % cases.count]
    }

    var previous: QPTab {
        let cases = QPTab.allCases
        guard let i = cases.firstIndex(of: self) else { return .all }
        return cases[(i - 1 + cases.count) % cases.count]
    }
}

struct QuickPickerView: View {
    @ObservedObject var viewModel: CBViewModel
    @StateObject private var tabInterceptor = TabKeyInterceptor()
    @State private var activeTab: QPTab = .all
    @State private var searchText = ""
    @State private var selectedIndex = 0
    // Shift+Arrow multi-select. nil = single-selection; otherwise the selected
    // range is min(anchor, selectedIndex)...max(anchor, selectedIndex).
    @State private var selectionAnchor: Int? = nil
    @State private var quickPickerItems: [CBItem] = []
    @State private var isLoadingItems = false
    @State private var hasMoreItems = true
    @State private var searchTask: Task<Void, Never>?
    @State private var favoriteCount: Int = 0
    @State private var textCount: Int = 0
    @State private var imageCount: Int = 0
    @State private var fileCount: Int = 0
    @FocusState private var isSearchFocused: Bool

    let onClose: () -> Void
    let onPreviewToggle: (CBItem) -> Void
    let onPreviewUpdate: (CBItem) -> Void
    let isPreviewVisible: () -> Bool
    private let settingsManager: SettingsManager?

    init(
        viewModel: CBViewModel,
        settingsManager: SettingsManager? = nil,
        onClose: @escaping () -> Void,
        onPreviewToggle: @escaping (CBItem) -> Void = { _ in },
        onPreviewUpdate: @escaping (CBItem) -> Void = { _ in },
        isPreviewVisible: @escaping () -> Bool = { false }
    ) {
        self.viewModel = viewModel
        self.settingsManager = settingsManager
        self.onClose = onClose
        self.onPreviewToggle = onPreviewToggle
        self.onPreviewUpdate = onPreviewUpdate
        self.isPreviewVisible = isPreviewVisible
    }

    private var filteredItems: [CBItem] {
        // Apply tab filter in-memory too so ⌥Space (unfavorite while on
        // Favorites) and other state changes update the view without an
        // extra disk fetch.
        let base: [CBItem]
        switch activeTab {
        case .all:
            base = quickPickerItems
        case .favorites:
            base = quickPickerItems.filter { $0.isFavorite }
        case .text:
            base = quickPickerItems.filter { $0.itemType == .text || $0.itemType == .combined }
        case .images:
            base = quickPickerItems.filter { $0.itemType == .image || $0.itemType == .combined }
        case .files:
            base = quickPickerItems.filter { $0.itemType == .file }
        }

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSearch.isEmpty {
            return base
        }

        return base.filter { item in
            switch item.itemType {
            case .text, .combined:
                if let content = item.content {
                    return content.localizedCaseInsensitiveContains(trimmedSearch)
                }
                return false
            case .image, .file:
                return item.displayContent.localizedCaseInsensitiveContains(trimmedSearch)
            }
        }
    }

    var body: some View {
        mainContent
            .onKeyPress(.escape) {
                if isPreviewVisible() {
                    onPreviewToggle(filteredItems[safe: selectedIndex] ?? filteredItems[0])
                } else {
                    onClose()
                }
                return .handled
            }
            .onKeyPress(keys: [.upArrow]) { keyPress in
                moveSelection(by: -1, extendingWith: keyPress.modifiers.contains(.shift))
                return .handled
            }
            .onKeyPress(keys: [.downArrow]) { keyPress in
                moveSelection(by: +1, extendingWith: keyPress.modifiers.contains(.shift))
                return .handled
            }
            .onKeyPress(keys: [.return]) { keyPress in
                let optionHeld = keyPress.modifiers.contains(.option)
                let hasMultiSelection = (selectedRange()?.count ?? 0) > 1
                // ⌥⏎ on a Shift-extended range is always OCR intent — bypass
                // the per-user `enableOCROptionKey` toggle, which only gates
                // the single-item shortcut.
                if optionHeld && (hasMultiSelection || settingsManager?.enableOCROptionKey == true) {
                    performOCRAction()
                } else {
                    performAction()
                }
                return .handled
            }
            .onKeyPress(keys: [.space]) { keyPress in
                // ⌥Space toggles favorite on the selected item.
                if keyPress.modifiers.contains(.option) {
                    toggleFavoriteForSelected()
                    return .handled
                }
                guard triggerKey == .space else { return .ignored }
                return handlePreviewTrigger()
            }
            .onKeyPress(.rightArrow) {
                guard triggerKey == .arrowRight else { return .ignored }
                // Only open QL when cursor is at the end of search text
                if isSearchFocused && !searchText.isEmpty,
                   let fieldEditor = NSApp.keyWindow?.firstResponder as? NSTextView {
                    let sel = fieldEditor.selectedRange()
                    let cursorEnd = sel.location + sel.length
                    if cursorEnd < fieldEditor.string.count {
                        return .ignored // Let cursor move normally
                    }
                }
                return handlePreviewTrigger()
            }
            .onChange(of: searchText) { _, newValue in
                selectedIndex = 0
                selectionAnchor = nil

                // Cancel previous search task
                searchTask?.cancel()

                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    // Favorites tab: all favorites are already in memory,
                    // so filteredItems handles search synchronously.
                    if activeTab == .favorites { return }

                    // Debounce search with 300ms delay
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        if !Task.isCancelled {
                            await MainActor.run {
                                performSearch(newValue)
                            }
                        }
                    }
                } else {
                    // Reset to showing all items when search is cleared
                    reloadForActiveTab()
                }
            }
            .onChange(of: activeTab) { _, _ in
                selectedIndex = 0
                selectionAnchor = nil
                searchTask?.cancel()
                reloadForActiveTab()
                isSearchFocused = true
            }
            .onChange(of: filteredItems.count) { _, newCount in
                if selectedIndex >= newCount {
                    selectedIndex = max(0, newCount - 1)
                }
                // Drop anchor if it now points past the list.
                if let anchor = selectionAnchor, anchor >= newCount {
                    selectionAnchor = nil
                }
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            dragHandle
            searchBar
            tabBar
            Divider()
            QPItemList(
                filteredItems: filteredItems,
                selectedIndex: $selectedIndex,
                searchText: $searchText,
                isLoading: isLoadingItems,
                hasMoreItems: hasMoreItems,
                ocrEnabled: settingsManager?.enableOCROptionKey == true,
                multiSelectionRange: selectedRange(),
                onClearMultiSelection: {
                    selectionAnchor = nil
                },
                onLoadMore: {
                    loadMoreItems()
                },
                performAction: {
                    performAction()
                },
                onOpenPreview: { item in
                    viewModel.openInPreview(item)
                },
                onOpenTextEdit: { item in
                    viewModel.openInTextEdit(item)
                }
            )
            footerBar
        }
        .frame(width: 500, height: 460)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .clipped()
        .onAppear {
            loadInitialItems()
            loadTabCounts()

            // Forward-Tab and Shift-Tab cycle tabs. We intercept at the
            // NSEvent layer because AppKit's field editor consumes Shift-Tab
            // for focus traversal before SwiftUI's .onKeyPress runs.
            //
            // Toggle focus false→true on the next tick: AppKit's responder
            // can desync from SwiftUI's @FocusState during the Tab event,
            // and re-assigning `true` to an already-`true` state is a no-op
            // that won't re-grab focus from the field editor.
            tabInterceptor.onTab = {
                activeTab = activeTab.next
                isSearchFocused = false
                DispatchQueue.main.async {
                    isSearchFocused = true
                }
            }
            tabInterceptor.onShiftTab = {
                activeTab = activeTab.previous
                isSearchFocused = false
                DispatchQueue.main.async {
                    isSearchFocused = true
                }
            }
            tabInterceptor.start()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
        .onDisappear {
            tabInterceptor.stop()
        }
    }

    @ViewBuilder
    private var dragHandle: some View {
        HStack {
            Spacer()
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.gray.opacity(0.4))
                .frame(width: 36, height: 4)
            Spacer()
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Color.clear)
    }

    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.accentColor)
                .font(.system(size: 14, weight: .medium))

            TextField(
                activeTab == .favorites ? "Search favorites..." : "Search clipboard...",
                text: $searchText
            )
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit {
                    performAction()
                }

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(QPTab.allCases) { tab in
                tabPill(tab)
            }
            Spacer()
            tabSwitchHint
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // Discoverability hint: Tab cycles forward, Shift+Tab cycles backward.
    private var tabSwitchHint: some View {
        HStack(spacing: 4) {
            Text("⇥")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
            Text("switch")
                .font(.system(size: 10))
        }
        .foregroundStyle(.tertiary)
        .help("Tab to switch tabs forward, Shift+Tab backward")
    }

    private func tabPill(_ tab: QPTab) -> some View {
        let isActive = activeTab == tab
        return Button {
            activeTab = tab
            // Click must NOT steal focus from the search field — otherwise
            // shortcuts like Tab/Space/⏎ would stop working. Toggle to force
            // SwiftUI to re-grab focus if AppKit's responder desynced.
            isSearchFocused = false
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        } label: {
            HStack(spacing: 5) {
                if tab == .favorites {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(isActive ? Color.white : .red)
                }
                Text(tabTitle(tab))
                    .font(.system(size: 11, weight: .medium))
                Text("\(tabCount(tab))")
                    .font(.system(size: 10))
                    .foregroundStyle(
                        isActive ? Color.white.opacity(0.85) : Color.secondary
                    )
            }
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isActive ? Color.accentColor : Color.clear)
            )
            .overlay(
                Capsule()
                    .stroke(
                        isActive ? Color.clear : Color.secondary.opacity(0.35),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func tabTitle(_ tab: QPTab) -> String {
        switch tab {
        case .all: return "All"
        case .favorites: return "Favorites"
        case .text: return "Text"
        case .images: return "Images"
        case .files: return "Files"
        }
    }

    private func tabCount(_ tab: QPTab) -> Int {
        switch tab {
        case .all:
            // "All" is everything on disk, favorites included.
            return viewModel.totalItemCount + viewModel.favoriteItemCount
        case .favorites:
            return favoriteCount
        case .text:
            return textCount
        case .images:
            return imageCount
        case .files:
            return fileCount
        }
    }

    @ViewBuilder
    private var footerBar: some View {
        Divider()
        HStack(spacing: 0) {
            // Left side: disk counts (non-favorites + favorites). No "in memory"
            // — that's an internal detail, not useful at-a-glance.
            HStack(spacing: 4) {
                Text("\(viewModel.totalItemCount)")
                if viewModel.favoriteItemCount > 0 {
                    Text("+")
                    Text("\(viewModel.favoriteItemCount)")
                    Image(systemName: "heart.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.red)
                }
                Text("on Disk")
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)

            Spacer()

            // Right side: only the shortcuts that aren't shown in the row
            // (Paste/OCR live on the selected row now) or in the tab bar.
            HStack(spacing: 6) {
                if let range = selectedRange(), range.count > 1 {
                    Text("\(range.count) selected")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    shortcutBadge("⇧↑↓", label: "Extend")
                } else {
                    shortcutBadge("⇧↑↓", label: "Multi-select")
                }
                shortcutBadge("ESC", label: "Close")
                favoriteToggleBadge()

                if settingsManager?.quickLookMode != .disabled {
                    let key = settingsManager?.quickLookTriggerKey ?? .space
                    shortcutBadge(key == .space ? "⎵" : "→", label: "Preview")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func favoriteToggleBadge() -> some View {
        HStack(spacing: 3) {
            Text("⌥⎵")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
            Image(systemName: "heart")
                .font(.system(size: 9))
        }
        .foregroundStyle(.tertiary)
        .help("Toggle favorite on the selected item")
    }

    private func shortcutBadge(_ key: String, label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
            Text(label)
                .font(.system(size: 9))
        }
        .foregroundStyle(.tertiary)
    }

    // Single fetch + in-memory tally. SwiftData #Predicate over String-backed
    // enums is finicky; iterating once is simple, accurate, and cheap at
    // typical clipboard-history sizes.
    private func loadTabCounts() {
        guard let modelContext = viewModel.modelContext else { return }
        do {
            let all = try modelContext.fetch(FetchDescriptor<CBItem>())
            favoriteCount = all.lazy.filter { $0.isFavorite }.count
            textCount = all.lazy.filter { $0.itemType == .text || $0.itemType == .combined }.count
            imageCount = all.lazy.filter { $0.itemType == .image || $0.itemType == .combined }.count
            fileCount = all.lazy.filter { $0.itemType == .file }.count
        } catch {
            favoriteCount = 0
            textCount = 0
            imageCount = 0
            fileCount = 0
        }
    }

    private func toggleFavoriteForSelected() {
        guard selectedIndex < filteredItems.count else { return }
        let item = filteredItems[selectedIndex]
        viewModel.toggleFavorite(item)
        loadTabCounts()
        // Toggling favorite can re-filter the list (Favorites tab) — drop
        // the multi-select anchor so the range doesn't reference stale rows.
        selectionAnchor = nil

        if activeTab == .favorites {
            let newCount = filteredItems.count
            if selectedIndex >= newCount {
                selectedIndex = max(0, newCount - 1)
            }
        }
    }

    private func reloadForActiveTab() {
        switch activeTab {
        case .all:
            loadInitialItems()
        case .favorites:
            loadFavoritesOnly()
        case .text:
            loadByTypes([.text, .combined])
        case .images:
            loadByTypes([.image, .combined])
        case .files:
            loadByTypes([.file])
        }
    }

    private func loadFavoritesOnly() {
        guard let modelContext = viewModel.modelContext else { return }
        let descriptor = FetchDescriptor<CBItem>(
            predicate: #Predicate<CBItem> { $0.isFavorite },
            sortBy: [SortDescriptor(\.orderIndex, order: .forward)]
        )
        do {
            quickPickerItems = try modelContext.fetch(descriptor)
            hasMoreItems = false
            isLoadingItems = false
        } catch {
            quickPickerItems = []
            hasMoreItems = false
            isLoadingItems = false
        }
    }

    private func loadByTypes(_ types: [CBItemType]) {
        guard let modelContext = viewModel.modelContext else { return }
        let descriptor = FetchDescriptor<CBItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        do {
            let all = try modelContext.fetch(descriptor)
            quickPickerItems = all.filter { types.contains($0.itemType) }
            hasMoreItems = false
            isLoadingItems = false
        } catch {
            quickPickerItems = []
            hasMoreItems = false
            isLoadingItems = false
        }
    }

    private func performAction() {
        if let range = selectedRange(), range.count > 1 {
            performMultiPaste(range: range)
            return
        }

        guard selectedIndex < filteredItems.count else { return }

        let item = filteredItems[selectedIndex]

        viewModel.markItemAccessed(item)
        copyToPasteboard(item)

        onClose()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            simulatePaste()
        }
    }

    // Resolved Shift+Arrow selection range, clamped to current items.
    // Returns nil when no anchor (= single selection on `selectedIndex`).
    private func selectedRange() -> ClosedRange<Int>? {
        guard let anchor = selectionAnchor, !filteredItems.isEmpty else { return nil }
        let lastValid = filteredItems.count - 1
        let lo = max(0, min(anchor, selectedIndex))
        let hi = min(lastValid, max(anchor, selectedIndex))
        guard hi >= lo else { return nil }
        return lo...hi
    }

    private func moveSelection(by delta: Int, extendingWith extending: Bool) {
        let newIndex = selectedIndex + delta
        guard newIndex >= 0, newIndex < filteredItems.count else { return }

        if extending {
            if selectionAnchor == nil { selectionAnchor = selectedIndex }
        } else {
            selectionAnchor = nil
        }

        selectedIndex = newIndex
        if let item = filteredItems[safe: selectedIndex] {
            onPreviewUpdate(item)
        }
    }

    // Multi-paste strategy:
    //   - All text/combined items → join `content` with newlines and paste
    //     once (snappy, no flicker, works in any text field).
    //   - Anything else (images, files, mixed) → paste each item sequentially:
    //     copy to clipboard, ⌘V, wait, repeat. The receiving app sees a
    //     separate paste per item, so images come through as images and files
    //     as files. Apps that don't support a given type ignore that step.
    // Multi-OCR (⌥⏎) is handled separately in performOCRAction.
    private func performMultiPaste(range: ClosedRange<Int>) {
        let items = range.compactMap { filteredItems[safe: $0] }
        guard !items.isEmpty else { return }

        let allTextLike = items.allSatisfy { item in
            (item.itemType == .text || item.itemType == .combined)
                && (item.content?.isEmpty == false)
        }

        if allTextLike {
            let joined = items.compactMap { $0.content }.joined(separator: "\n")
            items.forEach { viewModel.markItemAccessed($0) }

            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(joined, forType: .string)

            onClose()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                simulatePaste()
            }
        } else {
            items.forEach { viewModel.markItemAccessed($0) }
            onClose()
            // Let focus return to the previously-active window first, then
            // start the sequential paste chain.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                pasteSequentially(items, at: 0)
            }
        }
    }

    // Per-step timing matches the single-item path (~0.05s between copy and
    // ⌘V) plus a 0.25s gap between items so the receiving app finishes
    // handling one paste before the next clipboard write.
    private func pasteSequentially(_ items: [CBItem], at index: Int) {
        guard index < items.count else { return }
        let item = items[index]
        viewModel.copyAndUpdateItem(item)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            simulatePaste()
            let next = index + 1
            guard next < items.count else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                pasteSequentially(items, at: next)
            }
        }
    }

    private var triggerKey: QuickLookTriggerKey {
        settingsManager?.quickLookTriggerKey ?? .space
    }

    private func handlePreviewTrigger() -> KeyPress.Result {
        if triggerKey == .space {
            // Space trigger: allow QL when search is empty OR ends with a space
            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || searchText.hasSuffix(" ") {
                // Don't modify searchText — just consume the key and toggle preview
                togglePreview()
                return .handled
            }
            return .ignored
        } else {
            // Arrow right trigger: always toggle
            togglePreview()
            return .handled
        }
    }

    private func togglePreview() {
        guard selectedIndex < filteredItems.count else { return }
        onPreviewToggle(filteredItems[selectedIndex])
    }

    private func copyToPasteboard(_ item: CBItem) {
        viewModel.copyAndUpdateItem(item)
    }

    private func performOCRAction() {
        // Multi-select: combine text from text items + OCR'd text from
        // images, preserving order.
        if let range = selectedRange(), range.count > 1 {
            let items = range.compactMap { filteredItems[safe: $0] }
            performMultiOCR(items: items, range: range)
            return
        }

        guard selectedIndex < filteredItems.count else { return }

        let item = filteredItems[selectedIndex]

        // Determine the image to OCR based on item type
        let imageToProcess: NSImage?
        switch item.itemType {
        case .image:
            imageToProcess = item.image
        case .combined:
            imageToProcess = item.image
        case .file where item.isImageFile:
            imageToProcess = item.filePreviewImage
        default:
            // Not an image item — fall through to normal paste
            performAction()
            return
        }

        guard let image = imageToProcess,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            // Couldn't get CGImage — fall through to normal paste
            performAction()
            return
        }

        // Close the picker immediately (same UX as normal Enter)
        viewModel.markItemAccessed(item)
        onClose()

        // Run OCR on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            guard let recognizedText = Self.recognizeText(in: cgImage),
                  !recognizedText.isEmpty else { return }

            DispatchQueue.main.async {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(recognizedText, forType: .string)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.simulatePaste()
                }
            }
        }
    }

    // Each item contributes one chunk to the final paste: text items use
    // their `content` verbatim, image items get OCR'd via Vision, image
    // files use their preview image. Non-image files contribute nothing.
    // Order matches the visible selection (top-to-bottom). Bails to
    // performMultiPaste if nothing in the range yields OCR-able input
    // (e.g. all non-image files), so ⌥⏎ always does something useful.
    private func performMultiOCR(items: [CBItem], range: ClosedRange<Int>) {
        enum OCRSource {
            case text(String)
            case image(CGImage)
        }

        let sources: [OCRSource] = items.compactMap { item -> OCRSource? in
            switch item.itemType {
            case .text, .combined:
                // Prefer existing text. For combined items the text portion
                // is already the user's intent — skip OCR on its image.
                if let c = item.content, !c.isEmpty { return .text(c) }
                if item.itemType == .combined,
                   let img = item.image,
                   let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    return .image(cg)
                }
                return nil
            case .image:
                guard let img = item.image,
                      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    return nil
                }
                return .image(cg)
            case .file:
                guard item.isImageFile,
                      let img = item.filePreviewImage,
                      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    return nil
                }
                return .image(cg)
            }
        }

        guard !sources.isEmpty else {
            // Nothing OCR-able (e.g. all non-image files) — fall back to
            // the regular multi-paste behavior.
            performMultiPaste(range: range)
            return
        }

        items.forEach { viewModel.markItemAccessed($0) }
        onClose()

        // Process sources off the main thread, preserving order. Each image
        // gets its own request + handler (no shared mutable state). We use
        // a serial loop on a background queue — Vision is heavy enough that
        // parallelism wouldn't help much and pulls in Sendable headaches.
        DispatchQueue.global(qos: .userInitiated).async {
            var parts: [String] = []
            for source in sources {
                switch source {
                case .text(let s):
                    parts.append(s)
                case .image(let cg):
                    if let recognized = Self.recognizeText(in: cg) {
                        parts.append(recognized)
                    }
                }
            }

            let combined = parts.joined(separator: "\n")
            guard !combined.isEmpty else { return }

            DispatchQueue.main.async {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(combined, forType: .string)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    simulatePaste()
                }
            }
        }
    }

    // Synchronous Vision OCR. Safe to call concurrently — each invocation
    // creates its own request and handler with no captured mutable state.
    private static func recognizeText(in cgImage: CGImage) -> String? {
        final class Box { var text: String = "" }
        let box = Box()

        let request = VNRecognizeTextRequest { req, _ in
            guard let observations = req.results as? [VNRecognizedTextObservation] else {
                return
            }
            box.text = observations.compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        return box.text.isEmpty ? nil : box.text
    }

    private func simulatePaste() {
        if !AccessibilityAlertHelper.isAccessibilityGranted {
            AccessibilityAlertHelper.showAccessibilityAlert()
            return
        }

        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        let location = CGEventTapLocation.cghidEventTap

        keyDown?.post(tap: location)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            keyUp?.post(tap: location)
        }
    }

    private func loadInitialItems() {
        guard let modelContext = viewModel.modelContext else { return }

        // Get the most recent 30 items synchronously for instant display
        var recentDescriptor = FetchDescriptor<CBItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        recentDescriptor.fetchLimit = 30

        do {
            let recentItems = try modelContext.fetch(recentDescriptor)
            self.quickPickerItems = recentItems
            self.hasMoreItems = recentItems.count == 30
            self.isLoadingItems = false

            // Don't automatically load more - only when user scrolls
            // The 30 items are enough for immediate use
        } catch {
            print("Failed to load recent QuickPicker items: \(error)")
            self.quickPickerItems = []
            self.hasMoreItems = false
            self.isLoadingItems = false
        }
    }

    private func loadMoreItems() {
        guard let modelContext = viewModel.modelContext, !isLoadingItems, hasMoreItems else {
            return
        }

        isLoadingItems = true

        Task {
            var descriptor = FetchDescriptor<CBItem>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            descriptor.fetchOffset = quickPickerItems.count
            descriptor.fetchLimit = 50

            do {
                let newItems = try modelContext.fetch(descriptor)
                await MainActor.run {
                    self.quickPickerItems.append(contentsOf: newItems)
                    self.hasMoreItems = newItems.count == 50
                    self.isLoadingItems = false

                    // Clean up memory - keep only last 150 items loaded, but always keep first 30
                    if self.quickPickerItems.count > 150 {
                        let firstThirty = Array(self.quickPickerItems.prefix(30))
                        let remaining = Array(self.quickPickerItems.dropFirst(30).prefix(120))
                        self.quickPickerItems = firstThirty + remaining
                    }
                }
            } catch {
                await MainActor.run {
                    print("Failed to load more QuickPicker items: \(error)")
                    self.hasMoreItems = false
                    self.isLoadingItems = false
                }
            }
        }
    }

    private func performSearch(_ searchTerm: String) {
        guard let modelContext = viewModel.modelContext else { return }

        isLoadingItems = true

        Task {
            let trimmedSearch = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)

            // Fetch items for search - use a reasonable limit
            var descriptor = FetchDescriptor<CBItem>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            descriptor.fetchLimit = 300  // Reasonable limit for search

            do {
                let allItems = try modelContext.fetch(descriptor)
                let searchLower = trimmedSearch.lowercased()

                let searchResults = allItems.filter { item in
                    switch item.itemType {
                    case .text, .combined:
                        return item.content?.lowercased().contains(searchLower) == true
                            || item.contentPreview?.lowercased().contains(searchLower) == true
                    case .file:
                        return item.fileName?.lowercased().contains(searchLower) == true
                    case .image:
                        return true  // Show all images in search for now
                    }
                }

                await MainActor.run {
                    self.quickPickerItems = searchResults
                    self.hasMoreItems = false  // Don't paginate search results
                    self.isLoadingItems = false
                }
            } catch {
                await MainActor.run {
                    print("Failed to search QuickPicker items: \(error)")
                    self.quickPickerItems = []
                    self.hasMoreItems = false
                    self.isLoadingItems = false
                }
            }
        }
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Tab key interception
//
// SwiftUI's `.onKeyPress(.tab)` is not reliable on macOS when a TextField has
// focus: the field editor (NSTextView) consumes Shift-Tab for backward focus
// traversal before SwiftUI sees it. We catch the raw key event ourselves so
// both directions work consistently while typing in the search field.
@MainActor
final class TabKeyInterceptor: ObservableObject {
    var onTab: (() -> Void)?
    var onShiftTab: (() -> Void)?

    private var monitor: Any?
    private static let tabKeyCode: UInt16 = 48

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.intercept(event) ?? event
        }
    }

    func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        onTab = nil
        onShiftTab = nil
    }

    private func intercept(_ event: NSEvent) -> NSEvent? {
        guard event.keyCode == Self.tabKeyCode else { return event }

        let shift = event.modifierFlags.contains(.shift)
        // Defer to next runloop tick — mutating SwiftUI state directly inside
        // an event-dispatch callback can fight with the active event cycle.
        DispatchQueue.main.async { [weak self] in
            if shift {
                self?.onShiftTab?()
            } else {
                self?.onTab?()
            }
        }
        return nil  // swallow so the field editor doesn't move focus
    }

    deinit {
        if let m = monitor {
            NSEvent.removeMonitor(m)
        }
    }
}


#Preview {
    QuickPickerView(viewModel: CBViewModel()) {
        print("Closed")
    }
}
