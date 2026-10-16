import Carbon.HIToolbox
import XCTest
@testable import StoneClipboarderTool

/// Type-out paste's character → key mapping (TypePaster).
final class KeyboardLayoutTablesTests: XCTestCase {

    private func stroke(_ code: Int, _ flags: CGEventFlags = [], overrides: Bool = false) -> KeyStroke {
        KeyStroke(keyCode: CGKeyCode(code), flagsRawValue: flags.rawValue, overridesUnicode: overrides)
    }

    // MARK: - Choosing between the active layout and the ASCII fallback

    func testAsciiUsesTheActiveLayoutWhenItCanTypeIt() {
        let tables = KeyboardLayoutTables(active: ["a": stroke(kVK_ANSI_A)], asciiFallback: [:])
        XCTAssertEqual(tables.stroke(for: "a")?.keyCode, CGKeyCode(kVK_ANSI_A))
    }

    func testAsciiPrefersTheFallbackOnANonLatinLayout() {
        // Ukrainian-PC: "#" is ⌥3 there, ⇧3 on the ASCII layout a remote
        // desktop's far end expects.
        let tables = KeyboardLayoutTables(
            active: ["#": stroke(kVK_ANSI_3, .maskAlternate), "я": stroke(kVK_ANSI_Z)],
            asciiFallback: ["#": stroke(kVK_ANSI_3, .maskShift, overrides: true),
                            "a": stroke(kVK_ANSI_A, overrides: true)])

        XCTAssertEqual(tables.stroke(for: "#")?.flags, .maskShift)
        XCTAssertEqual(tables.stroke(for: "a")?.overridesUnicode, true)
        XCTAssertEqual(tables.stroke(for: "я")?.keyCode, CGKeyCode(kVK_ANSI_Z), "non-ASCII stays on the active layout")
        XCTAssertNil(tables.stroke(for: "😀"), "unreachable characters fall back to a Unicode event")
    }

    // MARK: - A real layout

    func testUSLayoutTableUsesMainRowKeysNotTheKeypad() throws {
        let filter = [kTISPropertyInputSourceID as String: "com.apple.keylayout.US"] as CFDictionary
        let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
        let us = try XCTUnwrap(sources?.first, "the US layout ships with macOS")

        let table = KeyboardLayoutTables.table(from: us, overridesUnicode: false)

        XCTAssertEqual(table["a"]?.keyCode, CGKeyCode(kVK_ANSI_A))
        XCTAssertEqual(table["a"]?.flags, [])
        XCTAssertEqual(table["A"]?.flags, .maskShift)
        XCTAssertEqual(table["#"]?.keyCode, CGKeyCode(kVK_ANSI_3))
        XCTAssertEqual(table["*"]?.keyCode, CGKeyCode(kVK_ANSI_8), "not keypad multiply")
        XCTAssertEqual(table["+"]?.keyCode, CGKeyCode(kVK_ANSI_Equal), "not keypad plus")
    }
}
