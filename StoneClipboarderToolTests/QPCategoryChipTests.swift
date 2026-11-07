import XCTest
@testable import StoneClipboarderTool

final class QPCategoryChipTests: XCTestCase {

    func testChipOrderSkipsEmptyAndDisabledCategories() {
        var categories = ItemCategory.builtIns
        categories[categories.firstIndex { $0.id == "email" }!].isEnabled = false
        var rule = ItemCategory.newRegex()
        rule.name = "Documents"
        rule.pattern = "№"
        var group = ItemCategory.newAppGroup()
        group.name = "Browsers"
        group.appBundleIDs = ["com.apple.Safari"]
        categories = [group, rule] + categories  // kind order wins; equal language counts go by code

        var facets = FacetCounts()
        facets.keys = ["link": 4, "email": 2, rule.id: 1]
        facets.languages = ["en": 3, "uk": 5, "de": 3]
        facets.apps = ["com.apple.Safari": 6]

        let chips = QPCategoryChip.chips(for: categories, facets: facets)

        XCTAssertEqual(chips.map(\.name), ["Link", "Ukrainian", "German", "English", "Documents", "Browsers"])
        XCTAssertEqual(chips.map(\.count), [4, 5, 3, 3, 1, 6])
        XCTAssertEqual(chips[1].selection, .language("uk"))
        XCTAssertEqual(chips.last?.selection, .category(group.id))
    }

    func testNoChipsWithoutCounts() {
        XCTAssertTrue(QPCategoryChip.chips(for: ItemCategory.builtIns, facets: FacetCounts()).isEmpty)
    }
}
