import XCTest
@testable import StoneClipboarderTool

final class AppEnvironmentTests: XCTestCase {

    /// If this fails, the test host ran against the real stores, watched the
    /// real clipboard and registered global hotkeys.
    func testDetectsUnitTestHost() {
        XCTAssertTrue(AppEnvironment.isRunningUnitTests)
    }
}
