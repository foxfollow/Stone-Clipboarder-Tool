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
            store: VaultStore(root: root), keyProvider: InMemoryVaultKeyProvider(),
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
