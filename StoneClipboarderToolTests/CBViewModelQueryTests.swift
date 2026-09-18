import AppKit
import SwiftData
import XCTest
@testable import StoneClipboarderTool

/// Read-only queries behind the Quick Picker and search boxes.
@MainActor
final class CBViewModelQueryTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var viewModel: CBViewModel!
    private let base = Date(timeIntervalSince1970: 7_000_000)

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([CBItem.self])
        let config = ModelConfiguration("CBViewModelQueryTests", schema: schema, isStoredInMemoryOnly: true)
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

    func testSearchFindsItemsOlderThanTheNewest300() throws {
        insert(CBItem(timestamp: base, content: "the needle", itemType: .text))
        for i in 1...400 {
            insert(CBItem(timestamp: base.addingTimeInterval(Double(i)), content: "filler \(i)", itemType: .text))
        }
        try context.save()

        let found = viewModel.searchItems(matching: "  NEEDLE ")

        XCTAssertEqual(found.map(\.content), ["the needle"])
    }

    func testSearchNoLongerMatchesEveryImage() throws {
        insert(CBItem(timestamp: base, imageData: try pngData(), itemType: .image))
        insert(CBItem(timestamp: base.addingTimeInterval(1), content: "hello", itemType: .text))
        try context.save()

        XCTAssertEqual(viewModel.searchItems(matching: "hello").map(\.itemType), [.text])
        XCTAssertEqual(viewModel.searchItems(matching: "image").map(\.itemType), [.image], "images match their label")
    }

    func testSearchCanBeLimitedToTypes() throws {
        insert(CBItem(timestamp: base, content: "cat pictures", itemType: .text))
        insert(CBItem(timestamp: base.addingTimeInterval(1), fileData: Data([1]), fileName: "cat.txt", itemType: .file))
        try context.save()

        XCTAssertEqual(viewModel.searchItems(matching: "cat").count, 2)
        XCTAssertEqual(viewModel.searchItems(matching: "cat", types: [.file]).map(\.fileName), ["cat.txt"])
    }

    func testSearchStopsAtTheLimitNewestFirst() throws {
        for i in 0..<20 {
            insert(CBItem(timestamp: base.addingTimeInterval(Double(i)), content: "match \(i)", itemType: .text))
        }
        try context.save()

        let found = viewModel.searchItems(matching: "match", limit: 5)

        XCTAssertEqual(found.map(\.content), (15..<20).reversed().map { "match \($0)" })
    }

    func testHistoryPagesAreContiguous() throws {
        for i in 0..<120 {
            insert(CBItem(timestamp: base.addingTimeInterval(Double(i)), content: "row \(i)", itemType: .text))
        }
        try context.save()

        let pages = [0, 50, 100].flatMap { viewModel.historyPage(offset: $0, limit: 50) }

        XCTAssertEqual(pages.compactMap(\.content), (0..<120).reversed().map { "row \($0)" })
    }

    func testCombinedItemsCountAsTextAndImages() throws {
        let image = try pngData()
        insert(CBItem(timestamp: base, content: "t", itemType: .text))
        insert(CBItem(timestamp: base.addingTimeInterval(1), imageData: image, itemType: .image))
        insert(CBItem(timestamp: base.addingTimeInterval(2), content: "both", imageData: image, itemType: .combined))
        insert(CBItem(timestamp: base.addingTimeInterval(3), fileData: Data([1]), fileName: "f", itemType: .file))
        try context.save()

        XCTAssertEqual(viewModel.itemTypeCounts(), CBViewModel.ItemTypeCounts(text: 2, images: 2, files: 1))
        XCTAssertEqual(viewModel.items(ofTypes: [.text, .combined]).compactMap(\.content), ["both", "t"])
    }

    func testTypeCountsAreCachedUntilTheHistoryChanges() throws {
        insert(CBItem(timestamp: base, content: "one", itemType: .text))
        try context.save()
        XCTAssertEqual(viewModel.itemTypeCounts().text, 1)

        insert(CBItem(timestamp: base.addingTimeInterval(1), content: "two", itemType: .text))
        try context.save()
        XCTAssertEqual(viewModel.itemTypeCounts().text, 1, "cached")

        viewModel.refreshItemCounts()
        XCTAssertEqual(viewModel.itemTypeCounts().text, 2)
    }

    // MARK: - Helpers

    private func insert(_ item: CBItem) {
        context.insert(item)
    }

    private func pngData() throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}
