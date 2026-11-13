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

/// A Quick Picker tab. Raw values are stored in
/// `SettingsManager.quickPickerTabOrder`: never rename them.
enum QPTab: String, Hashable, CaseIterable, Identifiable {
    case all
    case favorites
    case text
    case images
    case files
    /// The encrypted vault (VaultManager), not history items.
    case passwords

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "All"
        case .favorites: return "Favs"
        case .text: return "Text"
        case .images: return "Images"
        case .files: return "Files"
        case .passwords: return "Passwords"
        }
    }

    /// The tabs in the user's order: stored ids first (unknown ones
    /// dropped), then any tab the stored order doesn't name yet, in the
    /// default order.
    static func ordered(_ stored: [String]) -> [QPTab] {
        var result: [QPTab] = []
        for id in stored {
            if let tab = QPTab(rawValue: id), !result.contains(tab) {
                result.append(tab)
            }
        }
        result += allCases.filter { !result.contains($0) }
        return result
    }

    /// The tab after this one among `tabs` (the ones shown), wrapping.
    func next(in tabs: [QPTab]) -> QPTab {
        guard let i = tabs.firstIndex(of: self), !tabs.isEmpty else { return .all }
        return tabs[(i + 1) % tabs.count]
    }

    func previous(in tabs: [QPTab]) -> QPTab {
        guard let i = tabs.firstIndex(of: self), !tabs.isEmpty else { return .all }
        return tabs[(i - 1 + tabs.count) % tabs.count]
    }

    /// Item types listed on the tab; nil = every type (All, Favorites) or
    /// no history items at all (Passwords).
    var itemTypes: Set<CBItemType>? {
        switch self {
        case .all, .favorites, .passwords: return nil
        case .text: return [.text, .combined]
        case .images: return [.image, .combined]
        case .files: return [.file]
        }
    }
}

/// The Passwords preview, run by QuickPickerWindowManager the way the
/// Quick Look setting says: Apple Quick Look (a decrypted copy in an
/// owner-only `Previews/Secret_` folder, deleted when the preview closes)
/// or the custom panel (from memory).
struct QPVaultPreviewActions {
    /// Opens the preview of the entry, or closes it; `expanded` (⌥Space)
    /// opens it large, or switches size when it is open.
    var toggle: (VaultPayload, _ expanded: Bool) -> Void = { _, _ in }
    /// Shows another entry in an open preview.
    var update: (VaultPayload) -> Void = { _ in }
    var hide: () -> Void = {}
    var isVisible: () -> Bool = { false }
}

struct QuickPickerView: View {
    @ObservedObject var viewModel: CBViewModel
    @ObservedObject var pinManager: PinManager
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
    @State private var typeCounts = CBViewModel.ItemTypeCounts()
    /// The chip picked in the category bar; nil = no category filter.
    @State private var chipSelection = ChipSelection()
    /// Category, language and app counts for the active tab's chips.
    @State private var facets = FacetCounts()
    @State private var countsReloadTask: Task<Void, Never>?
    /// The open ⌥E editor, nil when closed.
    @State private var itemEditor: QPItemEditorModel?
    @ObservedObject var vaultManager: VaultManager
    /// Cursor on the Passwords tab.
    @State private var vaultIndex = 0
    /// The Passwords entry whose content is shown (Space / →).
    @State private var revealedVaultID: UUID?
    /// The open ⌥E editor on the Passwords tab.
    @State private var vaultEditor: QPVaultEditorModel?
    /// The Passwords password, typed where the search field usually is.
    @State private var vaultPasswordInput = ""
    @FocusState private var isSearchFocused: Bool

    let onClose: () -> Void
    let onPreviewToggle: (CBItem) -> Void
    let onPreviewUpdate: (CBItem) -> Void
    let isPreviewVisible: () -> Bool
    // Type the given text out character by character (⌘⇧Return). Handled by
    // the window manager's TypePaster so it survives the picker closing and
    // stays cancellable.
    let onTypePaste: (String) -> Void
    /// The Touch ID prompt is gone: take the focus back.
    let onVaultAuthenticationEnded: () -> Void
    let vaultPreview: QPVaultPreviewActions
    private let settingsManager: SettingsManager?

    init(
        viewModel: CBViewModel,
        pinManager: PinManager,
        settingsManager: SettingsManager? = nil,
        vaultManager: VaultManager? = nil,
        onClose: @escaping () -> Void,
        onPreviewToggle: @escaping (CBItem) -> Void = { _ in },
        onPreviewUpdate: @escaping (CBItem) -> Void = { _ in },
        isPreviewVisible: @escaping () -> Bool = { false },
        onTypePaste: @escaping (String) -> Void = { _ in },
        onVaultAuthenticationEnded: @escaping () -> Void = {},
        vaultPreview: QPVaultPreviewActions = QPVaultPreviewActions()
    ) {
        self.viewModel = viewModel
        self.pinManager = pinManager
        self.settingsManager = settingsManager
        self.onClose = onClose
        self.onPreviewToggle = onPreviewToggle
        self.onPreviewUpdate = onPreviewUpdate
        self.isPreviewVisible = isPreviewVisible
        self.onTypePaste = onTypePaste
        self.onVaultAuthenticationEnded = onVaultAuthenticationEnded
        self.vaultPreview = vaultPreview
        // Previews and a missing manager get an inert in-memory vault, never
        // a second one on the real Keychain.
        self.vaultManager = vaultManager ?? VaultManager.makeInert()
    }

    /// The tabs shown, in the order set in Settings; Passwords can be hidden.
    private var visibleTabs: [QPTab] {
        let showPasswords = settingsManager?.showPasswordsTab ?? true
        return QPTab.ordered(settingsManager?.quickPickerTabOrder ?? [])
            .filter { $0 != .passwords || showPasswords }
    }

    private var isPasswordsTab: Bool { activeTab == .passwords }

    /// A locked vault with a Passwords password: the search field takes it.
    private var isTypingVaultPassword: Bool {
        isPasswordsTab && !vaultManager.isUnlocked && vaultManager.usesPassword
    }

    private var filteredItems: [CBItem] {
        // Apply tab filter in-memory too so ⌥Space (unfavorite while on
        // Favorites) and other state changes update the view without an
        // extra disk fetch.
        let base: [CBItem]
        if activeTab == .favorites {
            base = quickPickerItems.filter { $0.isFavorite }
        } else if let types = activeTab.itemTypes {
            base = quickPickerItems.filter { types.contains($0.itemType) }
        } else {
            base = quickPickerItems
        }

        let filter = itemFilter
        return filter.isEmpty ? base : base.filter(filter.matches)
    }

    // MARK: - Categories

