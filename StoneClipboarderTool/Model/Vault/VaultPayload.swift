//
//  VaultPayload.swift
//  StoneClipboarderTool
//
//  One item of the Passwords vault, as it is sealed into its file.
//

import Foundation

/// The whole content of one vault entry. It is encoded as JSON and sealed
/// with AES-GCM (`VaultCrypto`); nothing of it is stored in plaintext.
///
/// A payload is a value, never a `CBItem`: vault content must not reach the
/// history store, categories, OCR, pins, Quick Look temp files or the log.
struct VaultPayload: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var itemType: CBItemType
    /// The name the user gave the entry; shown instead of the masked content.
    var title: String?
    var content: String?
    var imageData: Data?
    var fileData: Data?
    var fileName: String?
    var fileUTI: String?
    var createdAt: Date
    /// Place in the Passwords list, 0 = first.
    var orderIndex: Int

    init(
        id: UUID = UUID(),
        itemType: CBItemType,
        title: String? = nil,
        content: String? = nil,
        imageData: Data? = nil,
        fileData: Data? = nil,
        fileName: String? = nil,
        fileUTI: String? = nil,
        createdAt: Date = Date(),
        orderIndex: Int = 0
    ) {
        self.id = id
        self.itemType = itemType
        self.title = title
        self.content = content
        self.imageData = imageData
        self.fileData = fileData
        self.fileName = fileName
        self.fileUTI = fileUTI
        self.createdAt = createdAt
        self.orderIndex = orderIndex
    }

    /// Copies a history item's content and title. Returns nil when the item
    /// has nothing to keep (empty text, missing image or file data).
    init?(item: CBItem, id: UUID = UUID(), createdAt: Date = Date(), orderIndex: Int = 0) {
        let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            id: id,
            itemType: item.itemType,
            title: (title?.isEmpty ?? true) ? nil : title,
            content: item.content,
            imageData: item.imageData,
            fileData: item.fileData,
            fileName: item.fileName,
            fileUTI: item.fileUTI,
            createdAt: createdAt,
            orderIndex: orderIndex)
        guard hasContent else { return nil }
    }

    /// Whether there is something to paste, by type.
    var hasContent: Bool {
        switch itemType {
        case .text:
            return content?.isEmpty == false
        case .image:
            return imageData?.isEmpty == false
        case .file:
            return fileData != nil && fileName?.isEmpty == false
        case .combined:
            return content?.isEmpty == false || imageData?.isEmpty == false
        }
    }

    /// Same rules as `CBItem.hasSameContent`: the title doesn't count.
    func hasSameContent(as other: VaultPayload) -> Bool {
        guard itemType == other.itemType else { return false }
        switch itemType {
        case .text:
            return content == other.content
        case .image:
            return imageData == other.imageData
        case .file:
            return fileData == other.fileData && fileName == other.fileName
        case .combined:
            return content == other.content && imageData == other.imageData
        }
    }

    /// Text that can be typed out (⌘⇧⏎): text and combined items only.
    var typeableText: String? {
        guard itemType == .text || itemType == .combined, let content, !content.isEmpty else { return nil }
        return content
    }

    /// The name the list shows: the title, else a description that doesn't
    /// reveal text content.
    var displayName: String {
        if let title, !title.isEmpty { return title }
        switch itemType {
        case .text, .combined:
            return "Password"
        case .image:
            return "Image"
        case .file:
            return fileName ?? "File"
        }
    }

    /// Search matches the title, the file name and, for text, the content
    /// itself (case-insensitive), so a remembered fragment finds the entry.
    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return [title, fileName, content].contains { field in
            field?.localizedCaseInsensitiveContains(needle) == true
        }
    }

    /// The first payload in `entries` with the same content, if any.
    static func duplicate(of payload: VaultPayload, in entries: [VaultPayload]) -> VaultPayload? {
        entries.first { $0.id != payload.id && $0.hasSameContent(as: payload) }
    }

    /// Sorted for display: `orderIndex`, then the older entry first.
    static func sorted(_ entries: [VaultPayload]) -> [VaultPayload] {
        entries.sorted {
            ($0.orderIndex, $0.createdAt.timeIntervalSinceReferenceDate)
                < ($1.orderIndex, $1.createdAt.timeIntervalSinceReferenceDate)
        }
    }
}
