import AppKit
import SwiftData
import XCTest
@testable import StoneClipboarderTool

/// Re-copying content must move the existing item up, wherever it sits in
/// the history, instead of adding a duplicate.
@MainActor
final class CBViewModelDedupeTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var viewModel: CBViewModel!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([CBItem.self])
        let config = ModelConfiguration("CBViewModelDedupeTests", schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
        viewModel = CBViewModel()
        viewModel.setModelContext(context)
    }

    override func tearDown() async throws {
        viewModel = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    func testRecopyingOldTextBumpsItEvenWhenItIsNotLoaded() throws {
        let base = Date(timeIntervalSince1970: 6_000_000)
        context.insert(CBItem(timestamp: base, content: "old favorite snippet", itemType: .text))
        for i in 1...50 {
            context.insert(CBItem(timestamp: base.addingTimeInterval(Double(i)), content: "filler \(i)", itemType: .text))
        }
        try context.save()
        viewModel.fetchItems(reset: true)
        XCTAssertFalse(viewModel.items.contains { $0.content == "old favorite snippet" }, "precondition: not loaded")

        viewModel.addTextItem(content: "old favorite snippet")

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CBItem>()), 51, "no duplicate")
        XCTAssertEqual(viewModel.items.first?.content, "old favorite snippet")
    }

    func testSharedPrefixIsNotADuplicate() throws {
        let prefix = String(repeating: "x", count: CBItem.previewLength)
        viewModel.addTextItem(content: prefix + " first")
        viewModel.addTextItem(content: prefix + " second")

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CBItem>()), 2)
    }

    func testTextAndCombinedWithTheSameTextStaySeparate() throws {
        let image = try pngData(red: true)
        context.insert(CBItem(timestamp: Date(), content: "caption", imageData: image, itemType: .combined))
        try context.save()

        XCTAssertNil(viewModel.existingItem(matching: CBItem.ContentKey(type: .text, content: "caption")))
        XCTAssertNotNil(viewModel.existingItem(matching: CBItem.ContentKey(type: .combined, content: "caption", imageData: image)))
    }

    func testSameImageBytesAreFoundDifferentPixelsAreNot() throws {
        let red = try pngData(red: true)
        let blue = try pngData(red: false)
        XCTAssertNotEqual(red, blue, "precondition: different bytes")
        context.insert(CBItem(timestamp: Date(), imageData: red, itemType: .image))
        try context.save()

        XCTAssertNotNil(viewModel.existingItem(matching: CBItem.ContentKey(type: .image, imageData: red)))
        XCTAssertNil(viewModel.existingItem(matching: CBItem.ContentKey(type: .image, imageData: blue)),
                     "same size, different pixels")
    }

    func testCapturedImageIsDeduplicatedEndToEnd() async throws {
        let red = try pngData(red: true)
        viewModel.getClipboardManager().onClipboardChange?(.image(red))
        viewModel.getClipboardManager().onClipboardChange?(.image(red))
        await waitUntil { (try? self.context.fetchCount(FetchDescriptor<CBItem>())) == 1 && self.viewModel.items.count == 1 }

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CBItem>()), 1)
    }

    func testFilesMatchOnNameAndBytes() throws {
        context.insert(CBItem(timestamp: Date(), fileData: Data([1, 2]), fileName: "a.bin", itemType: .file))
        try context.save()

        XCTAssertNotNil(viewModel.existingItem(matching: CBItem.ContentKey(type: .file, fileData: Data([1, 2]), fileName: "a.bin")))
        XCTAssertNil(viewModel.existingItem(matching: CBItem.ContentKey(type: .file, fileData: Data([9]), fileName: "a.bin")))
        XCTAssertNil(viewModel.existingItem(matching: CBItem.ContentKey(type: .file, fileData: Data([1, 2]), fileName: "b.bin")))
    }

    func testOldFileIsFoundPastManyFilesWithTheSameName() throws {
        let base = Date(timeIntervalSince1970: 6_000_000)
        context.insert(CBItem(timestamp: base, fileData: Data([7, 7, 7]), fileName: "image.png", itemType: .file))
        for i in 1...40 {
            context.insert(CBItem(
                timestamp: base.addingTimeInterval(Double(i)), fileData: Data([UInt8(i)]),
                fileName: "image.png", itemType: .file))
        }
        try context.save()

        let found = viewModel.existingItem(matching: CBItem.ContentKey(type: .file, fileData: Data([7, 7, 7]), fileName: "image.png"))

        XCTAssertEqual(found?.timestamp, base)
    }

    // MARK: - Helpers

    /// A 4×3 PNG; `red` flips one pixel so both images share a size.
    private func pngData(red: Bool) throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        // A device-RGB color: setColor ignores colors from another color space.
        rep.setColor(NSColor(deviceRed: red ? 1 : 0, green: 0, blue: red ? 0 : 1, alpha: 1), atX: 0, y: 0)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
