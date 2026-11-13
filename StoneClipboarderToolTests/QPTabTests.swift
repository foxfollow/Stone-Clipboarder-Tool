import XCTest
@testable import StoneClipboarderTool

final class QPTabTests: XCTestCase {

    func testCyclesThroughShownTabsOnly() {
        let withoutPasswords = QPTab.allCases.filter { $0 != .passwords }
        XCTAssertEqual(QPTab.files.next(in: withoutPasswords), .all)
        XCTAssertEqual(QPTab.all.previous(in: withoutPasswords), .files)

        XCTAssertEqual(QPTab.files.next(in: QPTab.allCases), .passwords)
        XCTAssertEqual(QPTab.passwords.next(in: QPTab.allCases), .all)
        XCTAssertEqual(QPTab.all.previous(in: QPTab.allCases), .passwords)
    }

    func testHiddenTabFallsBackToAll() {
        XCTAssertEqual(QPTab.passwords.next(in: [.all, .text]), .all)
        XCTAssertEqual(QPTab.passwords.previous(in: []), .all)
    }

    func testPasswordsListNoHistoryTypes() {
        XCTAssertNil(QPTab.passwords.itemTypes)
    }
}

@MainActor
final class QPVaultEditorModelTests: XCTestCase {

    func testRenameMoveAndDelete() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QPVaultEditorModelTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = VaultManager(
            store: VaultStore(root: root), keyProvider: InMemoryVaultKeyProvider(), fingerprintKeyProvider: InMemoryVaultKeyProvider(),
            authenticator: AlwaysYesAuthenticator())
        await manager.unlock()
        _ = manager.add(VaultPayload(itemType: .text, content: "a"))
        _ = manager.add(VaultPayload(itemType: .file, fileData: Data([1]), fileName: "b.key"))
        guard let second = manager.entries.last else { return XCTFail("no entries") }

        let model = QPVaultEditorModel(entry: second, vaultManager: manager)
        XCTAssertEqual(model.kindDescription, "b.key")
        XCTAssertEqual(model.position, 1)
        XCTAssertTrue(model.canMoveUp)
        XCTAssertFalse(model.canMoveDown)

        model.move(by: -1)
        XCTAssertEqual(model.position, 0)
        XCTAssertEqual(manager.entries.first?.id, second.id)

        model.title = "Deploy key"
        model.saveTitle()
        XCTAssertEqual(manager.entry(withID: second.id)?.title, "Deploy key")

        model.isConfirmingDelete = true
        XCTAssertTrue(model.confirmDelete())
        XCTAssertFalse(model.isConfirmingDelete)
        XCTAssertNil(manager.entry(withID: second.id))
    }
}

@MainActor
private final class AlwaysYesAuthenticator: VaultAuthenticator {
    func authenticate(reason: String) async -> Bool { true }
}

final class QPPreviewContentTests: XCTestCase {

    func testVaultEntryPreviewKeepsContentAndDetectsImageFiles() {
        let png = VaultPayload(
            itemType: .file, title: "Scan", fileData: Data([1]), fileName: "scan.png", fileUTI: "public.png")
        let preview = QPPreviewContent(entry: png)
        XCTAssertEqual(preview.itemType, .file)
        XCTAssertEqual(preview.title, "Scan")
        XCTAssertEqual(preview.fileName, "scan.png")
        XCTAssertTrue(preview.isImageFile)

        let key = VaultPayload(itemType: .file, fileData: Data([1]), fileName: "id_rsa", fileUTI: "public.data")
        XCTAssertFalse(QPPreviewContent(entry: key).isImageFile)
        XCTAssertFalse(QPPreviewContent(entry: VaultPayload(itemType: .text, content: "pw")).isImageFile)
    }

    func testHistoryItemPreview() {
        let item = CBItem(timestamp: Date(), content: "hello", itemType: .text)
        item.title = "Greeting"
        let preview = QPPreviewContent(item: item)
        XCTAssertEqual(preview.content, "hello")
        XCTAssertEqual(preview.title, "Greeting")
    }
}

final class QPTabOrderTests: XCTestCase {

    func testDefaultOrder() {
        XCTAssertEqual(QPTab.ordered([]), QPTab.allCases)
    }

    func testStoredOrderComesFirstAndMissingTabsFollow() {
        XCTAssertEqual(
            QPTab.ordered(["passwords", "text"]),
            [.passwords, .text, .all, .favorites, .images, .files])
    }

    func testUnknownAndRepeatedIdsAreDropped() {
        XCTAssertEqual(
            QPTab.ordered(["files", "bogus", "files", "all"]),
            [.files, .all, .favorites, .text, .images, .passwords])
    }

    func testRawValuesAreStable() {
        // Stored in UserDefaults: renaming one would reset the user's order.
        XCTAssertEqual(QPTab.allCases.map(\.rawValue), ["all", "favorites", "text", "images", "files", "passwords"])
    }

    @MainActor
    func testOrderIsSaved() {
        let isolated = IsolatedDefaults()
        defer { isolated.remove() }
        let settings = SettingsManager(defaults: isolated.defaults)
        XCTAssertEqual(settings.quickPickerTabOrder, [])
        settings.quickPickerTabOrder = ["passwords", "all"]
        XCTAssertEqual(SettingsManager(defaults: isolated.defaults).quickPickerTabOrder, ["passwords", "all"])
    }
}
