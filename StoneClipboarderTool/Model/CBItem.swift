//
//  CBItem.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum CBItemType: String, Codable, CaseIterable {
    case text = "text"
    case image = "image"
    case file = "file"

    var sfSybmolName: String {
        switch self {
        case .text: return "text.page"
        case .image: return "photo"
        case .file: return "document.badge.ellipsis"
        }
    }

    var sybmolColor: Color {
        switch self {
        case .text: return .blue
        case .image: return .orange
        case .file: return .pink
        }
    }
}

@Model
final class CBItem {
    var timestamp: Date
    @Attribute(.externalStorage) var content: String?
    @Attribute(.externalStorage) var imageData: Data?
    @Attribute(.externalStorage) var fileData: Data?
    var fileName: String?
    var fileUTI: String?
    var itemType: CBItemType
    var isFavorite: Bool = false
    var orderIndex: Int = 0

    // Lightweight preview content for UI performance
    var contentPreview: String?
    var imageSize: String?
    var fileSize: Int64 = 0

    // Thumbnail for memory-efficient UI display
    @Attribute(.externalStorage) var thumbnailData: Data?

    init(
        timestamp: Date,
        content: String? = nil,
        imageData: Data? = nil,
        fileData: Data? = nil,
        fileName: String? = nil,
        fileUTI: String? = nil,
        itemType: CBItemType = .text,
        isFavorite: Bool = false,
        orderIndex: Int = 0
    ) {
        self.timestamp = timestamp
        self.content = content
        self.imageData = imageData
        self.fileData = fileData
        self.fileName = fileName
        self.fileUTI = fileUTI
        self.itemType = itemType
        self.isFavorite = isFavorite
        self.orderIndex = orderIndex

        // Generate lightweight previews
        self.contentPreview = content?.prefix(100).description

        // Calculate image size and generate thumbnail
        if let imageData = imageData, let image = NSImage(data: imageData) {
            let size = image.size
            self.imageSize = "\(Int(size.width))×\(Int(size.height))"
            self.thumbnailData = generateThumbnail(from: image)
        }

        // Calculate file size
        if let fileData = fileData {
            self.fileSize = Int64(fileData.count)

            // Generate thumbnail for image files
            if let uti = fileUTI, UTType(uti)?.conforms(to: .image) == true,
                let image = NSImage(data: fileData)
            {
                self.thumbnailData = generateThumbnail(from: image)
            }
        }
    }

    var displayContent: String {
        switch itemType {
        case .text:
            return contentPreview ?? content ?? "Empty text"
        case .image:
            return "[Image - \(imageSize ?? calculateImageSize())]"
        case .file:
            if isImageFile {
                return "[FileImage - \(fileName ?? "Unknown") (\(fileSizeString))]"
            }
            return "[File - \(fileName ?? "Unknown") (\(fileSizeString))]"
        }
    }

    var image: NSImage? {
        guard itemType == .image, let imageData = imageData else { return nil }
        return NSImage(data: imageData)
    }

    // Memory-efficient thumbnail for UI display
    var thumbnail: NSImage? {
        // First check if we have cached thumbnail
        if let thumbnailData = thumbnailData,
            let cachedThumbnail = NSImage(data: thumbnailData)
        {
            return cachedThumbnail
        }

        // Generate thumbnail on-demand for images
        if itemType == .image {
            if let imageData = imageData,
                let image = NSImage(data: imageData)
            {
                let thumbnail = generateThumbnailImage(from: image)
                // Cache the generated thumbnail immediately
                if let thumbnail = thumbnail,
                    let pngData = thumbnail.pngRepresentation
                {
                    self.thumbnailData = pngData
                }
                return thumbnail ?? createPlaceholderThumbnail()
            }
        }
        // Generate thumbnail for image files
        else if isImageFile {
            if let fileData = fileData,
                let image = NSImage(data: fileData)
            {
                let thumbnail = generateThumbnailImage(from: image)
                // Cache the generated thumbnail immediately
                if let thumbnail = thumbnail,
                    let pngData = thumbnail.pngRepresentation
                {
                    self.thumbnailData = pngData
                }
                return thumbnail ?? createPlaceholderThumbnail()
            }
        }

        // Return placeholder for failed generation
        return createPlaceholderThumbnail()
    }

