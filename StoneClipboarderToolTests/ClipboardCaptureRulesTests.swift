import XCTest
@testable import StoneClipboarderTool

/// The capture-mode matrix from ClipboardManager.captureKinds.
final class ClipboardCaptureRulesTests: XCTestCase {

    private func kinds(_ mode: ClipboardCaptureMode, text: Bool, image: Bool) -> [ClipboardManager.CaptureKind] {
        ClipboardManager.captureKinds(for: mode, hasText: text, hasImage: image)
    }

    func testNothingOnThePasteboardCapturesNothing() {
        for mode in ClipboardCaptureMode.allCases {
            XCTAssertEqual(kinds(mode, text: false, image: false), [], "\(mode)")
        }
    }

    func testTextOnlyPrefersTextButKeepsStandaloneImages() {
        XCTAssertEqual(kinds(.textOnly, text: true, image: true), [.text])
        XCTAssertEqual(kinds(.textOnly, text: true, image: false), [.text])
        XCTAssertEqual(kinds(.textOnly, text: false, image: true), [.image])
    }

    func testImageOnlyPrefersImageButKeepsStandaloneText() {
        XCTAssertEqual(kinds(.imageOnly, text: true, image: true), [.image])
        XCTAssertEqual(kinds(.imageOnly, text: false, image: true), [.image])
        XCTAssertEqual(kinds(.imageOnly, text: true, image: false), [.text])
    }

    func testBothCapturesTextThenImageSeparately() {
        XCTAssertEqual(kinds(.both, text: true, image: true), [.text, .image])
        XCTAssertEqual(kinds(.both, text: true, image: false), [.text])
        XCTAssertEqual(kinds(.both, text: false, image: true), [.image])
    }

    func testBothAsOneCombinesOnlyWhenBothArePresent() {
        XCTAssertEqual(kinds(.bothAsOne, text: true, image: true), [.combined])
        XCTAssertEqual(kinds(.bothAsOne, text: true, image: false), [.text])
        XCTAssertEqual(kinds(.bothAsOne, text: false, image: true), [.image])
    }
}
