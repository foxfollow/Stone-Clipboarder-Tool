//
//  PinnedItemConfig.swift
//  StoneClipboarderTool
//

import Foundation
import SwiftData

/// Persisted state for one pinned clipboard item. Lives in the *settings*
/// container so it survives a clipboard-history wipe — the snapshot below
/// (content/imageData/fileData) lets the pin keep rendering even if its
/// source CBItem is later deleted.
@Model
final class PinnedItemConfig {
    @Attribute(.unique) var id: UUID

    // Content snapshot (independent of CBItem). Mirrors CBItem's storage so a
    // pin can re-render after the source is gone.
    var itemTypeRaw: String
    @Attribute(.externalStorage) var content: String?
    @Attribute(.externalStorage) var imageData: Data?
    @Attribute(.externalStorage) var fileData: Data?
    var fileName: String?
    var fileUTI: String?

    // Layout (screen coordinates, Cocoa: origin bottom-left)
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    // Height before collapse, restored on expand.
    var expandedHeight: Double

    // Behavior (per-pin overrides of the global defaults at creation time)
    var opacity: Double
    var isLocked: Bool
    var isClickThrough: Bool
    var isCollapsed: Bool
    var imageZoom: Double

    // Timestamp of the source CBItem when it was pinned. Informational: the
    // link back to the history (pin badge, closing on delete) is made by
    // content — see `contentKey` and PinManager.restorePersistedPins.
    var sourceTimestamp: Date?

    var createdAt: Date

    init(
        id: UUID = UUID(),
        itemType: CBItemType,
        content: String? = nil,
        imageData: Data? = nil,
        fileData: Data? = nil,
        fileName: String? = nil,
        fileUTI: String? = nil,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        opacity: Double = 1.0,
        isLocked: Bool = false,
        isClickThrough: Bool = false,
        isCollapsed: Bool = false,
        imageZoom: Double = 1.0,
        sourceTimestamp: Date? = nil
    ) {
        self.id = id
        self.itemTypeRaw = itemType.rawValue
        self.content = content
        self.imageData = imageData
        self.fileData = fileData
        self.fileName = fileName
        self.fileUTI = fileUTI
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.expandedHeight = height
        self.opacity = opacity
        self.isLocked = isLocked
        self.isClickThrough = isClickThrough
        self.isCollapsed = isCollapsed
        self.imageZoom = imageZoom
        self.sourceTimestamp = sourceTimestamp
        self.createdAt = Date()
    }

    var itemType: CBItemType {
        CBItemType(rawValue: itemTypeRaw) ?? .text
    }

    var frame: NSRect {
        NSRect(x: x, y: y, width: width, height: height)
    }

    /// The snapshot as a dedup key, to find the history item it came from.
    /// Reads external-storage fields: call outside SwiftUI body evaluation.
    var contentKey: CBItem.ContentKey {
        CBItem.ContentKey(
            type: itemType, content: content, imageData: imageData,
            fileData: fileData, fileName: fileName)
    }
}
