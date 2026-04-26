import XCTest
@testable import StoneClipboarderTool

final class QuickLookTriggerKeyTests: XCTestCase {

    func testRawValues() {
        XCTAssertEqual(QuickLookTriggerKey.space.rawValue, "space")
        XCTAssertEqual(QuickLookTriggerKey.arrowRight.rawValue, "arrowRight")
    }

    func testAllCasesCount() {
        XCTAssertEqual(QuickLookTriggerKey.allCases.count, 2)
    }

    func testDisplayNames() {
        XCTAssertEqual(QuickLookTriggerKey.space.displayName, "Space")
        XCTAssertEqual(QuickLookTriggerKey.arrowRight.displayName, "Arrow Right (→)")
    }

    func testCodableRoundTrip() throws {
        for key in QuickLookTriggerKey.allCases {
            let data = try JSONEncoder().encode(key)
            let decoded = try JSONDecoder().decode(QuickLookTriggerKey.self, from: data)
            XCTAssertEqual(decoded, key)
        }
    }
}
