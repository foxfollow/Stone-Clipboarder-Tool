import AppKit
import CoreImage
import XCTest
@testable import StoneClipboarderTool

/// Vision runs on the device, so these use generated images.
final class ImageClassifierTests: XCTestCase {

    func testTextInImageFeedsTheTextCategories() throws {
        let png = try Self.render(width: 1200, height: 260) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black,
            ]
            ("Visit https://stone.example.com" as NSString).draw(at: NSPoint(x: 40, y: 150), withAttributes: attributes)
            ("Write to hello@example.com" as NSString).draw(at: NSPoint(x: 40, y: 50), withAttributes: attributes)
        }

        let result = ImageClassifier.classify(png)

        XCTAssertTrue(result.keys.contains("ocr"), "\(result.keys)")
        XCTAssertTrue(result.keys.contains("link"), "\(result.keys)")
        XCTAssertTrue(result.keys.contains("email"), "\(result.keys)")
        XCTAssertFalse(result.keys.contains { $0.hasSuffix(".full") }, "no entire-text keys for images")
        XCTAssertFalse(result.keys.contains("transparent"))
    }

    func testRegexRulesSeeTheRecognizedText() throws {
        let png = try Self.render(width: 900, height: 160) {
            ("Invoice 2026-0042" as NSString).draw(
                at: NSPoint(x: 40, y: 50),
                withAttributes: [.font: NSFont.systemFont(ofSize: 56), .foregroundColor: NSColor.black])
        }
        let rule = ContentClassifier.RegexRule(id: "invoice", pattern: #"invoice\s+\d{4}"#, caseSensitive: false)

        let result = ImageClassifier.classify(png, ruleset: .init(rules: [rule]))

        XCTAssertTrue(result.keys.contains("invoice"), "\(result.keys)")
    }

    func testQRCode() throws {
        let png = try Self.qrCode("https://stone.example.com/qr")

        let result = ImageClassifier.classify(png)

        XCTAssertTrue(result.keys.contains("barcode"), "\(result.keys)")
        XCTAssertTrue(result.keys.contains("link"), "the payload is a link")
    }

    func testTransparency() throws {
        let cutOut = try Self.render(width: 200, height: 200, opaque: false) {
            NSColor.red.setFill()
            NSRect(x: 50, y: 50, width: 100, height: 100).fill()
        }
        XCTAssertTrue(ImageClassifier.classify(cutOut).keys.contains("transparent"))

        let blank = try Self.render(width: 200, height: 200) {}
        XCTAssertEqual(ImageClassifier.classify(blank), ImageClassifier.Result(), "a blank opaque image has nothing")
    }

    func testNotAnImage() {
        XCTAssertEqual(ImageClassifier.classify(Data("nope".utf8)), ImageClassifier.Result())
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
