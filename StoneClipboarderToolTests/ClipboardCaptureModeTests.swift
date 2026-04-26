import XCTest
@testable import StoneClipboarderTool

final class ClipboardCaptureModeTests: XCTestCase {

    func testRawValues() {
        XCTAssertEqual(ClipboardCaptureMode.textOnly.rawValue, "textOnly")
        XCTAssertEqual(ClipboardCaptureMode.imageOnly.rawValue, "imageOnly")
        XCTAssertEqual(ClipboardCaptureMode.both.rawValue, "both")
        XCTAssertEqual(ClipboardCaptureMode.bothAsOne.rawValue, "bothAsOne")
    }

    func testAllCasesCount() {
        XCTAssertEqual(ClipboardCaptureMode.allCases.count, 4)
    }

    func testDisplayNamesNonEmpty() {
        for mode in ClipboardCaptureMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty, "Empty displayName for \(mode)")
        }
    }

    func testDescriptionsNonEmpty() {
        for mode in ClipboardCaptureMode.allCases {
            XCTAssertFalse(mode.description.isEmpty, "Empty description for \(mode)")
        }
    }

    func testDisplayNamesUnique() {
        let names = ClipboardCaptureMode.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testCodableRoundTrip() throws {
        for mode in ClipboardCaptureMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(ClipboardCaptureMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }
}
