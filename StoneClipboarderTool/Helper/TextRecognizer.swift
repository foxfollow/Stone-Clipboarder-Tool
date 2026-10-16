//
//  TextRecognizer.swift
//  StoneClipboarderTool
//
//  On-device OCR with the Vision framework — no network involved. Used by
//  the Quick Picker's ⌥⏎ paste and the detail view's "Extract Text".
//

import AppKit
import Vision

enum TextRecognizer {
    /// Recognized lines joined with newlines, or nil when nothing was found.
    /// Synchronous and CPU-heavy: call it off the main thread. Safe to call
    /// concurrently — each call has its own request and handler.
    static func recognizeText(in cgImage: CGImage) -> String? {
        var lines: [String] = []
        let request = VNRecognizeTextRequest { request, _ in
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            lines = observations.compactMap { $0.topCandidates(1).first?.string }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Let Vision pick the language instead of assuming English.
        request.automaticallyDetectsLanguage = true

        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } catch {
            ErrorLogger.shared.log("Failed to perform OCR", category: "OCR", error: error)
            return nil
        }
        let text = lines.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    /// The pixels of an NSImage as Vision wants them.
    static func cgImage(from image: NSImage) -> CGImage? {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