    private var categories: [ItemCategory] {
        settingsManager?.itemCategories ?? ItemCategory.builtIns
    }

    /// The chip plus the search field (is:/app:/lang: tokens and text).
    private var itemFilter: ItemFilter {
        ItemFilter(
            categories: categories, selections: chipSelection.selected, query: .parse(searchText),
            searchImageText: settingsManager?.searchImageText ?? true)
    }

    private var categoryChips: [QPCategoryChip] {
        guard settingsManager?.showCategoryBar ?? true, activeTab != .passwords else { return [] }
        return QPCategoryChip.chips(for: categories, facets: facets, forImages: activeTab == .images)
    }

    /// Content and regex categories shown as row badges.
    private var badgeCategories: [ItemCategory] {
        categories.filter { $0.isEnabled && $0.kind != .apps && $0.builtIn != .language }
    }

    private var showsLanguageBadge: Bool {
        categories.contains { $0.builtIn == .language && $0.isEnabled }
    }

    /// ⌥← / ⌥→ move to one chip; with ⇧ they extend a run of chips.
    private func moveChipSelection(by step: Int, extending: Bool) {
        let chips = categoryChips.map(\.selection)
        if extending {
            chipSelection.extend(step, in: chips)
        } else {
            chipSelection.step(step, in: chips)
        }
    }

    /// Drops chips the active tab doesn't show (no items of its types).
    private func dropUnavailableCategory() {
        chipSelection.keep(only: categoryChips.map(\.selection))
    }

    var body: some View {
        // The editor is a sibling of the list, not a child: the list's key
        // handlers below (Space, arrows, ⏎) must not fire while typing a title.
        ZStack {
            pickerContent
            if let itemEditor {
                QPItemEditorView(
                    model: itemEditor,
                    onSave: { closeItemEditor(saving: true) },
                    onCancel: { closeItemEditor(saving: false) },
                    onMoveToVault: visibleTabs.contains(.passwords) ? { moveEditedItemToVault() } : nil
                )
            }
            if let vaultEditor {
                QPVaultEditorView(
                    model: vaultEditor,
                    onSave: { closeVaultEditor(saving: true) },
                    onCancel: { closeVaultEditor(saving: false) },
                    onDelete: { deleteInVaultEditor() }
                )
            }
        }
        .onChange(of: vaultManager.isUnlocked) { _, isUnlocked in
            // Locked behind the picker (screen lock, timeout): nothing of the
            // vault may stay on screen.
            vaultPasswordInput = ""
            guard !isUnlocked else { return }
            vaultPreview.hide()
            revealedVaultID = nil
            vaultIndex = 0
            if vaultEditor != nil { closeVaultEditor(saving: false) }
        }
        .onChange(of: vaultEntries.count) { _, newCount in
            if vaultIndex >= newCount { vaultIndex = max(0, newCount - 1) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardItemDeleted)) { note in
            let deletedID = note.object as? PersistentIdentifier
            // The rows must let go of the item before it leaves the context
            // on the next turn ("backing data was detached").
            if let deletedID {
                quickPickerItems.removeAll { $0.persistentModelID == deletedID }
            } else {
                quickPickerItems = []
            }
            // The item is about to leave the context: close without saving.
            guard let editor = itemEditor else { return }
            if deletedID == nil || deletedID == editor.itemID {
                closeItemEditor(saving: false)
            }
        }
    }

