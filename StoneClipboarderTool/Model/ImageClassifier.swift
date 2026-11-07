//
//  ImageClassifier.swift
//  StoneClipboarderTool
//

import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Categories of an image, found with Vision on the device: readable text
/// (`ocr`), QR codes and barcodes (`barcode`), faces (`face`) and
/// transparent areas (`transparent`). The recognized text and barcode
/// payloads then go through `ContentClassifier`, so a screenshot of a link,
/// an email or a document number lands in those categories too, and gets a
/// language.
///
/// Synchronous and CPU-heavy (≈0.2–1 s per image): call it off the main
/// thread. Never logs what it reads.
enum ImageClassifier {
    /// Images are scaled down to this many pixels on the long side first.
    static let maxPixelSize = 2048
    /// Fewer recognized characters than this don't count as "text in image".
    static let minTextLength = 3
    static let minTextConfidence: Float = 0.4

    struct Result: Equatable {
        var keys: Set<String> = []
        var language: String?
    }

    static func classify(_ data: Data, ruleset: ContentClassifier.Ruleset = .empty) -> Result {
        guard let image = downscaledImage(from: data) else { return Result() }

        var keys = Set<String>()
        if hasTransparency(image) { keys.insert(ItemCategory.BuiltIn.transparent.rawValue) }

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.automaticallyDetectsLanguage = true
        let barcodeRequest = VNDetectBarcodesRequest()
        let faceRequest = VNDetectFaceRectanglesRequest()

        do {
            try VNImageRequestHandler(cgImage: image, options: [:])
                .perform([textRequest, barcodeRequest, faceRequest])
        } catch {
            ErrorLogger.shared.log("Failed to analyze an image", category: "Categories", error: error)
            return Result(keys: keys)
        }

        let lines = (textRequest.results ?? []).compactMap { observation -> String? in
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= minTextConfidence else { return nil }
            return candidate.string
        }
        let recognized = lines.joined(separator: "\n")
        if recognized.filter({ $0.isLetter || $0.isNumber }).count >= minTextLength {
            keys.insert(ItemCategory.BuiltIn.ocr.rawValue)
        }

        let payloads = (barcodeRequest.results ?? []).compactMap(\.payloadStringValue)
        if !(barcodeRequest.results ?? []).isEmpty {
            keys.insert(ItemCategory.BuiltIn.barcode.rawValue)
        }

        if !(faceRequest.results ?? []).isEmpty {
            keys.insert(ItemCategory.BuiltIn.face.rawValue)
        }

        // The text the image carries, through the same detectors as copied
        // text. "Entire text" makes no sense for a picture, so drop .full.
        let text = ([recognized] + payloads).filter { !$0.isEmpty }.joined(separator: "\n")
        var language: String?
        if !text.isEmpty {
            let found = ContentClassifier.classify(text, ruleset: ruleset)
            keys.formUnion(found.keys.filter { !$0.hasSuffix(".full") })
            language = found.language
        }
        return Result(keys: keys, language: language)
    }

    /// Decodes at most `maxPixelSize` on the long side, honoring EXIF
    /// orientation. nil when the data isn't an image.
    static func downscaledImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// True when some pixel is noticeably see-through. Checks a 64×64
    /// rendition, enough for icons and cut-outs.
    static func hasTransparency(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        let side = 64
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.clear(CGRect(x: 0, y: 0, width: side, height: side))
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return false }
        return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] < 250 }
    }
}
