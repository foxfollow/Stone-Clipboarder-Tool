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
    /// Optional name the user gives an item (⌥E in the Quick Picker), shown
    /// above its content so similar items are told apart at a glance. Added
    /// in 1.9.0; optional, so existing stores migrate without a version bump.
    var title: String?

    // Categories. All optional or defaulted, so stores migrate lightly.
    /// Keys found by `ContentClassifier`, comma-wrapped: ",link,link.full,code,".
    var categoryKeys: String?
    /// BCP-47 code of the detected language ("uk", "en"); nil when unsure.
    var languageCode: String?
    /// `ContentClassifier.Ruleset.stamp` the keys were computed with; 0 =
    /// never classified. A mismatch makes CBViewModel classify the item again.
    var classificationStamp: Int = 0
    /// The app in front when the item was (last) copied.
    var sourceAppBundleID: String?
    var sourceAppName: String?
    /// Text Vision read in the image (background analysis, or the user's
    /// OCR), so search finds the image by it. Inline, at most
    /// `maxRecognizedTextLength` characters.
    var recognizedText: String?
    /// QR code and barcode contents from the visual pass, apart from the OCR
    /// text so neither overwrites the other. Searched and classified with it.
    var barcodeText: String?
    /// Whether OCR ran on the image: `TextRecognition` values. Kept as an
    /// Int so predicates can test it.
    var textRecognitionState: Int = 0
    /// `ImageClassifier.visualVersion` of the last visual pass (QR codes,
    /// faces, transparency); 0 = none, negative = failed (retried at the
    /// next launch). Kept apart from the rules stamp, so a regex change
    /// doesn't send every image through Vision again.
    var visualAnalysisVersion: Int = 0

    enum TextRecognition {
        static let notRequested = 0
        /// Waiting for the background pass: a new image with automatic OCR on.
        static let pending = 1
        static let noText = 2
        static let found = 3
        /// Waiting for the background pass: queued by "Recognize Text in
        /// All Images"; Stop puts these back to notRequested.
        static let queued = 4
    }

    /// OCR is waiting for the background pass.
    var wantsTextRecognition: Bool {
        textRecognitionState == TextRecognition.pending || textRecognitionState == TextRecognition.queued
    }

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
        self.contentPreview = content.map(Self.preview(of:))

        // Calculate image size and generate thumbnail
        if let imageData = imageData, let image = NSImage(data: imageData) {
            self.imageSize = Self.sizeDescription(image.size)
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
        case .combined:
            let textPart = contentPreview ?? content ?? "No text"
            let imagePart = imageSize ?? calculateImageSize()
            return "\(textPart)\n[Image - \(imagePart)]"
        }
    }

    /// The user's title, trimmed; nil when there is none.
    var displayTitle: String? {
        guard let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    /// Name for a temp copy shown in Quick Look or opened in another app:
    /// the title when there is one, with `fallback`'s extension, otherwise
    /// `fallback` ("Clipboard Text.txt", the original file name, …).
    ///
    /// The extension always comes from `fallback`, never from the title: the
    /// extension picks the app that opens the file, and a title such as
    /// "x.command" must not turn a copied file into something Terminal runs.
    /// A fallback without an extension is therefore kept as it is.
    func exportFileName(fallback: String) -> String {
        guard let title = displayTitle else { return fallback }
        let ext = (fallback as NSString).pathExtension
        guard !ext.isEmpty else { return fallback }

        // "/" and ":" would split or rename the path; keep the name readable.
        var base = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        base = String(base.prefix(Self.exportTitleLength))
            .trimmingCharacters(in: .whitespaces)
        if base.hasPrefix(".") { base = "_" + base }  // not a hidden file

        if (base as NSString).pathExtension.caseInsensitiveCompare(ext) == .orderedSame {
            return base
        }
        return base + "." + ext
    }

    /// Temp file names for the item's text, image and file content.
    var textExportFileName: String { exportFileName(fallback: "Clipboard Text.txt") }
    var imageExportFileName: String { exportFileName(fallback: "Clipboard Image.png") }
    var fileExportFileName: String { exportFileName(fallback: fileName ?? "Clipboard File") }

    /// Room for the extension within the 255-byte name limit, even for
    /// Cyrillic titles (2 bytes per letter in UTF-8).
    static let exportTitleLength = 100

    var image: NSImage? {
        guard (itemType == .image || itemType == .combined), let imageData = imageData else { return nil }
        return NSImage(data: imageData)
    }

    // MARK: - Thumbnails

    /// Decoded thumbnails by item. Rows read `thumbnail` on every render;
    /// decoding `thumbnailData` each time — or, as before, regenerating from
    /// the full image and writing the result into the model mid-render — was
    /// wasted work and dirtied the context. NSCache also sheds entries under
    /// memory pressure.
    private static let thumbnailCache: NSCache<ThumbnailCacheKey, NSImage> = {
        let cache = NSCache<ThumbnailCacheKey, NSImage>()
        cache.countLimit = 500
        return cache
    }()

    /// Drops decoded thumbnails; they are rebuilt from `thumbnailData` on demand.
    static func evictThumbnails(for ids: [PersistentIdentifier]) {
        for id in ids {
            thumbnailCache.removeObject(forKey: ThumbnailCacheKey(id))
        }
    }

    /// Small preview for image-like items (images, text + image, image files);
    /// nil for anything else. Never writes to the model.
    var thumbnail: NSImage? {
        guard itemType == .image || itemType == .combined || isImageFile else { return nil }

        let key = ThumbnailCacheKey(persistentModelID)
        if let cached = Self.thumbnailCache.object(forKey: key) {
            return cached
        }
        let image = makeThumbnail() ?? createPlaceholderThumbnail()
        if let image {
            Self.thumbnailCache.setObject(image, forKey: key)
        }
        return image
    }

    private func makeThumbnail() -> NSImage? {
        if let thumbnailData, let stored = NSImage(data: thumbnailData) {
            return stored
        }
        // No stored thumbnail (older items; memory cleanup before 1.8.0 also
        // deleted them from the store): render one in memory from the source.
        let source = isImageFile ? fileData : imageData
        guard let source, let image = NSImage(data: source) else { return nil }
        return generateThumbnailImage(from: image)
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
        return Self.sizeDescription(image.size)
    }

    /// Stored as PNG: an uncompressed TIFF of the same 80 pt image is several
    /// times larger. (Thumbnails stored as TIFF by older versions still decode.)
    private func generateThumbnail(from image: NSImage) -> Data? {
        return generateThumbnailImage(from: image)?.pngRepresentation
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

    // MARK: - Search

    /// The one matching rule behind every search box: the item's title, the
    /// text of text-like items, the name of files, the "[Image - W×H]" label
    /// of images. Case-insensitive. `query` is expected trimmed and non-empty.
    func matchesSearch(_ query: String, includingImageText: Bool = true) -> Bool {
        if title?.localizedCaseInsensitiveContains(query) == true {
            return true
        }
        if includingImageText,
           recognizedText?.localizedCaseInsensitiveContains(query) == true
            || barcodeText?.localizedCaseInsensitiveContains(query) == true {
            return true
        }
        switch itemType {
        case .text, .combined:
            return content?.localizedCaseInsensitiveContains(query) ?? false
        case .file:
            return fileName?.localizedCaseInsensitiveContains(query) ?? false
        case .image:
            return displayContent.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: - Categories

    var categoryKeySet: Set<String> {
        guard let categoryKeys else { return [] }
        return Set(categoryKeys.split(separator: ",").map(String.init))
    }

    func hasCategoryKey(_ key: String) -> Bool {
        categoryKeys?.contains(",\(key),") ?? false
    }

    /// Images, text + image items and image files: `ImageClassifier` can
    /// look at them. Doesn't load any data.
    var hasAnalyzableImage: Bool {
        itemType == .image || itemType == .combined || isImageFile
    }

    /// The bytes `ImageClassifier` reads (loads external storage).
    var analyzableImageData: Data? {
        switch itemType {
        case .image, .combined: return imageData
        case .file: return isImageFile ? fileData : nil
        case .text: return nil
        }
    }

    /// Classifies the item with `ruleset` and stamps it, so the next rescan
    /// skips it. All image bookkeeping lives here:
    /// - text of text-like items through `ContentClassifier`;
    /// - the visual pass (QR codes, faces, transparency): `image`'s keys and
    ///   payloads when it ran; otherwise earlier visual keys are kept while
    ///   "Analyze images" is on and dropped when it's off;
    ///   `visualAnalysisVersion` follows (see `visualTarget(for:)`);
    /// - OCR: `image`'s text replaces `recognizedText` when it ran;
    /// - the stored image text and payloads through the same detectors as
    ///   copied text, minus "entire text" keys.
    /// A failed Vision request (`failedVisual` / `failedText`) changes
    /// nothing of its part and marks it for a retry at the next launch.
    func classify(with ruleset: ContentClassifier.Ruleset, image: ImageClassifier.Result? = nil) {
        var keys = Set<String>()
        var language: String?
        if itemType == .text || itemType == .combined, let content {
            let result = ContentClassifier.classify(content, ruleset: ruleset)
            keys = result.keys
            language = result.language
        }

        if hasAnalyzableImage {
            let earlierVisualKeys = categoryKeySet.intersection(ImageClassifier.visualKeys)
            if let image, image.ranVisual {
                keys.formUnion(image.keys)
                barcodeText = image.payloads.isEmpty ? nil : image.payloads.joined(separator: "\n")
                visualAnalysisVersion = ImageClassifier.visualVersion
            } else if let image, image.failedVisual {
                keys.formUnion(earlierVisualKeys)
                visualAnalysisVersion = -ImageClassifier.visualVersion
            } else if ruleset.analyzeImages {
                keys.formUnion(earlierVisualKeys)
            } else {
                barcodeText = nil
                visualAnalysisVersion = 0
            }

            if let text = image?.recognizedText {
                setRecognizedText(text)
                textRecognitionState = image?.foundText == true ? TextRecognition.found : TextRecognition.noText
            } else if image?.failedText == true {
                textRecognitionState = TextRecognition.notRequested
            }
            if textRecognitionState == TextRecognition.found {
                keys.insert(ItemCategory.BuiltIn.ocr.rawValue)
            }

            let imageText = [recognizedText, barcodeText].compactMap { $0 }.joined(separator: "\n")
            if !imageText.isEmpty {
                let found = ContentClassifier.classify(imageText, ruleset: ruleset)
                keys.formUnion(found.keys.filter { !$0.hasSuffix(".full") })
                language = language ?? found.language
            }
        } else {
            visualAnalysisVersion = Self.visualTarget(for: ruleset)
            // Waiting for OCR without an image to read: done.
            if wantsTextRecognition { textRecognitionState = TextRecognition.noText }
        }

        categoryKeys = Self.encodeKeys(keys)
        languageCode = language
        classificationStamp = ruleset.stamp
    }

    /// `visualAnalysisVersion` an up-to-date item has: the current visual
    /// version while "Analyze images" is on, 0 while it's off. Items
    /// without an image get it at once; images after their pass.
    static func visualTarget(for ruleset: ContentClassifier.Ruleset) -> Int {
        ruleset.analyzeImages ? ImageClassifier.visualVersion : 0
    }

    /// The visual pass is due: on, an image, and not done (or failed) for
    /// the current version.
    func needsVisualPass(_ ruleset: ContentClassifier.Ruleset) -> Bool {
        ruleset.analyzeImages && hasAnalyzableImage
            && visualAnalysisVersion != ImageClassifier.visualVersion
            && visualAnalysisVersion != -ImageClassifier.visualVersion
    }

    static func encodeKeys(_ keys: Set<String>) -> String? {
        keys.isEmpty ? nil : "," + keys.sorted().joined(separator: ",") + ","
    }

    static let maxRecognizedTextLength = 10_000

    /// Trimmed and capped; empty clears it.
    func setRecognizedText(_ text: String?) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        recognizedText = trimmed.isEmpty ? nil : String(trimmed.prefix(Self.maxRecognizedTextLength))
    }

    /// The recognized text on one line, for a row.
    var recognizedTextSnippet: String? {
        let text = [recognizedText, barcodeText].compactMap { $0 }.joined(separator: "\n")
        guard !text.isEmpty else { return nil }
        return text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    // MARK: - Deduplication

    /// `contentPreview` holds this many leading characters of `content`.
    static let previewLength = 100

    static func preview(of content: String) -> String {
        String(content.prefix(previewLength))
    }

    /// The "W×H" text stored in `imageSize` (points, as NSImage reports it).
    static func sizeDescription(_ size: NSSize) -> String {
        "\(Int(size.width))×\(Int(size.height))"
    }

    static func imageSizeDescription(for data: Data) -> String? {
        NSImage(data: data).map { sizeDescription($0.size) }
    }

    /// The content an item is deduplicated on, plus the inline columns that
    /// narrow a store lookup before any external data has to be loaded.
    struct ContentKey {
        let type: CBItemType
        let content: String?
        let imageData: Data?
        let fileData: Data?
        let fileName: String?
        /// Matches `contentPreview` of an item with the same text.
        let preview: String?
        /// Matches `imageSize` of an item with the same image.
        let imageSize: String?

        init(
            type: CBItemType, content: String? = nil, imageData: Data? = nil,
            fileData: Data? = nil, fileName: String? = nil
        ) {
            self.type = type
            self.content = content
            self.imageData = imageData
            self.fileData = fileData
            self.fileName = fileName
            self.preview = content.map(CBItem.preview(of:))
            self.imageSize = imageData.flatMap(CBItem.imageSizeDescription(for:))
        }
    }

    func hasSameContent(as key: ContentKey) -> Bool {
        guard itemType == key.type else { return false }

        switch itemType {
        case .text:
            return content == key.content
        case .image:
            return imageData == key.imageData
        case .file:
            return fileData == key.fileData && fileName == key.fileName
        case .combined:
            return content == key.content && imageData == key.imageData
        }
    }

    func isDuplicate(of other: CBItem) -> Bool {
        hasSameContent(as: ContentKey(
            type: other.itemType, content: other.content, imageData: other.imageData,
            fileData: other.fileData, fileName: other.fileName))
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

/// NSCache needs an object key; hashes and compares the item's identifier.
private final class ThumbnailCacheKey: NSObject {
    let id: PersistentIdentifier

    init(_ id: PersistentIdentifier) {
        self.id = id
    }

    override var hash: Int { id.hashValue }

    override func isEqual(_ object: Any?) -> Bool {
        (object as? ThumbnailCacheKey)?.id == id
    }
}
