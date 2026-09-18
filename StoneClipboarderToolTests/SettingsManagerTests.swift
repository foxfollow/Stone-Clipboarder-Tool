import XCTest
@testable import StoneClipboarderTool

@MainActor
final class SettingsManagerTests: XCTestCase {

    private var isolated: IsolatedDefaults!
    private var defaults: UserDefaults { isolated.defaults }

    override func setUp() async throws {
        try await super.setUp()
        isolated = IsolatedDefaults()
    }

    override func tearDown() async throws {
        isolated.remove()
        isolated = nil
        try await super.tearDown()
    }

    func testLegacyQuickPickerPositionKeysAreRemoved() {
        defaults.set(485.0, forKey: "QuickPickerWindowX")
        defaults.set(171.0, forKey: "QuickPickerWindowY")
        defaults.set(true, forKey: "QuickPickerHasValidPosition")

        _ = SettingsManager(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: "QuickPickerWindowX"))
        XCTAssertNil(defaults.object(forKey: "QuickPickerWindowY"))
        XCTAssertNil(defaults.object(forKey: "QuickPickerHasValidPosition"))
    }
}
