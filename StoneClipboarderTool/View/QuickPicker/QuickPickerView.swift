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

struct QuickPickerView: View {
    @ObservedObject var viewModel: CBViewModel
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var quickPickerItems: [CBItem] = []
    @State private var isLoadingItems = false
    @State private var hasMoreItems = true
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool

    let onClose: () -> Void

    init(viewModel: CBViewModel, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onClose = onClose
    }

    private var filteredItems: [CBItem] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return quickPickerItems
        }

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return quickPickerItems.filter { item in
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
        VStack(spacing: 0) {
            dragHandle
            searchBar
            Divider()
            QPItemList(
                filteredItems: filteredItems,
                selectedIndex: $selectedIndex,
                searchText: $searchText,
                isLoading: isLoadingItems,
                hasMoreItems: hasMoreItems,
                onLoadMore: {
                    loadMoreItems()
                }
            ) {
                performAction()
            }
        }
        .frame(width: 500, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .clipped()
        .onAppear {
            loadInitialItems()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filteredItems.count - 1 {
                selectedIndex += 1
            }
            return .handled
        }
        .onKeyPress(.return) {
            performAction()
            return .handled
        }
        .onChange(of: searchText) { _, newValue in
            selectedIndex = 0

            // Cancel previous search task
            searchTask?.cancel()

            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                loadInitialItems()
            }
        }
        .onChange(of: filteredItems.count) { _, newCount in
            if selectedIndex >= newCount {
                selectedIndex = max(0, newCount - 1)
            }
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
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search clipboard...", text: $searchText)
                .textFieldStyle(.roundedBorder)
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
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func performAction() {
        guard selectedIndex < filteredItems.count else { return }

        let item = filteredItems[selectedIndex]

        viewModel.markItemAccessed(item)
        copyToPasteboard(item)

        onClose()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            simulatePaste()
        }
    }

    private func copyToPasteboard(_ item: CBItem) {
        viewModel.copyAndUpdateItem(item)
    }

    private func simulatePaste() {
        // Check accessibility permissions
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            DispatchQueue.main.async {
                // Ensure the app is active and frontmost so the alert appears on top
                NSApp.activate(ignoringOtherApps: true)
                
                let alert = NSAlert()
                alert.messageText = "Accessibility Access Required"
                alert.informativeText = "To paste automatically, StoneClipboarder needs accessibility permissions.\n\nPlease grant access in System Settings > Privacy & Security > Accessibility."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Cancel")
                
                // Force alert window to be above other windows
                alert.window.level = .floating
                
                if alert.runModal() == .alertFirstButtonReturn {
                     if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
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

#Preview {
    QuickPickerView(viewModel: CBViewModel()) {
        print("Closed")
    }
}
