import SwiftData
import XCTest
@testable import StoneClipboarderTool

/// Classification on capture, rescans after rule changes, source apps,
/// chip counts and filtered search.
@MainActor
final class CBViewModelCategoryTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var viewModel: CBViewModel!
    private var isolated: IsolatedDefaults!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([CBItem.self])
        let config = ModelConfiguration("CBViewModelCategoryTests", schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
        viewModel = CBViewModel()
        viewModel.setModelContext(context)
        isolated = IsolatedDefaults()
    }

    override func tearDown() async throws {
        viewModel = nil
        context = nil
        container = nil
        isolated.remove()
        isolated = nil
        try await super.tearDown()
    }

    private let safari = CaptureSource(bundleID: "com.apple.Safari", name: "Safari")
    private let telegram = CaptureSource(bundleID: "ru.keepcoder.Telegram", name: "Telegram")

    private func allItems() throws -> [CBItem] {
        try context.fetch(FetchDescriptor<CBItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)]))
    }

    // MARK: - Capture

    func testNewTextIsClassifiedAndStamped() throws {
        viewModel.addTextItem(content: "https://example.com", source: safari)

        let item = try XCTUnwrap(try allItems().first)
        XCTAssertEqual(item.categoryKeySet, ["link", "link.full"])
        XCTAssertEqual(item.classificationStamp, viewModel.classifierRuleset.stamp)
        XCTAssertEqual(item.sourceAppBundleID, "com.apple.Safari")
        XCTAssertEqual(item.sourceAppName, "Safari")
    }

    func testRecopyKeepsKeysAndTakesTheLatestSource() throws {
        viewModel.addTextItem(content: "https://example.com", source: safari)
        viewModel.addTextItem(content: "https://example.com", source: telegram)
        viewModel.addTextItem(content: "https://example.com")

        let items = try allItems()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.sourceAppName, "Telegram", "no source keeps the last one")
        XCTAssertTrue(items.first?.hasCategoryKey("link") == true)
    }

    func testCapturedContentCarriesItsSource() async throws {
        viewModel.getClipboardManager().onClipboardChange?(.text("someone@example.com"), telegram)
        await waitUntil { (try? self.context.fetchCount(FetchDescriptor<CBItem>())) == 1 }

        let item = try XCTUnwrap(try allItems().first)
        XCTAssertEqual(item.sourceAppBundleID, telegram.bundleID)
        XCTAssertTrue(item.hasCategoryKey("email.full"))
    }

    func testClassifyWithoutAnImageResultClearsImageKeys() throws {
        let image = CBItem(timestamp: Date(), imageData: Data([1, 2, 3]), itemType: .image)
        image.categoryKeys = ",stale,"
        image.languageCode = "en"
        image.classify(with: viewModel.classifierRuleset)
        XCTAssertNil(image.categoryKeys)
        XCTAssertNil(image.languageCode)
        XCTAssertEqual(image.classificationStamp, viewModel.classifierRuleset.stamp)
    }

    func testCombinedItemsMergeTextAndImageResults() {
        let item = CBItem(timestamp: Date(), content: "Call +1 408 555 0123 now", imageData: Data([1]), itemType: .combined)
        item.classify(with: .empty, image: ImageClassifier.Result(keys: ["ocr", "face"], language: "uk"))
        XCTAssertTrue(item.hasCategoryKey("phone"))
        XCTAssertTrue(item.hasCategoryKey("face"))
        XCTAssertEqual(item.languageCode, "uk", "the image's language when the text has none")
        XCTAssertTrue(item.hasAnalyzableImage)
        XCTAssertEqual(item.analyzableImageData, Data([1]))
    }

    func testImageTextIsKeptAndSearchable() async throws {
        let image = CBItem(timestamp: Date(), imageData: Data([1]), itemType: .image)
        image.classify(with: .empty, image: ImageClassifier.Result(keys: ["ocr"], text: "  Quarterly report\nQ3 2026 \n"))
        context.insert(image)
        try context.save()

        XCTAssertEqual(image.recognizedText, "Quarterly report\nQ3 2026")
        XCTAssertEqual(image.recognizedTextSnippet, "Quarterly report · Q3 2026")
        XCTAssertTrue(image.matchesSearch("quarterly"))
        XCTAssertFalse(image.matchesSearch("quarterly", includingImageText: false))

        let found = await viewModel.searchItems(matching: "Q3 2026")
        XCTAssertEqual(found.count, 1)

        let settings = SettingsManager(defaults: isolated.defaults)
        settings.searchImageText = false
        viewModel.setSettingsManager(settings)
        let hidden = await viewModel.searchItems(matching: "Q3 2026")
        XCTAssertTrue(hidden.isEmpty)
        XCTAssertFalse(ItemFilter(query: .parse("quarterly"), searchImageText: false).matches(image))
        XCTAssertTrue(ItemFilter(query: .parse("quarterly")).matches(image))
    }

    func testAnImageWithoutTextKeepsEarlierText() {
        let image = CBItem(timestamp: Date(), imageData: Data([1]), itemType: .image)
        image.setRecognizedText("from the user's OCR")
        image.classify(with: .empty, image: ImageClassifier.Result())
        XCTAssertEqual(image.recognizedText, "from the user's OCR")

        image.setRecognizedText(String(repeating: "x", count: CBItem.maxRecognizedTextLength + 50))
        XCTAssertEqual(image.recognizedText?.count, CBItem.maxRecognizedTextLength)
        image.setRecognizedText("   ")
        XCTAssertNil(image.recognizedText)
        XCTAssertNil(image.recognizedTextSnippet)
    }

    func testTheUsersOCRStaysWithTheImage() throws {
        let image = CBItem(timestamp: Date(), imageData: Data([1]), itemType: .image)
        image.languageCode = nil
        let text = CBItem(timestamp: Date(), content: "plain", itemType: .text)
        context.insert(image)
        context.insert(text)
        try context.save()

        viewModel.rememberRecognizedText("Pay at https://bank.example.com", forItemWithID: image.persistentModelID)
        viewModel.rememberRecognizedText("ignored", forItemWithID: text.persistentModelID)

        XCTAssertEqual(image.recognizedText, "Pay at https://bank.example.com")
        XCTAssertTrue(image.hasCategoryKey("ocr"))
        XCTAssertTrue(image.hasCategoryKey("link"))
        XCTAssertFalse(image.hasCategoryKey("link.full"))
        XCTAssertNil(text.recognizedText, "only images keep recognized text")
    }

    func testImageFilesAreAnalyzableOtherFilesAreNot() {
        let png = CBItem(timestamp: Date(), fileData: Data([7]), fileName: "a.png", fileUTI: "public.png", itemType: .file)
        let zip = CBItem(timestamp: Date(), fileData: Data([7]), fileName: "a.zip", fileUTI: "public.zip-archive", itemType: .file)
        XCTAssertTrue(png.hasAnalyzableImage)
        XCTAssertEqual(png.analyzableImageData, Data([7]))
        XCTAssertFalse(zip.hasAnalyzableImage)
        XCTAssertNil(zip.analyzableImageData)
        XCTAssertNil(CBItem(timestamp: Date(), content: "x", itemType: .text).analyzableImageData)
    }

    func testCapturedImagesAreAnalyzedInTheBackground() async throws {
        let qr = try ImageClassifierTests.qrCode("https://stone.example.com/qr")
        viewModel.getClipboardManager().onClipboardChange?(.image(qr), safari)

        // The first Vision request of a run loads its models: allow a cold start.
        await waitUntil(timeout: 60) {
            (try? self.allItems().first?.hasCategoryKey("barcode")) == true
        }
        let item = try XCTUnwrap(try allItems().first)
        XCTAssertTrue(item.hasCategoryKey("barcode"))
        XCTAssertTrue(item.hasCategoryKey("link"))
        XCTAssertEqual(item.classificationStamp, viewModel.classifierRuleset.stamp)
    }

    func testTurningImageAnalysisOffClearsImageKeys() async throws {
        let qr = try ImageClassifierTests.qrCode("hello")
        context.insert(CBItem(timestamp: Date(), imageData: qr, itemType: .image))
        try context.save()
        await viewModel.reclassifyStaleItems()
        XCTAssertTrue(try XCTUnwrap(try allItems().first).hasCategoryKey("barcode"))

        viewModel.updateClassifierRules([], analyzeImages: false)
        await waitUntil { (try? self.allItems().first?.categoryKeys) == .some(nil) }

        XCTAssertNil(try XCTUnwrap(try allItems().first).categoryKeys)
    }

    // MARK: - Rescans

    func testOldItemsAreClassifiedByTheRescan() async throws {
        context.insert(CBItem(timestamp: Date(), content: "/Users/me/Desktop", itemType: .text))
        context.insert(CBItem(timestamp: Date(), imageData: Data([1]), itemType: .image))  // not decodable
        try context.save()

        let classified = await viewModel.reclassifyStaleItems()

        XCTAssertEqual(classified, 2)
        let text = try XCTUnwrap(try allItems().first { $0.itemType == .text })
        XCTAssertTrue(text.hasCategoryKey("path.full"))
        let second = await viewModel.reclassifyStaleItems()
        XCTAssertEqual(second, 0, "nothing left to do")
    }

    func testANewRegexRuleRescansTheHistory() async throws {
        viewModel.addTextItem(content: "№ 9351/2026")
        let settings = SettingsManager(defaults: isolated.defaults)
        viewModel.setSettingsManager(settings)

        var rule = ItemCategory.newRegex()
        rule.name = "Documents"
        rule.pattern = #"№\s*\d+/\d{4}"#
        settings.saveCategory(rule)
        await waitUntil { (try? self.allItems().first?.hasCategoryKey(rule.id)) == true }

        let item = try XCTUnwrap(try allItems().first)
        XCTAssertTrue(item.hasCategoryKey(rule.id))
        XCTAssertTrue(item.hasCategoryKey(ContentClassifier.fullKey(rule.id)))

        // Toggling or recoloring keeps the stamp.
        let stamp = viewModel.classifierRuleset.stamp
        rule.isEnabled = false
        rule.colorHex = "#000000"
        settings.saveCategory(rule)
        XCTAssertEqual(viewModel.classifierRuleset.stamp, stamp)

        settings.deleteCategory(id: rule.id)
        XCTAssertNotEqual(viewModel.classifierRuleset.stamp, stamp)
        await waitUntil { (try? self.allItems().first?.hasCategoryKey(rule.id)) == false }
        XCTAssertFalse(try XCTUnwrap(try allItems().first).hasCategoryKey(rule.id))
    }

    // MARK: - Counts and search

    func testFacetCountsPerType() throws {
        viewModel.addTextItem(content: "https://a.example.com", source: safari)
        viewModel.addTextItem(content: "https://b.example.com", source: telegram)
        let image = CBItem(timestamp: Date(), imageData: Data([1]), itemType: .image)
        image.sourceAppBundleID = safari.bundleID
        context.insert(image)
        try context.save()
        viewModel.refreshItemCounts()

        let all = viewModel.facetCounts(ofTypes: nil)
        XCTAssertEqual(all.keys["link"], 2)
        XCTAssertEqual(all.apps[safari.bundleID], 2)
        let images = viewModel.facetCounts(ofTypes: [.image, .combined])
        XCTAssertNil(images.keys["link"])
        XCTAssertEqual(images.apps[safari.bundleID], 1)

        viewModel.addTextItem(content: "https://c.example.com")
        XCTAssertEqual(viewModel.facetCounts(ofTypes: [.text]).keys["link"], 3, "a capture drops the cache")
    }

    func testFilteredSearch() async throws {
        viewModel.addTextItem(content: "https://example.com/invoice", source: safari)
        viewModel.addTextItem(content: "invoice text without a link", source: safari)
        viewModel.addTextItem(content: "https://example.com/other", source: telegram)

        var filter = ItemFilter(categories: ItemCategory.builtIns, query: .parse("is:link app:safari"))
        var found = await viewModel.searchItems(filter: filter)
        XCTAssertEqual(found.map(\.content), ["https://example.com/invoice"])

        filter = ItemFilter(categories: ItemCategory.builtIns, selections: [.category("link")], query: .parse("other"))
        found = await viewModel.searchItems(filter: filter, types: [.text])
        XCTAssertEqual(found.map(\.content), ["https://example.com/other"])

        found = await viewModel.searchItems(filter: ItemFilter())
        XCTAssertTrue(found.isEmpty, "an empty filter is not a search")
    }

    func testForgetSourceApps() throws {
        viewModel.addTextItem(content: "one", source: safari)
        viewModel.addTextItem(content: "two", source: telegram)

        viewModel.clearSourceApps()

        XCTAssertTrue(try allItems().allSatisfy { $0.sourceAppBundleID == nil && $0.sourceAppName == nil })
    }

    // MARK: - Helpers

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
