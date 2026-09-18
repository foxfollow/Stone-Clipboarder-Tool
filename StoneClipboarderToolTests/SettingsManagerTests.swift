import XCTest
@testable import StoneClipboarderTool

@MainActor
final class SettingsManagerTests: XCTestCase {

    private var isolated: IsolatedDefaults!
    private var defaults: UserDefaults { isolated.defaults }

    override func setUp() async throws {
        try await super.setUp()
        isolated = IsolatedDefaults()
    }

    override func tearDown() async throws {
        isolated.remove()
        isolated = nil
        try await super.tearDown()
    }

    // MARK: - Defaults and persistence

    func testFreshInstallDefaults() {
        let settings = SettingsManager(defaults: defaults)
        XCTAssertTrue(settings.showInMenubar)
        XCTAssertTrue(settings.showMainWindow)
        XCTAssertEqual(settings.clipboardCaptureMode, .textOnly)
        XCTAssertEqual(settings.maxItemsToKeep, 300)
        XCTAssertEqual(settings.typePasteCharDelayMs, 5)
        XCTAssertEqual(settings.quickLookMode, .native)
    }

    func testChangesArePersisted() {
        let settings = SettingsManager(defaults: defaults)
        settings.maxItemsToKeep = 1200
        settings.clipboardCaptureMode = .bothAsOne

        XCTAssertEqual(defaults.integer(forKey: "maxItemsToKeep"), 1200)
        XCTAssertEqual(SettingsManager(defaults: defaults).clipboardCaptureMode, .bothAsOne)
    }

    func testUnknownStoredEnumFallsBackToDefault() {
        defaults.set("gone", forKey: "quickLookMode")
        XCTAssertEqual(SettingsManager(defaults: defaults).quickLookMode, .native)
    }

    // MARK: - The app must stay reachable

    func testBothHiddenInStorageIsRepairedOnLaunch() {
        defaults.set(false, forKey: "showInMenubar")
        defaults.set(false, forKey: "showMainWindow")
        XCTAssertTrue(SettingsManager(defaults: defaults).showMainWindow)
    }

    func testHidingTheMenuBarItemWhileTheWindowIsHiddenBringsTheWindowBack() {
        let settings = SettingsManager(defaults: defaults)
        settings.showMainWindow = false
        settings.showInMenubar = false
        XCTAssertTrue(settings.showMainWindow)
    }

    // MARK: - Migrations and clamps

    func testPreferTextOverImageMigratesToCaptureMode() {
        defaults.set(false, forKey: "preferTextOverImage")
        let settings = SettingsManager(defaults: defaults)
        XCTAssertEqual(settings.clipboardCaptureMode, .imageOnly)
        XCTAssertEqual(defaults.string(forKey: "clipboardCaptureMode"), "imageOnly")
        XCTAssertNil(defaults.object(forKey: "preferTextOverImage"))
    }

    func testNegativeValuesAreClampedToZero() {
        let settings = SettingsManager(defaults: defaults)
        settings.typePasteCharDelayMs = -5
        settings.pinMaxConcurrent = -1
        XCTAssertEqual(settings.typePasteCharDelayMs, 0)
        XCTAssertEqual(settings.pinMaxConcurrent, 0)
        XCTAssertEqual(defaults.integer(forKey: "typePasteCharDelayMs"), 0)
    }

    func testLegacyQuickPickerPositionKeysAreRemoved() {
        defaults.set(485.0, forKey: "QuickPickerWindowX")
        defaults.set(171.0, forKey: "QuickPickerWindowY")
        defaults.set(true, forKey: "QuickPickerHasValidPosition")

        _ = SettingsManager(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: "QuickPickerWindowX"))
        XCTAssertNil(defaults.object(forKey: "QuickPickerWindowY"))
        XCTAssertNil(defaults.object(forKey: "QuickPickerHasValidPosition"))
    }
}
