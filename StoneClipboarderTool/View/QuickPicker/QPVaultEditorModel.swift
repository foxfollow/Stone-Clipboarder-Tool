//
//  QPVaultEditorModel.swift
//  StoneClipboarderTool
//

import SwiftUI

/// State behind ⌥E on the Passwords tab: rename, move and delete one entry.
/// Changes go through VaultManager; the view reads only these fields.
@MainActor
final class QPVaultEditorModel: ObservableObject {
    let entryID: UUID
    let typeSymbol: String
    let typeColor: Color
    let kindDescription: String

    @Published var title: String
    @Published private(set) var position: Int?
    @Published private(set) var count: Int
    /// Deleting asks first.
    @Published var isConfirmingDelete = false
    /// The row's icon; nil = the type's.
    @Published var icon: CategoryIcon?
    @Published var color: Color
    /// The picker popover.
    @Published var isPickingIcon = false

    /// The eye (⌥R): the content shows in the card.
    @Published var isRevealed = false
    /// What the eye shows; text and image copied once from the entry.
    let revealText: String?
    let revealImageData: Data?

    private let vaultManager: VaultManager

    init(entry: VaultPayload, vaultManager: VaultManager) {
        self.vaultManager = vaultManager
        entryID = entry.id
        typeSymbol = entry.itemType == .text ? "key.horizontal.fill" : entry.itemType.sfSybmolName
        typeColor = entry.itemType.sybmolColor
        switch entry.itemType {
        case .text: kindDescription = "Text"
        case .image: kindDescription = "Image"
        case .file: kindDescription = entry.fileName ?? "File"
        case .combined: kindDescription = "Text and image"
        }
        title = entry.title ?? ""
        icon = entry.icon
        color = entry.colorHex.flatMap(ItemCategory.nsColor(hex:)).map { Color(nsColor: $0) }
            ?? entry.itemType.sybmolColor
        revealText = entry.content
        revealImageData = entry.imageData
        position = nil
        count = 0
        refresh()
    }

    var canMoveUp: Bool { (position ?? 0) > 0 }
    var canMoveDown: Bool {
        guard let position else { return false }
        return position < count - 1
    }

    /// The default the icon picker starts from.
    var iconForPicker: CategoryIcon {
        icon ?? .symbol(typeSymbol)
    }

    /// Title, icon and color (⏎ / Save).
    func save() {
        vaultManager.rename(entryID, to: title)
        vaultManager.setAppearance(entryID, icon: icon, colorHex: icon == nil ? nil : ItemCategory.hex(from: color))
    }

    func resetAppearance() {
        icon = nil
        color = typeColor
    }

    func move(by offset: Int) {
        vaultManager.move(entryID, by: offset)
        refresh()
    }

    /// True when the entry is gone and the editor should close.
    func confirmDelete() -> Bool {
        isConfirmingDelete = false
        return vaultManager.delete(entryID)
    }

    private func refresh() {
        count = vaultManager.entries.count
        position = vaultManager.entries.firstIndex { $0.id == entryID }
    }
}
