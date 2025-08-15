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
}

#Preview {
    QPItemList(
        filteredItems: [],
        selectedIndex: .constant(0),
        searchText: .constant(""),
        isLoading: false,
        hasMoreItems: true,
        onLoadMore: {},
        performAction: {}
    )
}
