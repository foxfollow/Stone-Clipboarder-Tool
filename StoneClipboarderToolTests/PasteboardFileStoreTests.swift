import XCTest
@testable import StoneClipboarderTool

final class PasteboardFileStoreTests: XCTestCase {

    private var root: URL!

    override func setUp() {
        super.setUp()
        // Never the real store directory: an unsigned test run shares $TMPDIR
        // with the installed app.
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteboardFileStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        PasteboardFileStore.removeAll(root: root)
        super.tearDown()
    }

    func testWriteKeepsNameAndContents() throws {
        let url = try PasteboardFileStore.write(Data("hello".utf8), fileName: "notes.txt", root: root)
        XCTAssertEqual(url.lastPathComponent, "notes.txt")
        XCTAssertEqual(try Data(contentsOf: url), Data("hello".utf8))
    }

    func testFileOutlivesTheOldFiveSecondWindow() throws {
        // Nothing is scheduled for deletion; the file stays until the next copy.
        let url = try PasteboardFileStore.write(Data([1, 2, 3]), fileName: "a.bin", root: root)
        let expectation = expectation(description: "run loop turns")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { expectation.fulfill() }
        wait(for: [expectation], timeout: 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testNextCopyReplacesThePreviousFile() throws {
        let first = try PasteboardFileStore.write(Data([1]), fileName: "same.txt", root: root)
        let second = try PasteboardFileStore.write(Data([2]), fileName: "same.txt", root: root)
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertEqual(try Data(contentsOf: second), Data([2]))
    }

    func testFileNameCannotEscapeTheFolder() {
        XCTAssertEqual(PasteboardFileStore.safeFileName("../../etc/passwd"), "passwd")
        XCTAssertEqual(PasteboardFileStore.safeFileName(""), "Clipboard File")
        XCTAssertEqual(PasteboardFileStore.safeFileName(".."), "Clipboard File")
    }
}
