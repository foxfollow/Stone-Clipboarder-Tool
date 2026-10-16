import SwiftData
import XCTest
@testable import StoneClipboarderTool

/// A restored pin finds its history item by content, even when that item
/// isn't loaded and its timestamp moved since pinning.
@MainActor
final class PinSourceLinkTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var viewModel: CBViewModel!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([CBItem.self])
        let config = ModelConfiguration("PinSourceLinkTests", schema: schema, isStoredInMemoryOnly: true)
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

    func testPinnedTextFindsItsSourceWithoutLoadedRows() throws {
        let source = CBItem(timestamp: Date(timeIntervalSince1970: 100), content: "pinned text", itemType: .text)
        context.insert(source)
        try context.save()
        XCTAssertTrue(viewModel.items.isEmpty, "precondition: nothing loaded, as at launch")

        let pin = makePin(type: .text, content: "pinned text", sourceTimestamp: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(viewModel.existingItem(matching: pin.contentKey)?.persistentModelID, source.persistentModelID)
    }

    func testEditedPinTextNoLongerLinks() throws {
        context.insert(CBItem(timestamp: Date(), content: "original", itemType: .text))
        try context.save()

        let pin = makePin(type: .text, content: "original, edited in the pin")

        XCTAssertNil(viewModel.existingItem(matching: pin.contentKey))
    }

    func testPinnedFileLinksByNameAndBytes() throws {
        let source = CBItem(timestamp: Date(), fileData: Data([7, 7]), fileName: "doc.bin", itemType: .file)
        context.insert(source)
        try context.save()

        let pin = makePin(type: .file, fileData: Data([7, 7]), fileName: "doc.bin")

        XCTAssertEqual(viewModel.existingItem(matching: pin.contentKey)?.persistentModelID, source.persistentModelID)
    }

    private func makePin(
        type: CBItemType, content: String? = nil, fileData: Data? = nil,
        fileName: String? = nil, sourceTimestamp: Date? = nil
    ) -> PinnedItemConfig {
        PinnedItemConfig(
            itemType: type, content: content, fileData: fileData, fileName: fileName,
            x: 0, y: 0, width: 200, height: 100, sourceTimestamp: sourceTimestamp)
    }
}
