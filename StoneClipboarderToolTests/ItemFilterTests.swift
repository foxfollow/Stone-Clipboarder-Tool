import XCTest
@testable import StoneClipboarderTool

final class ItemFilterTests: XCTestCase {

    // MARK: - Parsing

    func testParseSplitsTokensFromText() {
        let query = QPSearchQuery.parse("  Invoice is:Link app:Safari lang:uk  march ")
        XCTAssertEqual(query.text, "Invoice march")
        XCTAssertEqual(query.isTokens, ["link"])
        XCTAssertEqual(query.appTokens, ["safari"])
        XCTAssertEqual(query.langTokens, ["uk"])
        XCTAssertTrue(query.hasTokens)
        XCTAssertFalse(query.isEmpty)
    }

    func testQuotedValues() {
        let query = QPSearchQuery.parse(#"app:"Visual Studio Code" hello"#)
        XCTAssertEqual(query.appTokens, ["visual studio code"])
        XCTAssertEqual(query.text, "hello")

        let unclosed = QPSearchQuery.parse(#"app:"Visual Studio"#)
        XCTAssertEqual(unclosed.appTokens, ["visual studio"])
    }

    func testTextWithoutTokensKeepsItsSpacing() {
        XCTAssertEqual(QPSearchQuery.parse("  two  spaces\nand a line ").text, "two  spaces\nand a line")
        XCTAssertEqual(QPSearchQuery.parse("IS:link Mixed").isTokens, ["link"], "prefixes in any case")
        XCTAssertEqual(QPSearchQuery.parse("is:link two  spaces").text, "two  spaces", "with tokens too")
        XCTAssertEqual(QPSearchQuery.parse("a is:x b").text, "a b")
        XCTAssertEqual(QPSearchQuery.parse("tail app:\"Visual Studio\"").text, "tail")
    }

    func testEmptyTokenValuesStayText() {
        let query = QPSearchQuery.parse("is: app:")
        XCTAssertEqual(query.text, "is: app:")
        XCTAssertFalse(query.hasTokens)
        XCTAssertTrue(QPSearchQuery.parse("   ").isEmpty)
    }

    // MARK: - Matching

    private func item(_ content: String = "hello world", keys: String? = nil, language: String? = nil,
                      app: (String, String)? = nil, favorite: Bool = false) -> CBItem {
        let item = CBItem(timestamp: Date(), content: content, itemType: .text, isFavorite: favorite)
        item.categoryKeys = keys
        item.languageCode = language
        item.sourceAppBundleID = app?.0
        item.sourceAppName = app?.1
        return item
    }

    private var docs: ItemCategory {
        var rule = ItemCategory.newRegex()
        rule.id = "docs-id"
        rule.name = "Documents"
        rule.pattern = "№"
        return rule
    }

    private func filter(_ text: String, selections: Set<CategorySelection> = []) -> ItemFilter {
        ItemFilter(categories: ItemCategory.builtIns + [docs], selections: selections, query: .parse(text))
    }

    func testEmptyFilterMatchesEverything() {
        XCTAssertTrue(filter("").isEmpty)
        XCTAssertTrue(filter("").matches(item()))
        XCTAssertTrue(filter("is:link").isCheap)
        XCTAssertFalse(filter("hello").isCheap)
    }

    func testIsTokenByIdOrNamePrefix() {
        let link = item(keys: ",link,")
        let doc = item(keys: ",docs-id,")
        XCTAssertTrue(filter("is:link").matches(link))
        XCTAssertFalse(filter("is:link").matches(doc))
        XCTAssertTrue(filter("is:doc").matches(doc))
        XCTAssertTrue(filter("is:documents").matches(doc))
        XCTAssertFalse(filter("is:nothing").matches(link), "an unknown category matches nothing")
    }

    func testIsTokenSkipsDisabledCategories() {
        var categories = ItemCategory.builtIns
        categories[0].isEnabled = false
        let f = ItemFilter(categories: categories, query: .parse("is:link"))
        XCTAssertFalse(f.matches(item(keys: ",link,")))
    }

    func testSpecialIsTokens() {
        XCTAssertTrue(filter("is:fav").matches(item(favorite: true)))
        XCTAssertFalse(filter("is:favorite").matches(item()))
        let titled = item()
        titled.title = "Bank"
        XCTAssertTrue(filter("is:titled").matches(titled))
        XCTAssertFalse(filter("is:title").matches(item()))
    }

    func testAppToken() {
        let safari = item(app: ("com.apple.Safari", "Safari"))
        XCTAssertTrue(filter("app:saf").matches(safari))
        XCTAssertTrue(filter("app:com.apple").matches(safari))
        XCTAssertFalse(filter("app:telegram").matches(safari))
        XCTAssertFalse(filter("app:safari").matches(item()))
    }

    func testLangToken() {
        let uk = item(language: "uk")
        XCTAssertTrue(filter("lang:uk").matches(uk))
        XCTAssertTrue(filter("lang:ukr").matches(uk))
        XCTAssertFalse(filter("lang:en").matches(uk))
        XCTAssertFalse(filter("lang:uk").matches(item()))
    }

    func testTokensAndTextCombine() {
        let match = item("Invoice for March", keys: ",link,", app: ("com.apple.Safari", "Safari"))
        XCTAssertTrue(filter("is:link app:safari march").matches(match))
        XCTAssertFalse(filter("is:link app:safari april").matches(match))
        XCTAssertFalse(filter("is:email app:safari march").matches(match))
    }

    func testSelection() {
        let link = item(keys: ",link,")
        XCTAssertTrue(filter("", selections: [.category("link")]).matches(link))
        XCTAssertFalse(filter("", selections: [.category("email")]).matches(link))
        XCTAssertFalse(filter("", selections: [.category("missing")]).matches(link))
        XCTAssertTrue(filter("", selections: [.language("uk")]).matches(item(language: "uk")))
        XCTAssertFalse(filter("", selections: [.language("uk")]).matches(item(language: "en")))
        let several = filter("", selections: [.category("email"), .language("uk")])
        XCTAssertTrue(several.matches(item(language: "uk")), "any chip that is on")
        XCTAssertTrue(several.matches(item(keys: ",email,")))
        XCTAssertFalse(several.matches(link))
    }

    // MARK: - Chip selection

    private let a = CategorySelection.category("a")
    private let b = CategorySelection.category("b")
    private let c = CategorySelection.language("uk")
    private var chips: [CategorySelection] { [a, b, c] }

    func testStepCyclesThroughNone() {
        var selection = ChipSelection()
        selection.step(1, in: chips)
        XCTAssertEqual(selection.selected, [a])
        selection.step(1, in: chips)
        XCTAssertEqual(selection.selected, [b])
        selection.step(1, in: chips)
        selection.step(1, in: chips)
        XCTAssertTrue(selection.isEmpty, "past the last chip comes none")
        selection.step(-1, in: chips)
        XCTAssertEqual(selection.selected, [c], "and backwards wraps to the last")
        selection.step(1, in: [])
        XCTAssertEqual(selection.selected, [c], "no chips: nothing changes")
    }

    func testExtendSelectsARunFromTheAnchor() {
        var selection = ChipSelection()
        selection.step(1, in: chips)            // a
        selection.extend(1, in: chips)          // a…b
        XCTAssertEqual(selection.selected, [a, b])
        selection.extend(1, in: chips)          // a…c
        selection.extend(1, in: chips)          // stays at the end
        XCTAssertEqual(selection.selected, [a, b, c])
        selection.extend(-1, in: chips)         // a…b again
        XCTAssertEqual(selection.selected, [a, b])
        selection.step(1, in: chips)            // a plain step ends the run
        XCTAssertEqual(selection.selected, [c])

        var fromNone = ChipSelection()
        fromNone.extend(-1, in: chips)
        XCTAssertEqual(fromNone.selected, [c], "from none, ⇧⌥← starts at the last chip")
        fromNone.extend(-1, in: chips)
        XCTAssertEqual(fromNone.selected, [b, c])
    }

    func testClicks() {
        var selection = ChipSelection()
        selection.click(a, adding: false)
        XCTAssertEqual(selection.selected, [a])
        selection.click(c, adding: true)
        XCTAssertEqual(selection.selected, [a, c])
        selection.click(a, adding: true)
        XCTAssertEqual(selection.selected, [c], "⇧-click removes a chip that is on")
        selection.click(b, adding: false)
        XCTAssertEqual(selection.selected, [b], "a plain click keeps only that chip")
        selection.click(b, adding: false)
        XCTAssertTrue(selection.isEmpty, "clicking the only chip again clears it")
    }

    func testKeepOnlyAvailableChips() {
        var selection = ChipSelection(selected: [a, c], cursor: c, anchor: a)
        selection.keep(only: [a, b])
        XCTAssertEqual(selection.selected, [a])
        XCTAssertNil(selection.cursor)
        XCTAssertEqual(selection.anchor, a)
        selection.keep(only: [])
        XCTAssertNil(selection.anchor)
    }

    // MARK: - Facets

    func testFacetCountsAddUp() {
        let a = FacetCounts(items: [item(keys: ",link,code,", language: "uk", app: ("x", "X")), item(keys: ",link,")])
        let b = FacetCounts(items: [item(language: "uk", app: ("x", "X"))])
        let sum = a + b
        XCTAssertEqual(sum.keys, ["link": 2, "code": 1])
        XCTAssertEqual(sum.languages, ["uk": 2])
        XCTAssertEqual(sum.apps, ["x": 2])
    }
}
