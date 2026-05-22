import XCTest
@testable import StoneClipboarderTool

final class PinnedItemConfigTests: XCTestCase {

    func testInitStoresProvidedValues() {
        let id = UUID()
        let ts = Date(timeIntervalSince1970: 1_000)
        let config = PinnedItemConfig(
            id: id,
            itemType: .text,
            content: "hello",
            imageData: nil,
            fileData: nil,
            fileName: "note.txt",
            fileUTI: "public.plain-text",
            x: 10,
            y: 20,
            width: 300,
            height: 200,
            opacity: 0.8,
            isLocked: true,
            isClickThrough: true,
            isCollapsed: true,
            imageZoom: 2.0,
            sourceTimestamp: ts
        )

        XCTAssertEqual(config.id, id)
        XCTAssertEqual(config.content, "hello")
        XCTAssertEqual(config.fileName, "note.txt")
        XCTAssertEqual(config.fileUTI, "public.plain-text")
        XCTAssertEqual(config.x, 10)
        XCTAssertEqual(config.y, 20)
        XCTAssertEqual(config.width, 300)
        XCTAssertEqual(config.height, 200)
        XCTAssertEqual(config.opacity, 0.8)
        XCTAssertTrue(config.isLocked)
        XCTAssertTrue(config.isClickThrough)
        XCTAssertTrue(config.isCollapsed)
        XCTAssertEqual(config.imageZoom, 2.0)
        XCTAssertEqual(config.sourceTimestamp, ts)
    }

    func testInitDefaults() {
        let config = PinnedItemConfig(
            itemType: .image,
            x: 0, y: 0, width: 400, height: 250
        )

        // Behavior defaults
        XCTAssertEqual(config.opacity, 1.0)
        XCTAssertFalse(config.isLocked)
        XCTAssertFalse(config.isClickThrough)
        XCTAssertFalse(config.isCollapsed)
        XCTAssertEqual(config.imageZoom, 1.0)
        XCTAssertNil(config.content)
        XCTAssertNil(config.sourceTimestamp)
        // expandedHeight mirrors the initial height so collapse can restore it
        XCTAssertEqual(config.expandedHeight, 250)
        // createdAt is set at init time
        XCTAssertLessThanOrEqual(config.createdAt.timeIntervalSinceNow, 0)
    }

    func testItemTypeRoundTripsForEveryCase() {
        for type in CBItemType.allCases {
            let config = PinnedItemConfig(itemType: type, x: 0, y: 0, width: 100, height: 100)
            XCTAssertEqual(config.itemTypeRaw, type.rawValue)
            XCTAssertEqual(config.itemType, type)
        }
    }

    func testItemTypeFallsBackToTextForUnknownRaw() {
        let config = PinnedItemConfig(itemType: .file, x: 0, y: 0, width: 100, height: 100)
        config.itemTypeRaw = "not-a-real-type"
        XCTAssertEqual(config.itemType, .text)
    }

    func testFrameMatchesStoredGeometry() {
        let config = PinnedItemConfig(
            itemType: .text, x: 12, y: 34, width: 320, height: 240
        )
        XCTAssertEqual(config.frame, NSRect(x: 12, y: 34, width: 320, height: 240))
    }

    func testUniqueIdsByDefault() {
        let a = PinnedItemConfig(itemType: .text, x: 0, y: 0, width: 1, height: 1)
        let b = PinnedItemConfig(itemType: .text, x: 0, y: 0, width: 1, height: 1)
        XCTAssertNotEqual(a.id, b.id)
    }
}
