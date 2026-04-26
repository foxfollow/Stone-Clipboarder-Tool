import XCTest
@testable import StoneClipboarderTool

final class QuickLookModeTests: XCTestCase {

    func testRawValues() {
        XCTAssertEqual(QuickLookMode.native.rawValue, "native")
        XCTAssertEqual(QuickLookMode.custom.rawValue, "custom")
        XCTAssertEqual(QuickLookMode.disabled.rawValue, "disabled")
    }

    func testAllCasesCount() {
        XCTAssertEqual(QuickLookMode.allCases.count, 3)
    }

    func testDisplayNames() {
        XCTAssertEqual(QuickLookMode.native.displayName, "Apple Quick Look")
        XCTAssertEqual(QuickLookMode.custom.displayName, "Custom Preview")
        XCTAssertEqual(QuickLookMode.disabled.displayName, "Disabled")
    }

    func testCodableRoundTrip() throws {
        for mode in QuickLookMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(QuickLookMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }
}