    private var pickerContent: some View {
        mainContent
            .onKeyPress(.escape) {
                if isPasswordsTab, vaultPreview.isVisible() {
                    vaultPreview.hide()
                    return .handled
                }
                if isPreviewVisible() {
                    onPreviewToggle(filteredItems[safe: selectedIndex] ?? filteredItems[0])
                } else {
                    onClose()
                }
                return .handled
            }
            .onKeyPress(keys: [.upArrow]) { keyPress in
                if isPasswordsTab {
                    moveVaultSelection(by: -1)
                    return .handled
                }
                moveSelection(by: -1, extendingWith: keyPress.modifiers.contains(.shift))
                return .handled
            }
            .onKeyPress(keys: [.downArrow]) { keyPress in
                if isPasswordsTab {
                    moveVaultSelection(by: 1)
                    return .handled
                }
                moveSelection(by: +1, extendingWith: keyPress.modifiers.contains(.shift))
                return .handled
            }
            .onKeyPress(keys: [.return]) { keyPress in
                // ⌘⇧⏎ → type the selected text out character by character
                // instead of the normal pasteboard + ⌘V.
                if keyPress.modifiers.contains(.command) && keyPress.modifiers.contains(.shift) {
                    if isPasswordsTab {
                        typeOutVaultEntry()
                    } else {
                        performTypePaste()
                    }
                    return .handled
                }
                if isPasswordsTab {
                    performVaultAction()
                    return .handled
                }
                if keyPress.modifiers.contains(.option) {
                    performOptionReturn()
                } else {
                    performAction()
                }
                return .handled
            }
            .onKeyPress(keys: [.space]) { keyPress in
                // Spaces are part of a password.
                if isTypingVaultPassword { return .ignored }
                // ⌥Space toggles favorite on the selected item.
                if keyPress.modifiers.contains(.option) {
                    // Passwords have no favorites: ⌥Space is the large
                    // preview there, as in Finder.
                    if isPasswordsTab {
                        toggleVaultPreview(expanded: true)
                    } else {
                        toggleFavoriteForSelected()
                    }
                    return .handled
                }
                guard triggerKey == .space else { return .ignored }
                return handlePreviewTrigger()
            }
            .onKeyPress(keys: [.rightArrow]) { keyPress in
                if isTypingVaultPassword { return .ignored }
                // ⌥→ / ⌘→ move the cursor (by word, to the end); only a
                // plain → opens the preview.
                guard triggerKey == .arrowRight, keyPress.modifiers.isDisjoint(with: [.option, .command, .control])
                else { return .ignored }
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
                // Passwords are filtered in memory (vaultEntries).
                if isPasswordsTab {
                    vaultIndex = 0
                    revealedVaultID = nil
                    searchTask?.cancel()
                    return
                }

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
                            await performSearch()
                        }
                    }
                } else {
                    // Reset to showing all items when search is cleared
                    reloadForActiveTab()
                }
            }
            .onChange(of: activeTab) { oldTab, newTab in
                selectedIndex = 0
                selectionAnchor = nil
                vaultIndex = 0
                revealedVaultID = nil
                vaultPasswordInput = ""
                // Neither a decrypted entry nor a history item stays in
                // the preview across the Passwords boundary.
                if (oldTab == .passwords || newTab == .passwords),
                   vaultPreview.isVisible() || isPreviewVisible() {
                    vaultPreview.hide()
                }
                if newTab == .passwords {
                    // Opening the tab counts as use; an expired vault locks.
                    vaultManager.checkExpiry()
                    vaultManager.noteUse()
                }
                searchTask?.cancel()
                loadTabCounts()
                dropUnavailableCategory()
                reloadForActiveTab()
                isSearchFocused = true
            }
            .onChange(of: viewModel.countsRevision) { _, _ in
                // A capture or a background rescan while the picker is open.
                // Counting scans the whole history, so a burst of changes
                // (a rescan, favorites toggled in a row) recounts once.
                countsReloadTask?.cancel()
                countsReloadTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    loadTabCounts()
                    dropUnavailableCategory()
                }
            }
            .onChange(of: chipSelection.selected) { _, _ in
                selectedIndex = 0
                selectionAnchor = nil
                searchTask?.cancel()
                reloadForActiveTab()
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
            if !categoryChips.isEmpty {
                QPCategoryBar(chips: categoryChips, selection: chipSelection) { chip, adding in
                    chipSelection.click(chip, adding: adding)
                    // Same focus re-grab as the tab pills.
                    isSearchFocused = false
                    DispatchQueue.main.async {
                        isSearchFocused = true
                    }
                }
            }
            Divider()
            if isPasswordsTab {
                QPVaultPane(
                    vaultManager: vaultManager,
                    entries: vaultEntries,
                    selectedIndex: $vaultIndex,
                    revealedID: revealedVaultID,
                    searchText: searchText,
                    onUnlock: { performVaultAction() },
                    onPaste: { performVaultAction() },
                    onEdit: { _ in openVaultEditor() },
                    onToggleReveal: { entry in toggleVaultReveal(entry.id) }
                )
            } else {
            if let match = vaultLabelMatches {
                vaultMatchesBar(count: match.count, titles: match.titles)
            }
            QPItemList(
                filteredItems: filteredItems,
                selectedIndex: $selectedIndex,
                searchText: $searchText,
                isLoading: isLoadingItems,
                hasMoreItems: hasMoreItems,
                ocrEnabled: settingsManager?.enableOCROptionKey == true,
                isItemPinned: { item in pinManager.isPinned(item) },
                onTogglePin: { item in pinManager.togglePin(item) },
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
                },
                onEdit: { item in
                    openItemEditor(for: item)
                },
                badgeCategories: badgeCategories,
                showLanguage: showsLanguageBadge,
                showBadges: settingsManager?.showRowBadges ?? true,
                showImageText: settingsManager?.showImageTextInRows ?? true
            )
            }
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
            // The picker opens on the first tab of the user's order.
            if let first = visibleTabs.first, first != activeTab {
                activeTab = first
            }
            loadInitialItems()
            loadTabCounts()
            vaultManager.checkExpiry()

            // Forward-Tab and Shift-Tab cycle tabs. We intercept at the
            // NSEvent layer because AppKit's field editor consumes Shift-Tab
            // for focus traversal before SwiftUI's .onKeyPress runs.
            //
            // Toggle focus false→true on the next tick: AppKit's responder
            // can desync from SwiftUI's @FocusState during the Tab event,
            // and re-assigning `true` to an already-`true` state is a no-op
            // that won't re-grab focus from the field editor.
            tabInterceptor.onTab = {
                activeTab = activeTab.next(in: visibleTabs)
                isSearchFocused = false
                DispatchQueue.main.async {
                    isSearchFocused = true
                }
            }
            tabInterceptor.onShiftTab = {
                activeTab = activeTab.previous(in: visibleTabs)
                isSearchFocused = false
                DispatchQueue.main.async {
                    isSearchFocused = true
                }
            }
            tabInterceptor.onOptionP = {
                // Passwords are never pinned: a pin is stored in plaintext.
                guard !isPasswordsTab else { return }
                togglePinForSelection()
            }
            // ⌥⏎ is intercepted too: with the search field focused, the field
            // editor takes it as insertNewlineIgnoringFieldEditor:, SwiftUI
            // submits the field and onSubmit pastes the image instead of OCR.
            tabInterceptor.onOptionReturn = {
                performOptionReturn()
            }
            tabInterceptor.onOptionArrow = { step, extending in
                moveChipSelection(by: step, extending: extending)
            }
            // Without chips, ⌥←/→ keep moving the cursor by word.
            tabInterceptor.hasChips = { !categoryChips.isEmpty }
            tabInterceptor.isPasswordsTab = { isPasswordsTab && vaultManager.isUnlocked }
            // ⌥ letters can be part of a password: let them type.
            tabInterceptor.passesOptionKeys = { isTypingVaultPassword }
            tabInterceptor.onOptionL = {
                vaultManager.lock()
            }
            tabInterceptor.onOptionR = {
                toggleVaultReveal()
            }
            // ⌘1…⌘9: the tab at that place in the bar.
            tabInterceptor.onCommandDigit = { number in
                guard let tab = visibleTabs[safe: number - 1] else { return }
                activeTab = tab
                isSearchFocused = false
                DispatchQueue.main.async {
                    isSearchFocused = true
                }
            }
            tabInterceptor.onOptionE = {
                if isPasswordsTab {
                    openVaultEditor()
                    return
                }
                guard let item = filteredItems[safe: selectedIndex] else { return }
                openItemEditor(for: item)
            }
            tabInterceptor.start()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
        .onDisappear {
            tabInterceptor.stop()
            countsReloadTask?.cancel()
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
        if isTypingVaultPassword {
            vaultPasswordBar
        } else {
            historySearchBar
        }
    }

    /// Where the search field is, so the cursor is already there.
    private var vaultPasswordBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .foregroundColor(.accentColor)
                .font(.system(size: 14, weight: .medium))
            SecureField("Passwords password, then ⏎", text: $vaultPasswordInput)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit { performVaultAction() }
                .disabled(vaultManager.isAuthenticating)
            if vaultManager.isAuthenticating {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private var historySearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.accentColor)
                .font(.system(size: 14, weight: .medium))

            TextField(
                isPasswordsTab
                    ? "Search passwords by title…"
                    : activeTab == .favorites
                    ? "Search favorites… (is:link, app:Safari, lang:uk)"
                    : "Search clipboard… (is:link, app:Safari, lang:uk)",
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
            if isPasswordsTab && vaultManager.isUnlocked {
                vaultLockButton(compact: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private var tabBar: some View {
        // Six tabs don't fit 500 pt at full size: the first layout that fits
        // wins, each a little tighter, so no pill is ever cut off.
        ViewThatFits(in: .horizontal) {
            tabRow(density: 0)
            tabRow(density: 1)
            tabRow(density: 2)
            tabRow(density: 3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    /// 0: full pills and the ⇥ hint. 1: tighter, no hint. 2: an inactive
    /// Passwords pill shows only its lock. 3: inactive pills drop their counts.
    private func tabRow(density: Int) -> some View {
        HStack(spacing: density == 0 ? 8 : 5) {
            ForEach(visibleTabs) { tab in
                tabPill(tab, density: density)
            }
            Spacer(minLength: 0)
            if density == 0 {
                tabSwitchHint
            }
        }
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

    private func tabPill(_ tab: QPTab, density: Int) -> some View {
        let isActive = activeTab == tab
        let showsTitle = isActive || tab != .passwords || density < 2
        let showsCount = (isActive || density < 3) && (tab != .passwords || vaultManager.isUnlocked)
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
                if tab == .passwords {
                    Image(systemName: vaultManager.isUnlocked ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(isActive ? Color.white : Color.accentColor)
                }
                if showsTitle {
                    Text(tab.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
                // A locked vault doesn't say how much it holds.
                if showsCount {
                    Text("\(tabCount(tab))")
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .foregroundStyle(
                            isActive ? Color.white.opacity(0.85) : Color.secondary
                        )
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .padding(.horizontal, density == 0 ? 10 : 7)
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
        .help(tabHelp(tab))
    }

    private func tabHelp(_ tab: QPTab) -> String {
        guard let index = visibleTabs.firstIndex(of: tab), index < 9 else { return tab.title }
        return "\(tab.title) (⌘\(index + 1))"
    }

    private func tabCount(_ tab: QPTab) -> Int {
        switch tab {
        case .all:
            // "All" is everything on disk, favorites included.
            return viewModel.totalItemCount + viewModel.favoriteItemCount
        case .favorites:
            return viewModel.favoriteItemCount
        case .text:
            return typeCounts.text
        case .images:
            return typeCounts.images
        case .files:
            return typeCounts.files
        case .passwords:
            return vaultManager.entries.count
        }
    }

    @ViewBuilder
    private var footerBar: some View {
        if isPasswordsTab {
            vaultFooterBar
        } else {
            historyFooterBar
        }
    }

    @ViewBuilder
    private var vaultFooterBar: some View {
        Divider()
        HStack(spacing: 6) {
            Label(
                vaultManager.isUnlocked ? "Encrypted · locks when idle" : "Encrypted · locked",
                systemImage: "lock.shield")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            shortcutBadge("ESC", label: "Close")
            if vaultManager.isUnlocked {
                if vaultEntries[safe: vaultIndex]?.typeableText != nil {
                    typePasteBadge()
                }
                shortcutBadge(triggerKey == .space ? "⎵" : "→", label: "Preview")
                shortcutBadge("⌥R", label: "Show")
                vaultLockButton(compact: false)
            } else {
                shortcutBadge("⏎", label: "Unlock")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private var historyFooterBar: some View {
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
                if selectionIsTypeable {
                    typePasteBadge()
                }
                favoriteToggleBadge()
                pinToggleBadge()

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

    private func pinToggleBadge() -> some View {
        HStack(spacing: 3) {
            Text("⌥P")
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
            Image(systemName: "pin")
                .font(.system(size: 9))
        }
        .foregroundStyle(.tertiary)
        .help("Pin / unpin the selected item to the screen")
    }

    private func typePasteBadge() -> some View {
        HStack(spacing: 3) {
            Text("⌘⇧⏎")
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
            Image(systemName: "keyboard")
                .font(.system(size: 9))
        }
        .foregroundStyle(.tertiary)
        .help("Type the selected text character by character (⌘⇧Return)")
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

    /// Favorites count comes live from the view model; per-type counts need
    /// a full scan, which the view model caches until the history changes.
    private func loadTabCounts() {
        typeCounts = viewModel.itemTypeCounts()
        guard activeTab != .passwords else {
            facets = FacetCounts()
            return
        }
        facets = activeTab == .favorites
            ? FacetCounts(items: viewModel.favoriteItems)
            : viewModel.facetCounts(ofTypes: activeTab.itemTypes)
    }

    private func togglePinForSelection() {
        // If there's a Shift-extended range, pin each item in it; otherwise
        // toggle on the cursor row. Already-pinned items inside a range get
        // toggled off, which mirrors the single-item behavior.
        if let range = selectedRange(), range.count > 1 {
            let items = range.compactMap { filteredItems[safe: $0] }
            items.forEach { pinManager.togglePin($0) }
            return
        }
        guard selectedIndex < filteredItems.count else { return }
        pinManager.togglePin(filteredItems[selectedIndex])
    }

    private func toggleFavoriteForSelected() {
        guard selectedIndex < filteredItems.count else { return }
        let item = filteredItems[selectedIndex]
        viewModel.toggleFavorite(item)
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

    // MARK: - ⌥E item editor

    private func openItemEditor(for item: CBItem) {
        guard itemEditor == nil, vaultEditor == nil else { return }
        if isPreviewVisible() {
            onPreviewToggle(item)
        }
        if let index = filteredItems.firstIndex(where: { $0.persistentModelID == item.persistentModelID }) {
            selectedIndex = index
        }
        selectionAnchor = nil

        let editor = QPItemEditorModel(item: item, viewModel: viewModel) { [self] in
            favoritesChangedInEditor()
        }
        tabInterceptor.onEditorKey = { [weak editor] key in
            guard let editor else { return }
            switch key {
            case .save:
                if editor.isConfirmingUnfavorite {
                    editor.confirmUnfavorite()
                } else {
                    closeItemEditor(saving: true)
                }
            case .cancel:
                if editor.isConfirmingUnfavorite {
                    editor.isConfirmingUnfavorite = false
                } else {
                    closeItemEditor(saving: false)
                }
            case .moveUp:
                editor.moveFavorite(by: -1)
            case .moveDown:
                editor.moveFavorite(by: 1)
            case .toggleFavorite:
                if editor.isConfirmingUnfavorite {
                    editor.confirmUnfavorite()
                } else {
                    editor.requestFavoriteToggle()
                }
            case .delete:
                break  // history items are deleted elsewhere
            case .moveToVault:
                if !editor.isConfirmingUnfavorite, visibleTabs.contains(.passwords) {
                    moveEditedItemToVault()
                }
            case .reveal:
                break
            }
        }
        isSearchFocused = false
        itemEditor = editor
    }

    private func closeItemEditor(saving: Bool) {
        guard let editor = itemEditor else { return }
        if saving {
            editor.saveTitle()
        }
        tabInterceptor.onEditorKey = nil
        itemEditor = nil
        // Same false→true toggle as the tab switch: AppKit's responder may
        // still point at the editor's (now gone) field.
        DispatchQueue.main.async {
            isSearchFocused = true
        }
    }

    /// ⌥K / Move to Passwords: unlock if needed, seal a copy into the vault
    /// (or find the same content there already), delete the history item,
    /// then show it on the Passwords tab.
    private func moveEditedItemToVault() {
        guard let editor = itemEditor, !editor.isMovingToVault,
              let item = quickPickerItems.first(where: { $0.persistentModelID == editor.itemID })
        else { return }
        editor.vaultMessage = nil
        if !vaultManager.isUnlocked, vaultManager.usesPassword {
            editor.vaultMessage = "Unlock the Passwords tab with your password first."
            return
        }
        editor.isMovingToVault = true
        Task { @MainActor in
            let unlocked = await vaultManager.unlock(reason: "move this item to your passwords")
            onVaultAuthenticationEnded()
            editor.isMovingToVault = false
            // The editor closed, or the item was deleted, while Touch ID was up.
            guard itemEditor === editor,
                  quickPickerItems.contains(where: { $0.persistentModelID == editor.itemID })
            else { return }
            guard unlocked else {
                editor.vaultMessage = "Passwords stayed locked."
                return
            }
            guard var payload = VaultPayload(item: item) else {
                editor.vaultMessage = "This item has nothing to save."
                return
            }
            let typedTitle = editor.title.trimmingCharacters(in: .whitespacesAndNewlines)
            payload.title = typedTitle.isEmpty ? nil : typedTitle

            let vaultID: UUID
            switch vaultManager.add(payload) {
            case .added(let id):
                vaultID = id
            case .duplicate(let id):
                // Same content already there: keep that one, name it if it has no name.
                if vaultManager.entry(withID: id)?.title == nil, !typedTitle.isEmpty {
                    vaultManager.rename(id, to: typedTitle)
                }
                vaultID = id
            case .nothingToAdd:
                editor.vaultMessage = "This item has nothing to save."
                return
            case .locked, .failed:
                editor.vaultMessage = "Couldn't save it to Passwords."
                return
            }

            closeItemEditor(saving: false)
            viewModel.deleteItem(item)
            searchText = ""
            activeTab = .passwords
            // After the tab switch has reset the cursor.
            DispatchQueue.main.async { selectVaultEntry(vaultID) }
        }
    }

    /// The Favorites tab lists a copy of `favoriteItems`; re-read it so a
    /// move or (un)favorite shows behind the editor, and keep the cursor on
    /// the edited item.
    private func favoritesChangedInEditor() {
        loadTabCounts()
        guard activeTab == .favorites, let editor = itemEditor else { return }
        quickPickerItems = viewModel.favoriteItems
        if let index = filteredItems.firstIndex(where: { $0.persistentModelID == editor.itemID }) {
            selectedIndex = index
        }
    }

    private func reloadForActiveTab() {
        if activeTab == .passwords {
            searchTask?.cancel()
            quickPickerItems = []
            hasMoreItems = false
            isLoadingItems = false
            return
        }
        // Switching tabs keeps an active search (or chip) instead of listing
        // the tab's newest rows and filtering only those.
        if !itemFilter.isEmpty && activeTab != .favorites {
            searchTask?.cancel()
            searchTask = Task { await performSearch() }
            return
        }

        switch activeTab {
        case .all:
            loadInitialItems()
        case .favorites:
            quickPickerItems = viewModel.favoriteItems
            hasMoreItems = false
            isLoadingItems = false
        case .text, .images, .files:
            quickPickerItems = viewModel.items(ofTypes: activeTab.itemTypes ?? [])
            hasMoreItems = false
            isLoadingItems = false
        case .passwords:
            break  // handled above
        }
    }

    private func performAction() {
        if isPasswordsTab {
            performVaultAction()
            return
        }
        if let range = selectedRange(), range.count > 1 {
            performMultiPaste(range: range)
            return
        }

        guard selectedIndex < filteredItems.count else { return }

        let item = filteredItems[selectedIndex]
        guard viewModel.copyAndUpdateItem(item) else { return }

        onClose()
        PasteSimulator.paste()
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

            // Through ClipboardManager, so the monitor doesn't save the joined
            // text as yet another history item.
            viewModel.getClipboardManager().copyToClipboard(joined)

            onClose()
            PasteSimulator.paste()
        } else {
            items.forEach { viewModel.markItemAccessed($0) }
            onClose()
            // One Accessibility alert up front rather than one per item.
            guard PasteSimulator.ensureAccessibility() else { return }
            // Let focus return to the previously-active window first, then
            // start the sequential paste chain.
            DispatchQueue.main.asyncAfter(deadline: .now() + PasteSimulator.defaultDelay) {
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
        PasteSimulator.paste(after: 0.05)

        let next = index + 1
        guard next < items.count else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            pasteSequentially(items, at: next)
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
        if isPasswordsTab {
            toggleVaultPreview(expanded: false)
            return
        }
        guard selectedIndex < filteredItems.count else { return }
        onPreviewToggle(filteredItems[selectedIndex])
    }

    // ⌥⏎ on a Shift-extended range is always OCR intent — bypass the
    // per-user `enableOCROptionKey` toggle, which only gates the single-item
    // shortcut.
    private func performOptionReturn() {
        if isPasswordsTab {
            performVaultAction()
            return
        }
        let hasMultiSelection = (selectedRange()?.count ?? 0) > 1
        if hasMultiSelection || settingsManager?.enableOCROptionKey == true {
            performOCRAction()
        } else {
            performAction()
        }
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
              let cgImage = TextRecognizer.cgImage(from: image) else {
            // Couldn't get CGImage — fall through to normal paste
            performAction()
            return
        }

        // Close the picker immediately (same UX as normal Enter)
        viewModel.markItemAccessed(item)
        let itemID = item.persistentModelID
        onClose()

        // Run OCR on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            guard let recognizedText = TextRecognizer.recognizeText(in: cgImage),
                  !recognizedText.isEmpty else { return }

            DispatchQueue.main.async {
                // The image keeps its text, so search finds it later.
                viewModel.rememberRecognizedText(recognizedText, forItemWithID: itemID)
                // Straight to the pasteboard on purpose: the clipboard monitor
                // then saves the recognized text as a history item, honoring
                // pause and excluded apps.
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(recognizedText, forType: .string)
                PasteSimulator.paste()
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
            case image(CGImage, PersistentIdentifier)
        }

        let sources: [OCRSource] = items.compactMap { item -> OCRSource? in
            switch item.itemType {
            case .text, .combined:
                // Prefer existing text. For combined items the text portion
                // is already the user's intent — skip OCR on its image.
                if let c = item.content, !c.isEmpty { return .text(c) }
                if item.itemType == .combined,
                   let img = item.image,
                   let cg = TextRecognizer.cgImage(from: img) {
                    return .image(cg, item.persistentModelID)
                }
                return nil
            case .image:
                guard let img = item.image,
                      let cg = TextRecognizer.cgImage(from: img) else {
                    return nil
                }
                return .image(cg, item.persistentModelID)
            case .file:
                guard item.isImageFile,
                      let img = item.filePreviewImage,
                      let cg = TextRecognizer.cgImage(from: img) else {
                    return nil
                }
                return .image(cg, item.persistentModelID)
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
            var recognizedByItem: [(PersistentIdentifier, String)] = []
            for source in sources {
                switch source {
                case .text(let s):
                    parts.append(s)
                case .image(let cg, let id):
                    if let recognized = TextRecognizer.recognizeText(in: cg) {
                        parts.append(recognized)
                        recognizedByItem.append((id, recognized))
                    }
                }
            }

            let combined = parts.joined(separator: "\n")
            guard !combined.isEmpty else { return }

            DispatchQueue.main.async {
                for (id, text) in recognizedByItem {
                    viewModel.rememberRecognizedText(text, forItemWithID: id)
                }
                // Straight to the pasteboard on purpose, like single OCR: the
                // monitor saves the recognized text as a history item.
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(combined, forType: .string)
                PasteSimulator.paste()
            }
        }
    }

    // Whether the current selection is something performTypePaste can act on:
    // a single text/combined item with content, or a Shift-extended range
    // that's entirely text/combined. Drives the footer hint's visibility.
    private var selectionIsTypeable: Bool {
        if let range = selectedRange(), range.count > 1 {
            let items = range.compactMap { filteredItems[safe: $0] }
            return !items.isEmpty && items.allSatisfy { isTextLikeWithContent($0) }
        }
        guard let item = filteredItems[safe: selectedIndex] else { return false }
        return isTextLikeWithContent(item)
    }

    private func isTextLikeWithContent(_ item: CBItem) -> Bool {
        (item.itemType == .text || item.itemType == .combined)
            && (item.content?.isEmpty == false)
    }

    // "Type" paste (both ⌘ keys + Return): instead of writing to the pasteboard
    // and simulating ⌘V, emit the text as synthetic keystrokes so it lands in
    // apps that block programmatic paste (some password/secure fields, remote
    // desktops, terminals). Text-only — images/files have nothing to type.
    private func performTypePaste() {
        let targetText: String?

        if let range = selectedRange(), range.count > 1 {
            let items = range.compactMap { filteredItems[safe: $0] }
            guard !items.isEmpty, items.allSatisfy({ isTextLikeWithContent($0) }) else { return }
            items.forEach { viewModel.markItemAccessed($0) }
            targetText = items.compactMap { $0.content }.joined(separator: "\n")
        } else {
            guard let item = filteredItems[safe: selectedIndex],
                  isTextLikeWithContent(item),
                  let content = item.content else { return }
            viewModel.markItemAccessed(item)
            targetText = content
        }

        guard let text = targetText, !text.isEmpty else { return }

        guard PasteSimulator.ensureAccessibility() else { return }

        onClose()
        // Let focus return to the previously-active window before typing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onTypePaste(text)
        }
    }

    // MARK: - Passwords tab

    /// Locks the vault now (also ⌥L here, and the global Lock Passwords
    /// hotkey, ⌃⌥L by default).
    private func vaultLockButton(compact: Bool) -> some View {
        Button {
            vaultManager.lock()
        } label: {
            if compact {
                Image(systemName: "lock.fill")
                    .foregroundColor(.accentColor)
            } else {
                HStack(spacing: 3) {
                    Text("⌥L")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor.opacity(0.15))
                        )
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                    Text("Lock")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(Color.accentColor)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(lockHelp)
    }

    private var lockHelp: String {
        "Lock Passwords (⌥L here; the Lock Passwords hotkey in Settings → Hotkeys, ⌃⌥L by default, works anywhere)"
    }

    /// Searching another tab: Passwords entries whose label or file name
    /// matches (unlocked only: the labels are sealed too). nil = none.
    private var vaultLabelMatches: (count: Int, titles: [String])? {
        guard visibleTabs.contains(.passwords), vaultManager.isUnlocked,
              !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let matches = vaultManager.entries.filter { $0.matchesLabel(searchText) }
        guard !matches.isEmpty else { return nil }
        return (matches.count, matches.prefix(3).map(\.displayName))
    }

    /// "3 in Passwords: …" above the results; a click (or ⌘ and the tab's
    /// number) opens the Passwords tab with the same search.
    private func vaultMatchesBar(count: Int, titles: [String]) -> some View {
        Button {
            activeTab = .passwords
            isSearchFocused = false
            DispatchQueue.main.async { isSearchFocused = true }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .foregroundStyle(Color.accentColor)
                Text("\(count) in Passwords: \(titles.joined(separator: ", "))\(count > titles.count ? "…" : "")")
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer()
                if let index = visibleTabs.firstIndex(of: .passwords), index < 9 {
                    shortcutBadge("⌘\(index + 1)", label: "Show")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.accentColor.opacity(0.08))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    /// Unlocked entries matching the search; empty while locked.
    private var vaultEntries: [VaultPayload] {
        vaultManager.entries.filter { $0.matches(searchText) }
    }

    private func moveVaultSelection(by delta: Int) {
        let newIndex = vaultIndex + delta
        guard vaultEntries.indices.contains(newIndex) else { return }
        vaultIndex = newIndex
        revealedVaultID = nil
        if vaultPreview.isVisible(), let entry = vaultEntries[safe: newIndex] {
            vaultPreview.update(entry)
        }
    }

    /// ⌥R or the eye: shows or hides the content in the row. `id` defaults
    /// to the selected entry; another row's eye also selects it.
    private func toggleVaultReveal(_ id: UUID? = nil) {
        guard vaultManager.isUnlocked,
              let target = id ?? vaultEntries[safe: vaultIndex]?.id else { return }
        if let index = vaultEntries.firstIndex(where: { $0.id == target }) {
            vaultIndex = index
        }
        revealedVaultID = revealedVaultID == target ? nil : target
        vaultManager.noteUse()
    }

    /// Space / → (preview beside the picker) and ⌥Space (large).
    private func toggleVaultPreview(expanded: Bool) {
        vaultManager.checkExpiry()
        guard vaultManager.isUnlocked, let entry = vaultEntries[safe: vaultIndex] else { return }
        vaultManager.noteUse()
        vaultPreview.toggle(entry, expanded)
    }

    private func unlockVaultWithPassword() {
        let password = vaultPasswordInput
        guard !password.isEmpty, !vaultManager.isAuthenticating else { return }
        Task { @MainActor in
            let unlocked = await vaultManager.unlock(password: password)
            vaultPasswordInput = ""
            if unlocked { vaultIndex = 0 }
            DispatchQueue.main.async { isSearchFocused = true }
        }
    }

    /// Touch ID (or the password) while the picker stays open.
    private func unlockVault() {
        Task { @MainActor in
            let unlocked = await vaultManager.unlock()
            onVaultAuthenticationEnded()
            if unlocked { vaultIndex = 0 }
        }
    }

    /// ⏎: unlock (Touch ID, or the typed password), or paste the selected entry.
    private func performVaultAction() {
        vaultManager.checkExpiry()
        guard vaultManager.isUnlocked else {
            if vaultManager.usesPassword {
                unlockVaultWithPassword()
            } else {
                unlockVault()
            }
            return
        }
        guard let entry = vaultEntries[safe: vaultIndex],
              vaultManager.copyToPasteboard(entry.id) else { return }
        onClose()
        PasteSimulator.paste()
    }

    /// ⌘⇧⏎: type a text entry out, for fields that block pasting.
    private func typeOutVaultEntry() {
        vaultManager.checkExpiry()
        guard let entry = vaultEntries[safe: vaultIndex],
              let text = vaultManager.typeableText(of: entry.id),
              PasteSimulator.ensureAccessibility() else { return }
        onClose()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onTypePaste(text)
        }
    }

    private func openVaultEditor() {
        vaultManager.checkExpiry()
        guard itemEditor == nil, vaultEditor == nil, vaultManager.isUnlocked,
              let entry = vaultEntries[safe: vaultIndex] else { return }
        let editor = QPVaultEditorModel(entry: entry, vaultManager: vaultManager)
        tabInterceptor.onEditorKey = { [weak editor] key in
            guard let editor else { return }
            switch key {
            case .save:
                if editor.isConfirmingDelete {
                    deleteInVaultEditor()
                } else {
                    closeVaultEditor(saving: true)
                }
            case .cancel:
                if editor.isConfirmingDelete {
                    editor.isConfirmingDelete = false
                } else {
                    closeVaultEditor(saving: false)
                }
            case .moveUp:
                editor.move(by: -1)
                selectVaultEntry(editor.entryID)
            case .moveDown:
                editor.move(by: 1)
                selectVaultEntry(editor.entryID)
            case .delete:
                // Never confirms: a repeated key press mustn't delete an entry.
                editor.isConfirmingDelete = true
            case .reveal:
                editor.isRevealed.toggle()
            case .toggleFavorite, .moveToVault:
                break  // passwords have no favorites and are in the vault already
            }
        }
        revealedVaultID = nil
        vaultPreview.hide()
        isSearchFocused = false
        vaultEditor = editor
    }

    private func closeVaultEditor(saving: Bool) {
        guard let editor = vaultEditor else { return }
        if saving {
            editor.save()
        }
        tabInterceptor.onEditorKey = nil
        vaultEditor = nil
        DispatchQueue.main.async {
            isSearchFocused = true
        }
    }

    private func deleteInVaultEditor() {
        guard let editor = vaultEditor else { return }
        if editor.confirmDelete() {
            closeVaultEditor(saving: false)
        }
    }

    private func selectVaultEntry(_ id: UUID) {
        if let index = vaultEntries.firstIndex(where: { $0.id == id }) {
            vaultIndex = index
        }
    }

    private static let initialPageSize = 30
    private static let pageSize = 50

    private func loadInitialItems() {
        quickPickerItems = viewModel.historyPage(offset: 0, limit: Self.initialPageSize)
        hasMoreItems = quickPickerItems.count == Self.initialPageSize
        isLoadingItems = false
    }

    private func loadMoreItems() {
        guard !isLoadingItems, hasMoreItems else { return }
        isLoadingItems = true

        // Next turn, so the appearing row's callback doesn't mutate the list.
        // Everything loaded stays: the old 150-row window re-fetched and
        // discarded the same page forever, so rows past 150 never showed.
        Task {
            let page = viewModel.historyPage(offset: quickPickerItems.count, limit: Self.pageSize)
            let loaded = Set(quickPickerItems.map(\.persistentModelID))
            quickPickerItems.append(contentsOf: page.filter { !loaded.contains($0.persistentModelID) })
            hasMoreItems = page.count == Self.pageSize
            isLoadingItems = false
        }
    }

    /// Searches the whole history (limited to the tab's types), not just the
    /// newest 300 rows as before. Runs inside `searchTask`; a newer search,
    /// chip or tab switch cancels it. A chip or tokens alone check only
    /// inline columns, so they list every match; free text stops at 300.
    private func performSearch() async {
        guard activeTab != .passwords else { return }
        let filter = itemFilter
        let limit = filter.isCheap ? Int.max : 300
        let found = await viewModel.searchItems(filter: filter, types: activeTab.itemTypes, limit: limit)
        guard !Task.isCancelled else { return }
        quickPickerItems = found
        hasMoreItems = false
        isLoadingItems = false
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
    // ⌥P pin toggle. Matched by physical key code, not character, so it works
    // on non-Latin layouts (e.g. Ukrainian ЙЦУКЕН, where the P key types "з").
    var onOptionP: (() -> Void)?
    // ⌥⏎ OCR paste. The search field's editor would otherwise turn it into a
    // submit (plain paste) before SwiftUI's .onKeyPress sees it.
    var onOptionReturn: (() -> Void)?
    // ⌥E opens the item editor. By key code: ⌥E is a dead key (´) on the US
    // layout and would start a composed character in the search field.
    var onOptionE: (() -> Void)?
    // ⌥← / ⌥→ step through the category chips, ⌥⇧← / ⌥⇧→ extend the chip
    // selection (-1 / +1, extending). Swallowed, so the search field
    // doesn't move or select by word.
    var onOptionArrow: ((Int, Bool) -> Void)?
    /// Asked synchronously: ⌥←/→ are only taken while there are chips.
    var hasChips: (() -> Bool)?

    enum EditorKey {
        case save, cancel, moveUp, moveDown, toggleFavorite
        /// ⌘⌫ in the Passwords editor: asks to delete; only ⏎ confirms.
        case delete
        /// ⌥K in the history editor: Move to Passwords.
        case moveToVault
        /// ⌥R in the Passwords editor: show or hide the content.
        case reveal
    }

    /// ⌥L locks the vault, ⌥R shows the selected entry in its row; taken
    /// only while the Passwords tab is active.
    var onOptionL: (() -> Void)?
    var onOptionR: (() -> Void)?
    /// True while a password is typed: ⌥ letters reach the field.
    var passesOptionKeys: (() -> Bool)?
    /// ⌘1…⌘9 with the number.
    var onCommandDigit: ((Int) -> Void)?
    /// Key codes of 1…9 on the main row (ANSI positions, any layout).
    private static let digitKeyCodes: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
    var isPasswordsTab: (() -> Bool)?

    /// Set while the ⌥E editor is open. The picker's own shortcuts stand
    /// down; ⏎, Esc, ⌥E, ⌥↑, ⌥↓ and ⌥F go here instead, and the rest of the
    /// typing reaches the title field.
    var onEditorKey: ((EditorKey) -> Void)?

    private var monitor: Any?
    private static let tabKeyCode: UInt16 = 48
    private static let pKeyCode: UInt16 = 35
    private static let eKeyCode: UInt16 = 14
    private static let fKeyCode: UInt16 = 3
    private static let lKeyCode: UInt16 = 37
    private static let kKeyCode: UInt16 = 40
    private static let rKeyCode: UInt16 = 15
    private static let deleteKeyCode: UInt16 = 51
    private static let escapeKeyCode: UInt16 = 53
    private static let upArrowKeyCode: UInt16 = 126
    private static let downArrowKeyCode: UInt16 = 125
    private static let leftArrowKeyCode: UInt16 = 123
    private static let rightArrowKeyCode: UInt16 = 124
    private static let returnKeyCodes: Set<UInt16> = [36, 76]  // Return, keypad Enter

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // NOTE: must NOT use `intercept(event) ?? event` — that turns a
            // deliberate nil (swallow) back into the event, so the keystroke
            // (e.g. the "p" in ⌥P) would leak into the search field.
            guard let self else { return event }
            return self.intercept(event)
        }
    }

    func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        onTab = nil
        onShiftTab = nil
        onOptionP = nil
        onOptionReturn = nil
        onOptionE = nil
        onOptionArrow = nil
        hasChips = nil
        onEditorKey = nil
        onOptionL = nil
        onOptionR = nil
        isPasswordsTab = nil
        passesOptionKeys = nil
        onCommandDigit = nil
    }

    private func intercept(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags

        if let onEditorKey {
            return interceptForEditor(event, flags: flags, handler: onEditorKey)
        }

        // ⌘1…⌘9 (no other modifier) switch tabs, also while typing a password.
        if let number = Self.digitKeyCodes[event.keyCode],
           flags.intersection([.command, .option, .control, .shift]) == .command {
            DispatchQueue.main.async { [weak self] in
                self?.onCommandDigit?(number)
            }
            return nil
        }

        if passesOptionKeys?() == true, event.keyCode != Self.tabKeyCode {
            return event
        }

        // ⌥← / ⌥→, with or without ⇧ (no Control/Command).
        if event.keyCode == Self.leftArrowKeyCode || event.keyCode == Self.rightArrowKeyCode,
           flags.contains(.option),
           !flags.contains(.control),
           !flags.contains(.command),
           hasChips?() ?? false {
            let step = event.keyCode == Self.leftArrowKeyCode ? -1 : 1
            let extending = flags.contains(.shift)
            DispatchQueue.main.async { [weak self] in
                self?.onOptionArrow?(step, extending)
            }
            return nil
        }

        // ⌥L / ⌥R on the Passwords tab (no Control/Command).
        if event.keyCode == Self.lKeyCode || event.keyCode == Self.rKeyCode,
           flags.contains(.option),
           !flags.contains(.control),
           !flags.contains(.command),
           isPasswordsTab?() ?? false {
            let isLock = event.keyCode == Self.lKeyCode
            DispatchQueue.main.async { [weak self] in
                if isLock {
                    self?.onOptionL?()
                } else {
                    self?.onOptionR?()
                }
            }
            return nil
        }

        // ⌥E (no Control/Command).
        if event.keyCode == Self.eKeyCode,
           flags.contains(.option),
           !flags.contains(.control),
           !flags.contains(.command) {
            DispatchQueue.main.async { [weak self] in
                self?.onOptionE?()
            }
            return nil
        }

        // ⌥P (Option held, no Control/Command — the latter is the global pin
        // hotkey handled elsewhere). Key code is layout-independent.
        if event.keyCode == Self.pKeyCode,
           flags.contains(.option),
           !flags.contains(.control),
           !flags.contains(.command) {
            DispatchQueue.main.async { [weak self] in
                self?.onOptionP?()
            }
            return nil  // swallow so no character is typed into the search field
        }

        // ⌥⏎ (no Control/Command — ⌘⇧⏎ type-paste stays with .onKeyPress).
        if Self.returnKeyCodes.contains(event.keyCode),
           flags.contains(.option),
           !flags.contains(.control),
           !flags.contains(.command) {
            DispatchQueue.main.async { [weak self] in
                self?.onOptionReturn?()
            }
            return nil  // swallow so the field editor doesn't submit or insert a newline
        }

        guard event.keyCode == Self.tabKeyCode else { return event }

        let shift = flags.contains(.shift)
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

    private func interceptForEditor(
        _ event: NSEvent, flags: NSEvent.ModifierFlags, handler: @escaping (EditorKey) -> Void
    ) -> NSEvent? {
        let option = flags.contains(.option)
        let commandOrControl = flags.contains(.command) || flags.contains(.control)

        let key: EditorKey?
        switch event.keyCode {
        case Self.escapeKeyCode:
            key = .cancel
        case _ where Self.returnKeyCodes.contains(event.keyCode) && !commandOrControl:
            key = .save
        case Self.eKeyCode where option && !commandOrControl:
            key = .save
        case Self.fKeyCode where option && !commandOrControl:
            key = .toggleFavorite
        case Self.upArrowKeyCode where option && !commandOrControl:
            key = .moveUp
        case Self.downArrowKeyCode where option && !commandOrControl:
            key = .moveDown
        // ⌘⌫ asks to delete (⏎ confirms); ⌥⌫ stays word-delete in the field.
        case Self.deleteKeyCode where flags.contains(.command) && !option && !flags.contains(.control):
            key = .delete
        case Self.kKeyCode where option && !commandOrControl:
            key = .moveToVault
        case Self.rKeyCode where option && !commandOrControl:
            key = .reveal
        case Self.tabKeyCode:
            return nil  // the title field is the only field; keep focus in it
        default:
            key = nil
        }
        guard let key else { return event }
        DispatchQueue.main.async { handler(key) }
        return nil
    }

    deinit {
        if let m = monitor {
            NSEvent.removeMonitor(m)
        }
    }
}


#Preview {
    QuickPickerView(viewModel: CBViewModel(), pinManager: PinManager()) { /* preview: no-op close */ }
}
