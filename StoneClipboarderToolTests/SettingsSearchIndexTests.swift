import XCTest
@testable import StoneClipboarderTool

final class SettingsSearchIndexTests: XCTestCase {

    private let entries = SettingsSearchIndex.entries()

    func testIdsAreUnique() {
        let ids = entries.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testEveryPageHasEntries() {
        for section in SettingsSection.allCases {
            XCTAssertTrue(entries.contains { $0.section == section }, "\(section) has nothing to find")
        }
    }

    func testIncludesEveryHotkeyAndBuiltInCategory() {
        for action in HotkeyAction.allCases {
            XCTAssertTrue(entries.contains { $0.anchor == SettingsAnchor.hotkey(action) })
        }
        for category in ItemCategory.builtIns {
            XCTAssertTrue(entries.contains { $0.anchor == SettingsAnchor.category(category.id) })
        }
    }

    func testHotkeysAndCategoriesFollowTheirPage() {
        let sections = entries.map(\.section)
        // Each page's entries stay together, in sidebar order.
        var seen: [SettingsSection] = []
        for section in sections where seen.last != section {
            XCTAssertFalse(seen.contains(section), "\(section) is split")
            seen.append(section)
        }
    }

    func testEmptyQueryFindsNothing() {
        XCTAssertTrue(SettingsSearchIndex.search("   ", in: entries).isEmpty)
    }

    func testFindsByTitleKeywordGroupAndPage() {
        XCTAssertEqual(SettingsSearchIndex.search("Drop shadow", in: entries).first?.id, "pins.shadow")
        XCTAssertTrue(SettingsSearchIndex.search("touch id", in: entries).contains { $0.id == "passwords.relock" })
        XCTAssertTrue(SettingsSearchIndex.search("memory management", in: entries).contains {
            $0.id == "general.memoryInterval"
        })
        XCTAssertTrue(SettingsSearchIndex.search("pins default size", in: entries).contains { $0.id == "pins.textSize" })
    }

    func testEveryWordMustMatch() {
        XCTAssertTrue(SettingsSearchIndex.search("shadow zebra", in: entries).isEmpty)
    }

    func testIgnoresCaseAccentsAndSpacing() {
        XCTAssertEqual(
            SettingsSearchIndex.search("  DRÓP   shadow ", in: entries).first?.id, "pins.shadow")
    }

    func testTitleMatchesComeFirst() {
        XCTAssertEqual(SettingsSearchIndex.search("clipboard", in: entries).first?.id, "general.captureMode")

        // "Quick Picker" is a title prefix for one entry and only the page
        // name for the Preview mode row.
        let results = SettingsSearchIndex.search("quick picker", in: entries)
        guard let titleIndex = results.firstIndex(where: { $0.id == "pins.quickPickerDismisses" }),
              let pageIndex = results.firstIndex(where: { $0.id == "quickPicker.previewMode" })
        else { return XCTFail("expected both") }
        XCTAssertLessThan(titleIndex, pageIndex)
    }

    func testCustomCategoriesAreSearchable() {
        var rule = ItemCategory.newRegex()
        rule.name = "Invoice numbers"
        rule.pattern = "INV-\\d+"
        let found = SettingsSearchIndex.search("invoice", in: SettingsSearchIndex.entries(categories: [rule]))
        XCTAssertEqual(found.first?.anchor, SettingsAnchor.category(rule.id))
        XCTAssertEqual(found.first?.group, "Custom rules")
    }

    func testDependentRowsNameTheirParent() {
        let maxItems = entries.first { $0.id == "general.maxItems" }
        XCTAssertEqual(maxItems?.parentAnchor, "general.autoCleanup")
        XCTAssertNotNil(maxItems?.note)
    }
}
