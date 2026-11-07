//
//  ImageClassifier.swift
//  StoneClipboarderTool
//

import CoreGraphics
import Foundation
import ImageIO
import Vision

/// What Vision sees in an image, on the device. Two independent parts:
///
/// - the visual pass (`analyzeVisual`): QR codes and barcodes (`barcode`,
///   with their payloads), faces (`face`), transparent areas
///   (`transparent`); fairly cheap;
/// - text recognition (`recognizeText`, OCR): the expensive part. It runs
///   once per image; `CBItem` keeps the text, so later rescans (a new
///   regex rule…) reuse it instead of reading the image again.
///
/// Synchronous and CPU-heavy: call it off the main thread. Never logs what
/// it reads.
enum ImageClassifier {
    /// Images are scaled down to this many pixels on the long side first.
    static let maxPixelSize = 2048
    /// Fewer recognized characters than this don't count as "text in image".
    static let minTextLength = 3
    static let minTextConfidence: Float = 0.4

    /// Keys only the visual pass produces.
    static let visualKeys: Set<String> = [
        ItemCategory.BuiltIn.barcode.rawValue, ItemCategory.BuiltIn.face.rawValue,
        ItemCategory.BuiltIn.transparent.rawValue,
    ]

    struct Result: Equatable {
        /// Visual keys found (a subset of `visualKeys`).
        var keys: Set<String> = []
        /// What OCR read; nil when OCR didn't run.
        var recognizedText: String?
        /// OCR ran and found at least `minTextLength` letters or digits.
        var foundText = false
        /// QR code and barcode contents.
        var payloads: [String] = []

        var didRecognizeText: Bool { recognizedText != nil }
    }

    static func classify(_ data: Data, analyzeVisual: Bool = true, recognizeText: Bool = true) -> Result {
        guard analyzeVisual || recognizeText, let image = downscaledImage(from: data) else { return Result() }

        var result = Result()
        if analyzeVisual && hasTransparency(image) { result.keys.insert(ItemCategory.BuiltIn.transparent.rawValue) }

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.automaticallyDetectsLanguage = true
        let barcodeRequest = VNDetectBarcodesRequest()
        let faceRequest = VNDetectFaceRectanglesRequest()
        var requests: [VNRequest] = []
        if recognizeText { requests.append(textRequest) }
        if analyzeVisual { requests += [barcodeRequest, faceRequest] }

        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform(requests)
        } catch {
            ErrorLogger.shared.log("Failed to analyze an image", category: "Categories", error: error)
            return result
        }

        if recognizeText {
            let lines = (textRequest.results ?? []).compactMap { observation -> String? in
                guard let candidate = observation.topCandidates(1).first,
                      candidate.confidence >= minTextConfidence else { return nil }
                return candidate.string
            }
            let recognized = lines.joined(separator: "\n")
            result.recognizedText = recognized
            result.foundText = recognized.filter { $0.isLetter || $0.isNumber }.count >= minTextLength
        }

        if analyzeVisual {
            let barcodes = barcodeRequest.results ?? []
            if !barcodes.isEmpty { result.keys.insert(ItemCategory.BuiltIn.barcode.rawValue) }
            result.payloads = barcodes.compactMap(\.payloadStringValue).filter { !$0.isEmpty }
            if !(faceRequest.results ?? []).isEmpty { result.keys.insert(ItemCategory.BuiltIn.face.rawValue) }
        }
        return result
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
