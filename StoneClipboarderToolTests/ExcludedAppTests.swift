import XCTest
@testable import StoneClipboarderTool

final class ExcludedAppTests: XCTestCase {

    func testInitializerStoresFields() {
        let app = ExcludedApp(bundleIdentifier: "com.example.foo", appName: "Foo")
        XCTAssertEqual(app.bundleIdentifier, "com.example.foo")
        XCTAssertEqual(app.appName, "Foo")
    }

    func testDateAddedIsRecent() {
        let before = Date()
        let app = ExcludedApp(bundleIdentifier: "x", appName: "X")
        let after = Date()
        XCTAssertGreaterThanOrEqual(app.dateAdded, before)
        XCTAssertLessThanOrEqual(app.dateAdded, after)
    }
}
