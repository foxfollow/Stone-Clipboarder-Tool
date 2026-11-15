//
//  QPItemEditorModel.swift
//  StoneClipboarderTool
//

import SwiftData
import SwiftUI

/// State behind the Quick Picker's ⌥E editor: the item's title, its favorite
/// flag, its place among the favorites, and Move to Passwords (⌥K).
///
/// The editor view renders only the snapshot fields copied here, never the
/// `CBItem`, so a deletion while the editor is open can't crash a render. The
/// Quick Picker closes the editor on `.clipboardItemDeleted`; the item is
/// touched only from user actions before that.
@MainActor
final class QPItemEditorModel: ObservableObject {
    let itemID: PersistentIdentifier
    let preview: String
    let typeSymbol: String
    let typeColor: Color

    @Published var title: String
    @Published private(set) var isFavorite: Bool
    /// 0-based place in the favorites order; nil when not a favorite.
    @Published private(set) var favoritePosition: Int?
    @Published private(set) var favoriteCount: Int
    /// Removing a favorite asks first: a non-favorite can be cleaned up.
    @Published var isConfirmingUnfavorite = false
    /// Deleting the item asks first (⌃⌥⌫ or Delete…; ⏎ confirms).
    @Published var isConfirmingDelete = false
    /// Why "Move to Passwords" didn't go through, if it didn't.
    @Published var vaultMessage: String?
    /// True while Move to Passwords waits for Touch ID.
    @Published var isMovingToVault = false

    private let item: CBItem
    private let viewModel: CBViewModel
    /// Lets the Quick Picker re-read its list after a favorite change.
    private let onFavoritesChanged: () -> Void

    init(item: CBItem, viewModel: CBViewModel, onFavoritesChanged: @escaping () -> Void) {
        self.item = item
        self.viewModel = viewModel
        self.onFavoritesChanged = onFavoritesChanged
        itemID = item.persistentModelID
        preview = item.displayContent
        typeSymbol = item.itemType.sfSybmolName
        typeColor = item.itemType.sybmolColor
        title = item.title ?? ""
        isFavorite = item.isFavorite
        favoritePosition = nil
        favoriteCount = 0
        refreshFavoriteState()
    }

    var canMoveUp: Bool { (favoritePosition ?? 0) > 0 }
    var canMoveDown: Bool {
        guard let favoritePosition else { return false }
        return favoritePosition < favoriteCount - 1
    }

    func saveTitle() {
        viewModel.setTitle(item, to: title)
    }

    func moveFavorite(by offset: Int) {
        guard isFavorite else { return }
        viewModel.moveFavorite(item, by: offset)
        refreshFavoriteState()
        onFavoritesChanged()
    }

    /// Adds right away; removing goes through `isConfirmingUnfavorite`.
    func requestFavoriteToggle() {
        if isFavorite {
            isConfirmingUnfavorite = true
        } else {
            viewModel.toggleFavorite(item)
            refreshFavoriteState()
            onFavoritesChanged()
        }
    }

    /// Asks to delete the item; a second request only asks again.
    func requestDelete() {
        isConfirmingUnfavorite = false
        isConfirmingDelete = true
    }

    /// Deletes the item from the history (two steps, like every delete).
    /// The Quick Picker closes the editor on the deletion it announces.
    func confirmDelete() {
        guard isConfirmingDelete else { return }
        isConfirmingDelete = false
        viewModel.deleteItem(item)
    }

    func confirmUnfavorite() {
        isConfirmingUnfavorite = false
        guard isFavorite else { return }
        viewModel.toggleFavorite(item)
        refreshFavoriteState()
        onFavoritesChanged()
    }

    private func refreshFavoriteState() {
        let favorites = viewModel.favoriteItems
        isFavorite = item.isFavorite
        favoriteCount = favorites.count
        favoritePosition = favorites.firstIndex { $0.persistentModelID == itemID }
    }
}
