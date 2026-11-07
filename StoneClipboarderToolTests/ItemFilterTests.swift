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

    private func filter(_ text: String, selection: CategorySelection? = nil) -> ItemFilter {
        ItemFilter(categories: ItemCategory.builtIns + [docs], selection: selection, query: .parse(text))
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
        XCTAssertTrue(filter("", selection: .category("link")).matches(link))
        XCTAssertFalse(filter("", selection: .category("email")).matches(link))
        XCTAssertFalse(filter("", selection: .category("missing")).matches(link))
        XCTAssertTrue(filter("", selection: .language("uk")).matches(item(language: "uk")))
        XCTAssertFalse(filter("", selection: .language("uk")).matches(item(language: "en")))
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
