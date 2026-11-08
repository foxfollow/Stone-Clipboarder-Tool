import SwiftData
import XCTest
@testable import StoneClipboarderTool

/// The made-up history behind demo mode and the landing screenshots.
@MainActor
final class DemoDataTests: XCTestCase {

    func testTheDemoHistoryCoversEveryKindOfRow() throws {
        let schema = Schema([CBItem.self])
        let container = try ModelContainer(
            for: schema, configurations: [ModelConfiguration("DemoDataTests", schema: schema, isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let ruleset = ContentClassifier.Ruleset(rules: [try XCTUnwrap(DemoData.documentsRule.regexRule)])

        try DemoData.fill(context, ruleset: ruleset)

        let items = try context.fetch(FetchDescriptor<CBItem>())
        XCTAssertGreaterThan(items.count, 100, "enough for realistic counts")
        XCTAssertEqual(items.filter(\.isFavorite).count, 2)
        XCTAssertTrue(items.contains { $0.displayTitle != nil })
        XCTAssertTrue(items.contains { $0.itemType == .file })
        XCTAssertTrue(items.contains { $0.hasCategoryKey("barcode") && $0.barcodeText != nil })
        XCTAssertTrue(items.contains { $0.hasCategoryKey("ocr") && $0.recognizedText != nil })
        XCTAssertTrue(items.contains { $0.hasCategoryKey(DemoData.documentsRule.id) })
        XCTAssertTrue(items.contains { $0.languageCode == "uk" })
        XCTAssertTrue(items.allSatisfy { $0.sourceAppBundleID != nil })
        XCTAssertTrue(items.allSatisfy { $0.classificationStamp == ruleset.stamp })
    }

    func testDemoSettingsAreSeparateFromTheRealOnes() {
        let isolated = IsolatedDefaults()
        defer { isolated.remove() }
        DemoData.presetSettings(in: isolated.defaults)
        let settings = SettingsManager(defaults: isolated.defaults)
        DemoData.addCategories(to: settings)

        XCTAssertTrue(settings.showMainWindow)
        XCTAssertFalse(settings.showInMenubar)
        XCTAssertFalse(settings.enableHotkeys)
        XCTAssertTrue(settings.itemCategories.contains(DemoData.documentsRule))
        XCTAssertTrue(settings.itemCategories.contains(DemoData.browsersGroup))
        XCTAssertNotEqual(DemoData.defaultsSuite, Bundle.main.bundleIdentifier, "never the real preferences")
        XCTAssertFalse(AppEnvironment.isDemo, "tests don't run as a demo")
        XCTAssertNil(AppEnvironment.screenshotsDirectory)
    }

    func testPicturesAreImages() {
        XCTAssertNotNil(NSImage(data: DemoData.screenshotImage()))
        XCTAssertNotNil(NSImage(data: DemoData.qrImage("https://example.com")))
    }
}
