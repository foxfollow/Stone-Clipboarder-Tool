import XCTest
@testable import StoneClipboarderTool

final class CBItemTests: XCTestCase {

    func testTextItemInitialization() {
        let now = Date()
        let item = CBItem(timestamp: now, content: "hello", itemType: .text)
        XCTAssertEqual(item.timestamp, now)
        XCTAssertEqual(item.content, "hello")
        XCTAssertEqual(item.itemType, .text)
        XCTAssertFalse(item.isFavorite)
        XCTAssertEqual(item.orderIndex, 0)
    }

    func testContentPreviewTruncatedToFirst100Chars() {
        let longText = String(repeating: "a", count: 250)
        let item = CBItem(timestamp: Date(), content: longText, itemType: .text)
        XCTAssertEqual(item.contentPreview?.count, 100)
    }

    func testContentPreviewShortText() {
        let item = CBItem(timestamp: Date(), content: "short", itemType: .text)
        XCTAssertEqual(item.contentPreview, "short")
    }

    func testDisplayContentForText() {
        let item = CBItem(timestamp: Date(), content: "hello world", itemType: .text)
        XCTAssertEqual(item.displayContent, "hello world")
    }

    func testDisplayContentForEmptyText() {
        let item = CBItem(timestamp: Date(), itemType: .text)
        XCTAssertEqual(item.displayContent, "Empty text")
    }

    func testDisplayContentForFile() {
        let item = CBItem(
            timestamp: Date(),
            fileData: Data([0x01, 0x02, 0x03]),
            fileName: "doc.txt",
            fileUTI: "public.plain-text",
            itemType: .file
        )
        XCTAssertTrue(item.displayContent.contains("doc.txt"))
        XCTAssertTrue(item.displayContent.hasPrefix("[File"))
    }

    func testFileSizeIsRecorded() {
        let bytes = Data(repeating: 0xAB, count: 1024)
        let item = CBItem(
            timestamp: Date(),
            fileData: bytes,
            fileName: "blob.bin",
            fileUTI: "public.data",
            itemType: .file
        )
        XCTAssertEqual(item.fileSize, 1024)
    }

    func testIsImageFileFalseForNonImageUTI() {
        let item = CBItem(
            timestamp: Date(),
            fileData: Data([0x00]),
            fileName: "doc.txt",
            fileUTI: "public.plain-text",
            itemType: .file
        )
        XCTAssertFalse(item.isImageFile)
    }

    func testIsImageFileFalseWhenNoUTI() {
        let item = CBItem(timestamp: Date(), itemType: .file)
        XCTAssertFalse(item.isImageFile)
    }

    func testIsImageFileFalseForNonFileType() {
        let item = CBItem(timestamp: Date(), content: "hi", itemType: .text)
        XCTAssertFalse(item.isImageFile)
    }

    func testImagePropertyNilForTextItem() {
        let item = CBItem(timestamp: Date(), content: "hello", itemType: .text)
        XCTAssertNil(item.image)
    }

    func testIsDuplicateForIdenticalText() {
        let a = CBItem(timestamp: Date(), content: "same", itemType: .text)
        let b = CBItem(timestamp: Date().addingTimeInterval(10), content: "same", itemType: .text)
        XCTAssertTrue(a.isDuplicate(of: b))
    }

    func testIsDuplicateFalseForDifferentText() {
        let a = CBItem(timestamp: Date(), content: "one", itemType: .text)
        let b = CBItem(timestamp: Date(), content: "two", itemType: .text)
        XCTAssertFalse(a.isDuplicate(of: b))
    }

    func testIsDuplicateFalseAcrossTypes() {
        let text = CBItem(timestamp: Date(), content: "x", itemType: .text)
        let file = CBItem(
            timestamp: Date(),
            fileData: Data([0x01]),
            fileName: "x",
            itemType: .file
        )
        XCTAssertFalse(text.isDuplicate(of: file))
    }

    func testIsDuplicateForFile() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let a = CBItem(timestamp: Date(), fileData: data, fileName: "a.bin", itemType: .file)
        let b = CBItem(timestamp: Date(), fileData: data, fileName: "a.bin", itemType: .file)
        XCTAssertTrue(a.isDuplicate(of: b))
    }

    func testIsDuplicateFileFalseWhenNameDiffers() {
        let data = Data([0x01])
        let a = CBItem(timestamp: Date(), fileData: data, fileName: "a.bin", itemType: .file)
        let b = CBItem(timestamp: Date(), fileData: data, fileName: "b.bin", itemType: .file)
        XCTAssertFalse(a.isDuplicate(of: b))
    }

    func testIsDuplicateForCombined() {
        let data = Data([0x01, 0x02])
        let a = CBItem(timestamp: Date(), content: "txt", imageData: data, itemType: .combined)
        let b = CBItem(timestamp: Date(), content: "txt", imageData: data, itemType: .combined)
        XCTAssertTrue(a.isDuplicate(of: b))
    }

    func testFindExistingItemReturnsMatch() {
        let items = [
            CBItem(timestamp: Date(), content: "a", itemType: .text),
            CBItem(timestamp: Date(), content: "b", itemType: .text),
            CBItem(timestamp: Date(), content: "c", itemType: .text)
        ]
        let probe = CBItem(timestamp: Date(), content: "b", itemType: .text)
        let found = CBItem.findExistingItem(in: items, matching: probe)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.content, "b")
    }

    func testFindExistingItemReturnsNilWhenAbsent() {
        let items = [
            CBItem(timestamp: Date(), content: "a", itemType: .text),
            CBItem(timestamp: Date(), content: "b", itemType: .text)
        ]
        let probe = CBItem(timestamp: Date(), content: "missing", itemType: .text)
        XCTAssertNil(CBItem.findExistingItem(in: items, matching: probe))
    }

    func testFavoriteAndOrderIndexAreSet() {
        let item = CBItem(
            timestamp: Date(),
            content: "fav",
            itemType: .text,
            isFavorite: true,
            orderIndex: 7
        )
        XCTAssertTrue(item.isFavorite)
        XCTAssertEqual(item.orderIndex, 7)
    }
}
