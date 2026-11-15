import XCTest
@testable import StoneClipboarderTool

@MainActor
final class ExternalOpenerTests: XCTestCase {

    func testTempFilesLiveUnderTheirOwnFolder() {
        XCTAssertEqual(ExternalOpener.directory.lastPathComponent, "Open")
        XCTAssertEqual(ExternalOpener.directory.deletingLastPathComponent().lastPathComponent, "StoneClipboarderTool")
    }

    func testRemoveAllTempFilesDeletesLeftovers() throws {
        // Never the real folder: an unsigned test run shares $TMPDIR with the
        // installed app.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExternalOpenerTests-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("left behind".utf8).write(to: folder.appendingPathComponent("Clipboard Text.txt"))

        ExternalOpener.removeAllTempFiles(root: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
}
