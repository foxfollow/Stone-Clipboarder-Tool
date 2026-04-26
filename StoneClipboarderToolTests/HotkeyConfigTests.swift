import XCTest
@testable import StoneClipboarderTool

final class HotkeyConfigTests: XCTestCase {

    func testInitWithDefaultsUsesActionDefaultShortcut() {
        let config = HotkeyConfig(action: .last1)
        XCTAssertEqual(config.action, "last_1")
        XCTAssertEqual(config.shortcutKeys, HotkeyAction.last1.defaultShortcut)
        XCTAssertTrue(config.isEnabled)
    }

    func testInitWithCustomShortcut() {
        let config = HotkeyConfig(action: .fav3, shortcutKeys: "⌘1")
        XCTAssertEqual(config.shortcutKeys, "⌘1")
    }

    func testInitDisabled() {
        let config = HotkeyConfig(action: .mainPanel, isEnabled: false)
        XCTAssertFalse(config.isEnabled)
    }

    func testHotkeyActionRoundTrip() {
        for action in HotkeyAction.allCases {
            let config = HotkeyConfig(action: action)
            XCTAssertEqual(config.hotkeyAction, action)
        }
    }

    func testHotkeyActionInvalidRawReturnsNil() {
        let config = HotkeyConfig(action: .last1)
        config.action = "not_a_real_action"
        XCTAssertNil(config.hotkeyAction)
    }

    func testEachConfigGetsUniqueId() {
        let a = HotkeyConfig(action: .last1)
        let b = HotkeyConfig(action: .last1)
        XCTAssertNotEqual(a.id, b.id)
    }

    func testTimestampIsRecent() {
        let before = Date()
        let config = HotkeyConfig(action: .last1)
        let after = Date()
        XCTAssertGreaterThanOrEqual(config.timestamp, before)
        XCTAssertLessThanOrEqual(config.timestamp, after)
    }
}
