//
//  CBItem.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import SwiftUI
import SwiftData
import AppKit
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
    var content: String?
    var imageData: Data?
    var fileData: Data?
    var fileName: String?
    var fileUTI: String? // Uniform Type Identifier
    var itemType: CBItemType
    var isFavorite: Bool = false
    var orderIndex: Int = 0

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
    }

    var displayContent: String {
        switch itemType {
        case .text:
            return content ?? "Empty text"
        case .image:
            return "[Image - \(imageSize)]"
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

    // Check if file is an image based on UTI
    var isImageFile: Bool {
        guard itemType == .file, let uti = fileUTI else { return false }
        return UTType(uti)?.conforms(to: .image) ?? false
    }

    // Get file image for display (either the file content if it's an image, or a file icon)
    var filePreviewImage: NSImage? {
        if isImageFile, let fileData = fileData {
            return NSImage(data: fileData)
        }
        return fileIcon
    }

    // Get appropriate file icon based on UTI
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

    private var imageSize: String {
        guard let image = image else { return "Unknown size" }
        let size = image.size
        return "\(Int(size.width))×\(Int(size.height))"
    }

    private var fileSizeString: String {
        guard let fileData = fileData else { return "Unknown size" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(fileData.count))
    }
}
