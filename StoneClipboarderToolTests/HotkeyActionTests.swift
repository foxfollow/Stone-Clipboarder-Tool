import XCTest
@testable import StoneClipboarderTool

final class HotkeyActionTests: XCTestCase {

    func testAllCasesCount() {
        // 10 last + 10 favorite + 1 main panel
        XCTAssertEqual(HotkeyAction.allCases.count, 21)
    }

    func testLastActionsClassification() {
        let lastActions: [HotkeyAction] = [.last1, .last2, .last3, .last4, .last5,
                                            .last6, .last7, .last8, .last9, .last0]
        for action in lastActions {
            XCTAssertTrue(action.isLastAction, "\(action) should be last action")
            XCTAssertFalse(action.isFavoriteAction)
        }
    }

    func testFavoriteActionsClassification() {
        let favActions: [HotkeyAction] = [.fav1, .fav2, .fav3, .fav4, .fav5,
                                          .fav6, .fav7, .fav8, .fav9, .fav0]
        for action in favActions {
            XCTAssertTrue(action.isFavoriteAction, "\(action) should be favorite action")
            XCTAssertFalse(action.isLastAction)
        }
    }

    func testMainPanelClassification() {
        XCTAssertFalse(HotkeyAction.mainPanel.isLastAction)
        XCTAssertFalse(HotkeyAction.mainPanel.isFavoriteAction)
        XCTAssertEqual(HotkeyAction.mainPanel.index, -1)
    }

    func testIndexMapping() {
        XCTAssertEqual(HotkeyAction.last1.index, 0)
        XCTAssertEqual(HotkeyAction.fav1.index, 0)
        XCTAssertEqual(HotkeyAction.last5.index, 4)
        XCTAssertEqual(HotkeyAction.fav5.index, 4)
        XCTAssertEqual(HotkeyAction.last0.index, 9)
        XCTAssertEqual(HotkeyAction.fav0.index, 9)
    }

    func testDefaultShortcutsNonEmpty() {
        for action in HotkeyAction.allCases {
            XCTAssertFalse(action.defaultShortcut.isEmpty, "Empty shortcut for \(action)")
        }
    }

    func testDefaultShortcutsUnique() {
        let shortcuts = HotkeyAction.allCases.map(\.defaultShortcut)
        XCTAssertEqual(Set(shortcuts).count, shortcuts.count, "Duplicate default shortcuts")
    }

    func testLastActionsUseControlOption() {
        let lastActions: [HotkeyAction] = [.last1, .last2, .last3, .last4, .last5,
                                            .last6, .last7, .last8, .last9, .last0]
        for action in lastActions {
            XCTAssertTrue(action.defaultShortcut.contains("⌃"))
            XCTAssertTrue(action.defaultShortcut.contains("⌥"))
        }
    }

    func testFavActionsUseControlShift() {
        let favActions: [HotkeyAction] = [.fav1, .fav2, .fav3, .fav4, .fav5,
                                          .fav6, .fav7, .fav8, .fav9, .fav0]
        for action in favActions {
            XCTAssertTrue(action.defaultShortcut.contains("⌃"))
            XCTAssertTrue(action.defaultShortcut.contains("⇧"))
        }
    }

    func testMainPanelDefaultShortcut() {
        XCTAssertEqual(HotkeyAction.mainPanel.defaultShortcut, "⌃⌥Space")
    }

    func testDisplayNamesNonEmpty() {
        for action in HotkeyAction.allCases {
            XCTAssertFalse(action.displayName.isEmpty)
        }
    }

    func testCodableRoundTrip() throws {
        for action in HotkeyAction.allCases {
            let data = try JSONEncoder().encode(action)
            let decoded = try JSONDecoder().decode(HotkeyAction.self, from: data)
            XCTAssertEqual(decoded, action)
        }
    }
}
