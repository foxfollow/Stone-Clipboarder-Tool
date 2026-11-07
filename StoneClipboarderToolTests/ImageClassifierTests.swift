import AppKit
import CoreImage
import XCTest
@testable import StoneClipboarderTool

/// Vision runs on the device, so these use generated images.
final class ImageClassifierTests: XCTestCase {

    private func textImage() throws -> Data {
        try Self.render(width: 1200, height: 260) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black,
            ]
            ("Visit https://stone.example.com" as NSString).draw(at: NSPoint(x: 40, y: 150), withAttributes: attributes)
            ("Write to hello@example.com" as NSString).draw(at: NSPoint(x: 40, y: 50), withAttributes: attributes)
        }
    }

    func testTextRecognition() throws {
        let result = ImageClassifier.classify(try textImage(), analyzeVisual: false)

        XCTAssertTrue(result.didRecognizeText)
        XCTAssertTrue(result.foundText)
        XCTAssertTrue(result.recognizedText?.contains("stone.example.com") == true)
        XCTAssertTrue(result.keys.isEmpty, "the visual pass didn't run")
    }

    func testRecognizedTextFeedsTheTextCategories() throws {
        let item = CBItem(timestamp: Date(), imageData: try textImage(), itemType: .image)
        let rule = ContentClassifier.RegexRule(id: "visit", pattern: #"visit\s+https"#, caseSensitive: false)

        item.classify(with: .init(rules: [rule]), image: ImageClassifier.classify(item.imageData!))

        XCTAssertEqual(item.textRecognitionState, CBItem.TextRecognition.found)
        for key in ["ocr", "link", "email", "visit"] {
            XCTAssertTrue(item.hasCategoryKey(key), "\(key) in \(item.categoryKeySet)")
        }
        XCTAssertFalse(item.categoryKeySet.contains { $0.hasSuffix(".full") }, "no entire-text keys for images")
        XCTAssertFalse(item.hasCategoryKey("transparent"))
    }

    func testVisualPassOnlySkipsOCR() throws {
        let result = ImageClassifier.classify(try textImage(), recognizeText: false)
        XCTAssertFalse(result.didRecognizeText)
        XCTAssertFalse(result.foundText)
        XCTAssertEqual(ImageClassifier.classify(try textImage(), analyzeVisual: false, recognizeText: false),
                       ImageClassifier.Result(), "nothing asked, nothing done")
    }

    func testQRCode() throws {
        let result = ImageClassifier.classify(try Self.qrCode("https://stone.example.com/qr"), recognizeText: false)

        XCTAssertEqual(result.keys, ["barcode"])
        XCTAssertEqual(result.payloads, ["https://stone.example.com/qr"])
    }

    func testTransparency() throws {
        let cutOut = try Self.render(width: 200, height: 200, opaque: false) {
            NSColor.red.setFill()
            NSRect(x: 50, y: 50, width: 100, height: 100).fill()
        }
        XCTAssertTrue(ImageClassifier.classify(cutOut).keys.contains("transparent"))

        let blank = try Self.render(width: 200, height: 200) {}
        let nothing = ImageClassifier.classify(blank)
        XCTAssertTrue(nothing.keys.isEmpty, "a blank opaque image has nothing")
        XCTAssertFalse(nothing.foundText)
        XCTAssertEqual(nothing.recognizedText, "", "OCR ran and read nothing")
    }

    func testNotAnImage() {
        XCTAssertEqual(ImageClassifier.classify(Data("nope".utf8)),
                       .unreadable(analyzeVisual: true, recognizeText: true), "done for good, not a failure")
        XCTAssertEqual(ImageClassifier.classify(Data("nope".utf8), analyzeVisual: false, recognizeText: false),
                       ImageClassifier.Result())
        XCTAssertNil(ImageClassifier.downscaledImage(from: Data()))
    }

    func testLargeImagesAreScaledDown() throws {
        let png = try Self.render(width: 4000, height: 1000) {}
        let image = try XCTUnwrap(ImageClassifier.downscaledImage(from: png))
        XCTAssertEqual(max(image.width, image.height), ImageClassifier.maxPixelSize)
    }

    // MARK: - Images

    /// PNG bytes of a white (or clear) canvas with `draw` on top, at 1×.
    static func render(width: Int, height: Int, opaque: Bool = true, _ draw: () -> Void) throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        (opaque ? NSColor.white : NSColor.clear).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill(using: .copy)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    static func qrCode(_ message: String) throws -> Data {
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data(message.utf8), forKey: "inputMessage")
        let output = try XCTUnwrap(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let cgImage = try XCTUnwrap(CIContext().createCGImage(output, from: output.extent))
        let side = cgImage.width + 120  // quiet zone
        return try render(width: side, height: side) {
            NSGraphicsContext.current?.cgContext.draw(
                cgImage, in: CGRect(x: 60, y: 60, width: cgImage.width, height: cgImage.height))
        }
    }
}
