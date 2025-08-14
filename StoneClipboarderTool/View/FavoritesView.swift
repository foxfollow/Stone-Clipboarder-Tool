//
//  FavoritesView.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 13.08.2025.
//

import SwiftUI
import SwiftData

struct FavoritesView: View {
    @EnvironmentObject var cbViewModel: CBViewModel
    @State private var showingDeleteAllAlert = false
    @State private var draggedItem: CBItem?

    var body: some View {
        NavigationView {
            VStack {
                if cbViewModel.favoriteItems.isEmpty {
                    emptyStateView
                } else {
                    favoriteItemsList
                }
            }
            .navigationTitle("Favorites")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if !cbViewModel.favoriteItems.isEmpty {
                        Button("Clear All", role: .destructive) {
                            showingDeleteAllAlert = true
                        }
                    }
                }
            }
            .alert("Clear All Favorites", isPresented: $showingDeleteAllAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Clear All", role: .destructive) {
                    cbViewModel.deleteAllFavorites()
                }
            } message: {
                Text("This will remove all items from favorites. The items will remain in your clipboard history.")
            }
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Favorites", systemImage: "heart")
        } description: {
            Text("Add items to favorites by tapping the heart icon")
        }
    }

    @ViewBuilder
    private var favoriteItemsList: some View {
        List {
            ForEach(cbViewModel.favoriteItems, id: \.id) { item in
                FavoriteItemRow(item: item, draggedItem: $draggedItem)
                    .onDrag {
                        draggedItem = item
                        return NSItemProvider(object: "\(item.id)" as NSString)
                    }
                    .onDrop(of: [.text], delegate: FavoriteDropDelegate(
                        item: item,
                        favoriteItems: cbViewModel.favoriteItems,
                        draggedItem: $draggedItem,
                        cbViewModel: cbViewModel
                    ))
            }
        }
        .listStyle(.inset)
    }
}

struct FavoriteItemRow: View {
    let item: CBItem
    @Binding var draggedItem: CBItem?
    @EnvironmentObject var cbViewModel: CBViewModel
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
                .opacity(isHovered ? 1.0 : 0.3)

            // Type icon
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 20)

            // Preview
            Group {
                if item.itemType == .image {
                    if let image = item.image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: 40, maxHeight: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.3))
                            .frame(maxWidth: 40, maxHeight: 30)
                    }
                } else if item.itemType == .file && item.isImageFile {
                    if let image = item.filePreviewImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: 40, maxHeight: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.3))
                            .frame(maxWidth: 40, maxHeight: 30)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(iconColor.opacity(0.1))
                        .frame(maxWidth: 40, maxHeight: 30)
                        .overlay {
                            Image(systemName: iconName)
                                .font(.system(size: 12))
                                .foregroundStyle(iconColor)
                        }
                }
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayContent)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)

                HStack {
                    Text("Position: \(item.orderIndex + 1)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(item.timestamp, style: .relative)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Actions
            HStack {
                Button(action: {
                    cbViewModel.copyAndUpdateItem(item)
                }) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 14))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")

                Button(action: {
                    cbViewModel.toggleFavorite(item)
                }) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Remove from favorites")
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(draggedItem?.id == item.id ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }

    private var iconName: String {
        item.itemType.sfSybmolName
    }

    private var iconColor: Color {
        item.itemType.sybmolColor
    }
}

struct FavoriteDropDelegate: DropDelegate {
    let item: CBItem
    let favoriteItems: [CBItem]
    @Binding var draggedItem: CBItem?
    let cbViewModel: CBViewModel

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem else { return }
        guard draggedItem.id != item.id else { return }

        let fromIndex = favoriteItems.firstIndex { $0.id == draggedItem.id } ?? 0
        let toIndex = favoriteItems.firstIndex { $0.id == item.id } ?? 0

        if fromIndex != toIndex {
            withAnimation(.default) {
                var newFavorites = favoriteItems
                newFavorites.move(fromOffsets: IndexSet([fromIndex]), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
                cbViewModel.updateFavoriteOrder(newFavorites)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

#Preview {
    let viewModel = CBViewModel()

    FavoritesView()
        .environmentObject(viewModel)
}
