//
//  QPItemList.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 14.08.2025.
//

import SwiftUI

struct QPItemList: View {
    var filteredItems: [CBItem]
    @Binding var selectedIndex: Int
    @Binding var searchText: String
    var isLoading: Bool = false
    var hasMoreItems: Bool = true
    let onLoadMore: () -> Void
    let performAction: () -> Void
    var onOpenPreview: ((CBItem) -> Void)?
    var onOpenTextEdit: ((CBItem) -> Void)?

    var body: some View {
        if filteredItems.isEmpty {
            emptyState
        } else {
            itemsList
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No items found")
                .font(.headline)
                .foregroundStyle(.secondary)

            if !searchText.isEmpty {
                Text("Try a different search term")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var itemsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                        QPItemRow(item: item, isSelected: index == selectedIndex)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedIndex = index
                                performAction()
                            }
                            .contextMenu {
                                // Open in Preview (for images/files)
                                if let onOpenPreview = onOpenPreview, shouldShowPreview(for: item) {
                                    Button("Open in Preview") {
                                        onOpenPreview(item)
                                    }
                                }

                                // Open with TextEdit (for text/combined)
                                if let onOpenTextEdit = onOpenTextEdit, item.content != nil {
                                    Button("Open with TextEdit") {
                                        onOpenTextEdit(item)
                                    }
                                }
                                
                                Divider()

                                Button("Copy") {
                                    selectedIndex = index
                                    performAction()
                                }
                            }
                            .onAppear {
                                // Trigger load more when near the end
                                if shouldLoadMore(at: index) {
                                    onLoadMore()
                                }
                            }
                    }

                    // Loading indicator at bottom
                    if isLoading {
                        loadingIndicator
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: filteredItems.count)
            }
            .scrollIndicators(.automatic)
            .onAppear {
                // Scroll to top when items first appear
                if !filteredItems.isEmpty {
                    withAnimation(.none) {
                        proxy.scrollTo(filteredItems.first?.id, anchor: .top)
                    }
                }
            }
            .onChange(of: selectedIndex) { _, newIndex in
                // Smooth scroll to selected item
                if newIndex < filteredItems.count {
                    let selectedItem = filteredItems[newIndex]
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(selectedItem.id, anchor: .center)
                    }
                }
            }
            .onChange(of: searchText) { _, _ in
                // Reset scroll position when search changes
                if !filteredItems.isEmpty {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(filteredItems.first?.id, anchor: .top)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var loadingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)

            Text("Loading...")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color.clear)
    }

    private func shouldLoadMore(at index: Int) -> Bool {
        // Only trigger load more if:
        // 1. We have more items to load
        // 2. We're not currently loading
        // 3. We're near the end (last 3 items)
        // 4. We have at least 25 items (avoid triggering on small lists)
        return hasMoreItems && !isLoading && index >= filteredItems.count - 3
            && filteredItems.count >= 25
    }
    private func shouldShowPreview(for item: CBItem) -> Bool {
        switch item.itemType {
        case .image, .combined:
            return item.image != nil
        case .file:
            // For files, we preview if it's an image file with a preview, OR if it's just a file (we can open it)
            // Actually, for "Open in Preview", better to stick to images/pdfs that Preview.app handles well.
            // But ActionsBottomButtonView only checked for images.
            // Let's allow opening any file in "Preview" logic if it's an image, or fallback to file opening.
            // But CBViewModel.openInPreview handles generic files too.
            // Let's just return true for .file to allow trying.
            // Wait, ActionsBottomButtonView logic:
            // case .file: return item.isImageFile && item.filePreviewImage != nil
            // Let's match that for "Preview" specifically?
            // Actually, users might want to QuickLook any file.
            // User said "Open with Previewer".
            // Let's stick to safe logic:
            return item.itemType == .image || item.itemType == .combined || item.itemType == .file
        case .text:
            return false
        }
    }
}

#Preview {
    QPItemList(
        filteredItems: [],
        selectedIndex: .constant(0),
        searchText: .constant(""),
        isLoading: false,
        hasMoreItems: true,
        onLoadMore: {},
        performAction: {},
        onOpenPreview: { _ in },
        onOpenTextEdit: { _ in }
    )
}