    private func createPlaceholderThumbnail() -> NSImage? {
        let size = NSSize(width: 100, height: 100)
        let image = NSImage(size: size)

        image.lockFocus()

        // Draw background
        NSColor.systemGray.setFill()
        NSRect(origin: .zero, size: size).fill()

        // Draw icon
        let iconSize: CGFloat = 40
        let iconOrigin = NSPoint(
            x: (size.width - iconSize) / 2,
            y: (size.height - iconSize) / 2
        )
        let iconRect = NSRect(
            origin: iconOrigin, size: NSSize(width: iconSize, height: iconSize))

        let iconName = itemType == .image ? "photo" : "doc.richtext"
        if let systemImage = NSImage(
            systemSymbolName: iconName, accessibilityDescription: nil)
        {
            systemImage.draw(in: iconRect)
        }

        image.unlockFocus()
        return image
    }

    var isImageFile: Bool {
        guard itemType == .file, let uti = fileUTI else { return false }
        return UTType(uti)?.conforms(to: .image) ?? false
    }

    var filePreviewImage: NSImage? {
        if isImageFile, let fileData = fileData {
            return NSImage(data: fileData)
        }
        return fileIcon
    }

    var fileIcon: NSImage? {
        guard let fileName = fileName else {
            return NSWorkspace.shared.icon(for: UTType.data)
        }

        let fileURL = URL(fileURLWithPath: fileName)
        let pathExtension = fileURL.pathExtension

        if let utType = UTType(filenameExtension: pathExtension) {
            return NSWorkspace.shared.icon(for: utType)
        } else {
            return NSWorkspace.shared.icon(for: UTType.data)
        }
    }

    private var fileSizeString: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(
            fromByteCount: fileSize > 0 ? fileSize : Int64(fileData?.count ?? 0))
    }

    private func calculateImageSize() -> String {
        if let cached = imageSize {
            return cached
        }

        guard let image = self.image else { return "Unknown size" }
        let size = image.size
        return "\(Int(size.width))×\(Int(size.height))"
    }

    private func generateThumbnail(from image: NSImage) -> Data? {
        return generateThumbnailImage(from: image)?.tiffRepresentation
    }

    private func generateThumbnailImage(from image: NSImage) -> NSImage? {
        let maxSize: CGFloat = 80
        let imageSize = image.size

        // Ensure we have valid dimensions
        guard imageSize.width > 0 && imageSize.height > 0 else {
            return nil
        }

        // Calculate thumbnail size maintaining aspect ratio
        let aspectRatio = imageSize.width / imageSize.height
        var thumbnailSize: NSSize

        if aspectRatio > 1 {
            thumbnailSize = NSSize(width: maxSize, height: maxSize / aspectRatio)
        } else {
            thumbnailSize = NSSize(width: maxSize * aspectRatio, height: maxSize)
        }

        // Create high-quality thumbnail
        let thumbnail = NSImage(size: thumbnailSize)
        thumbnail.lockFocus()

        // Use high-quality interpolation
        NSGraphicsContext.current?.imageInterpolation = .high

        image.draw(
            in: NSRect(origin: .zero, size: thumbnailSize),
            from: NSRect(origin: .zero, size: imageSize),
            operation: .copy,
            fraction: 1.0)

        thumbnail.unlockFocus()
        return thumbnail
    }

    func isDuplicate(of other: CBItem) -> Bool {
        guard itemType == other.itemType else { return false }

        switch itemType {
        case .text:
            return content == other.content
        case .image:
            return imageData == other.imageData
        case .file:
            return fileData == other.fileData && fileName == other.fileName
        }
    }

    static func findExistingItem(in items: [CBItem], matching newItem: CBItem) -> CBItem? {
        return items.first { existingItem in
            newItem.isDuplicate(of: existingItem)
        }
    }
}

extension NSImage {
    var pngRepresentation: Data? {
        guard let tiffData = self.tiffRepresentation,
            let bitmapRep = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return bitmapRep.representation(using: .png, properties: [:])
    }
}
