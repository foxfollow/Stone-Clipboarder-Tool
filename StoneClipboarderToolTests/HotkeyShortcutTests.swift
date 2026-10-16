import AppKit
import Carbon.HIToolbox
import XCTest
@testable import StoneClipboarderTool

final class HotkeyShortcutTests: XCTestCase {

    // MARK: - Recorder ↔ registration agree

    func testEveryDefaultShortcutParsesToItsCanonicalForm() {
        for action in HotkeyAction.allCases {
            let shortcut = HotkeyShortcut(action.defaultShortcut)
            XCTAssertNotNil(shortcut, "Default for \(action) must be registrable")
            XCTAssertEqual(shortcut?.stringValue, action.defaultShortcut)
        }
    }

    func testEveryRecordableKeyRoundTrips() {
        for key in HotkeyShortcut.keys {
            let recorded = HotkeyShortcut(keyCode: key.keyCode, modifierFlags: [.control, .option])
            XCTAssertNotNil(recorded, "\(key.label) should be recordable")
            let reparsed = HotkeyShortcut(recorded?.stringValue)
            XCTAssertEqual(reparsed, recorded, "\(key.label) must parse back to the same key")
        }
    }

    func testKeyTableHasNoDuplicates() {
        let codes = HotkeyShortcut.keys.map(\.keyCode)
        let labels = HotkeyShortcut.keys.map { $0.label.lowercased() }
        XCTAssertEqual(Set(codes).count, codes.count)
        XCTAssertEqual(Set(labels).count, labels.count)
    }

    func testKeysThatUsedToBeDroppedNowParse() {
        // The old registration only knew digits, letters and Space.
        for text in ["⌃⌥Return", "⌃⌥←", "⌃⌥F5", "⌃⌥-", "⌃⌥[", "⌃⌥Tab"] {
            XCTAssertNotNil(HotkeyShortcut(text), text)
        }
    }

    // MARK: - Parsing

    func testModifierOrderDoesNotMatter() {
        XCTAssertEqual(HotkeyShortcut("⌘⇧Z"), HotkeyShortcut("⇧⌘Z"))
        XCTAssertEqual(HotkeyShortcut("⌘⇧Z")?.stringValue, "⇧⌘Z")
    }

    func testLabelsAreCaseInsensitive() {
        XCTAssertEqual(HotkeyShortcut("⌃⌥space")?.keyCode, UInt16(kVK_Space))
        XCTAssertEqual(HotkeyShortcut("⌃⌥p"), HotkeyShortcut("⌃⌥P"))
    }

    func testRejectsUnusableStrings() {
        XCTAssertNil(HotkeyShortcut(nil))
        XCTAssertNil(HotkeyShortcut(""))
        XCTAssertNil(HotkeyShortcut("None"))
        XCTAssertNil(HotkeyShortcut("1"), "a shortcut needs a modifier")
        XCTAssertNil(HotkeyShortcut("⌃⌥"), "a shortcut needs a key")
        XCTAssertNil(HotkeyShortcut("⌃⌥Х"), "Cyrillic label from an old recorder")
    }

    func testRecorderRejectsPressWithoutModifierOrUnknownKey() {
        XCTAssertNil(HotkeyShortcut(keyCode: UInt16(kVK_ANSI_A), modifierFlags: []))
        XCTAssertNil(HotkeyShortcut(keyCode: UInt16(kVK_ANSI_A), modifierFlags: [.capsLock]))
        XCTAssertNil(HotkeyShortcut(keyCode: UInt16(kVK_Home), modifierFlags: [.control]))
    }

    func testCarbonModifierMask() {
        let all = HotkeyShortcut("⌃⌥⇧⌘1")
        XCTAssertEqual(all?.carbonModifiers, UInt32(controlKey | optionKey | shiftKey | cmdKey))
        XCTAssertEqual(HotkeyShortcut("⌃⌥1")?.carbonModifiers, UInt32(controlKey | optionKey))
    }

    // MARK: - Reserved shortcuts

    func testReservedShortcutsMatchWhateverTheModifierOrder() {
        // The recorder formats modifiers as ⌃⌥⇧⌘ while the old block list was
        // written "⌘⇧Z", so string comparison never blocked these.
        let recorded = HotkeyShortcut(keyCode: UInt16(kVK_ANSI_Z), modifierFlags: [.command, .shift])
        XCTAssertEqual(recorded?.isReservedBySystem, true)
        XCTAssertEqual(HotkeyShortcut("⌃⌘Space")?.isReservedBySystem, true)
    }

    func testDefaultShortcutsAreNotReserved() {
        for action in HotkeyAction.allCases {
            XCTAssertEqual(HotkeyShortcut(action.defaultShortcut)?.isReservedBySystem, false, "\(action)")
        }
    }
}
