import SwiftUI
import XCTest
@testable import StoneClipboarderTool

final class ItemCategoryTests: XCTestCase {

    private func item(keys: String? = nil, language: String? = nil, app: String? = nil) -> CBItem {
        let item = CBItem(timestamp: Date(), content: "x", itemType: .text)
        item.categoryKeys = keys
        item.languageCode = language
        item.sourceAppBundleID = app
        return item
    }

    func testBuiltInIdsAreStable() {
        // Stored in CBItem.categoryKeys and settings: never rename.
        XCTAssertEqual(ItemCategory.builtIns.map(\.id),
                       ["link", "email", "phone", "address", "date", "code", "json", "path", "language",
                        "ocr", "barcode", "face", "transparent"])
        XCTAssertEqual(ItemCategory.BuiltIn.allCases.filter(\.isImageCategory), [.ocr, .barcode, .face, .transparent])
        XCTAssertFalse(ItemCategory.builtIns.first { $0.id == "ocr" }!.supportsMatchMode)
        XCTAssertTrue(ItemCategory.builtIns.allSatisfy { $0.isEnabled && $0.kind == .builtIn })
    }

    func testMatchModeSelectsTheStoredKey() {
        var link = ItemCategory.builtIns[0]
        let inText = item(keys: ",link,")
        let whole = item(keys: ",link,link.full,")
        XCTAssertTrue(link.matches(inText))
        link.matchMode = .entireText
        XCTAssertFalse(link.matches(inText))
        XCTAssertTrue(link.matches(whole))
    }

    func testCodeIgnoresMatchMode() {
        var code = ItemCategory.builtIns.first { $0.id == "code" }!
        code.matchMode = .entireText
        XCTAssertFalse(code.supportsMatchMode)
        XCTAssertEqual(code.storedKey, "code")
    }

    func testLanguageAndAppGroupMatching() {
        let languages = ItemCategory.builtIns.first { $0.builtIn == .language }!
        XCTAssertTrue(languages.matches(item(language: "uk")))
        XCTAssertFalse(languages.matches(item()))

        var group = ItemCategory.newAppGroup()
        group.appBundleIDs = ["com.tinyspeck.slackmacgap", "ru.keepcoder.Telegram"]
        XCTAssertTrue(group.matches(item(app: "ru.keepcoder.Telegram")))
        XCTAssertFalse(group.matches(item(app: "com.apple.Safari")))
        XCTAssertFalse(group.matches(item()))
    }

    func testCountsFromFacets() {
        var facets = FacetCounts()
        facets.keys = ["link": 3, "link.full": 1]
        facets.languages = ["uk": 2, "en": 5]
        facets.apps = ["a": 4, "b": 1, "c": 9]

        var link = ItemCategory.builtIns[0]
        XCTAssertEqual(link.count(in: facets), 3)
        link.matchMode = .entireText
        XCTAssertEqual(link.count(in: facets), 1)
        XCTAssertEqual(ItemCategory.builtIns.first { $0.builtIn == .language }!.count(in: facets), 7)
        var group = ItemCategory.newAppGroup()
        group.appBundleIDs = ["a", "b"]
        XCTAssertEqual(group.count(in: facets), 5)
    }

    func testRegexRuleOnlyForValidPatterns() {
        var rule = ItemCategory.newRegex()
        XCTAssertNil(rule.regexRule, "empty pattern")
        rule.pattern = "(oops"
        XCTAssertNil(rule.regexRule)
        rule.pattern = #"\d+"#
        rule.isEnabled = false
        XCTAssertEqual(rule.regexRule?.pattern, #"\d+"#, "disabled rules still classify")
        XCTAssertNil(ItemCategory.builtIns[0].regexRule)
    }

    func testMergeAddsMissingBuiltInsAndDropsUnknownOnes() {
        var link = ItemCategory.builtIns[0]
        link.isEnabled = false
        link.name = "Renamed"
        var custom = ItemCategory.newRegex()
        custom.name = "Docs"
        let ghost = ItemCategory(id: "gone", name: "Gone", kind: .builtIn, icon: .symbol("x"), colorHex: "#000000")

        let merged = ItemCategory.merged(stored: [custom, link, ghost, link])

        XCTAssertEqual(merged.first?.id, custom.id, "stored order kept")
        XCTAssertEqual(merged[1].id, "link")
        XCTAssertFalse(merged[1].isEnabled, "user state kept")
        XCTAssertEqual(merged[1].name, "Link", "built-in names come from the code")
        XCTAssertFalse(merged.contains { $0.id == "gone" })
        XCTAssertEqual(merged.filter { $0.id == "link" }.count, 1)
        XCTAssertEqual(merged.count, ItemCategory.builtIns.count + 1)
    }

    func testCodableRoundTripAndOldJSON() throws {
        var group = ItemCategory.newAppGroup()
        group.name = "Messengers"
        group.appBundleIDs = ["ru.keepcoder.Telegram"]
        group.appNames = ["Telegram"]
        group.icon = .emoji("💬")
        let data = try JSONEncoder().encode([group])
        XCTAssertEqual(try JSONDecoder().decode([ItemCategory].self, from: data), [group])

        let minimal = #"[{"id":"x","kind":"regex"}]"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([ItemCategory].self, from: minimal)
        XCTAssertEqual(decoded.first?.isEnabled, true)
        XCTAssertEqual(decoded.first?.matchMode, .contains)
        XCTAssertEqual(decoded.first?.icon, .symbol("tag"))
    }

    func testHexColors() {
        XCTAssertEqual(ItemCategory.hex(from: Color(nsColor: ItemCategory.nsColor(hex: "#0A84FF")!)), "#0A84FF")
        XCTAssertNotNil(ItemCategory.nsColor(hex: "ff0000"))
        XCTAssertNil(ItemCategory.nsColor(hex: "#12345"))
        XCTAssertNil(ItemCategory.nsColor(hex: "#GGGGGG"))
        _ = ItemCategory.builtIns[0].color
    }

    func testEmojiValidation() {
        XCTAssertTrue(ItemCategory.isSingleEmoji("📄"))
        XCTAssertTrue(ItemCategory.isSingleEmoji("👍🏽"))
        XCTAssertTrue(ItemCategory.isSingleEmoji("🇺🇦"))
        XCTAssertFalse(ItemCategory.isSingleEmoji("1"))
        XCTAssertFalse(ItemCategory.isSingleEmoji("a"))
        XCTAssertFalse(ItemCategory.isSingleEmoji("📄📄"))
        XCTAssertFalse(ItemCategory.isSingleEmoji(""))
    }

    func testPatternValidationAndLanguageNames() {
        XCTAssertTrue(ItemCategory.isValidPattern(#"\d+"#))
        XCTAssertFalse(ItemCategory.isValidPattern(""))
        XCTAssertFalse(ItemCategory.isValidPattern("[a-"))
        XCTAssertEqual(ItemCategory.languageName("uk"), "Ukrainian")
        XCTAssertEqual(ItemCategory.MatchMode.entireText.displayName, "Entire text")
        XCTAssertEqual(ItemCategory.MatchMode.contains.displayName, "Contains")
    }
}
