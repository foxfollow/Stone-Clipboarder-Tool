import AppKit
import SwiftData
import XCTest
@testable import StoneClipboarderTool

@MainActor
final class CBItemThumbnailTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([CBItem.self])
        let config = ModelConfiguration("CBItemThumbnailTests", schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }

    func testNewImageItemsStoreAPNGThumbnail() throws {
        let item = CBItem(timestamp: Date(), imageData: try pngData(), itemType: .image)
        let stored = try XCTUnwrap(item.thumbnailData)
        XCTAssertEqual(Array(stored.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "PNG signature")
    }

    func testReadingAThumbnailNeverWritesToTheModel() throws {
        let item = CBItem(timestamp: Date(), imageData: try pngData(), itemType: .image)
        context.insert(item)
        item.thumbnailData = nil  // an item whose stored thumbnail is missing
        try context.save()

        XCTAssertNotNil(item.thumbnail)

        XCTAssertNil(item.thumbnailData, "the rendered thumbnail stays in memory")
        XCTAssertFalse(context.hasChanges, "rendering must not dirty the context")
    }

    func testOnlyImageLikeItemsHaveAThumbnail() {
        let text = CBItem(timestamp: Date(), content: "hi", itemType: .text)
        let pdf = CBItem(timestamp: Date(), fileData: Data([1]), fileName: "a.pdf", fileUTI: "com.adobe.pdf", itemType: .file)
        XCTAssertNil(text.thumbnail)
        XCTAssertNil(pdf.thumbnail, "non-image files show their file icon instead")
    }

    private func pngData() throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 90, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}
