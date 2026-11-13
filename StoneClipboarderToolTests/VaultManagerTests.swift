import CryptoKit
import XCTest
@testable import StoneClipboarderTool

@MainActor
private final class StubAuthenticator: VaultAuthenticator {
    var answer = true
    private(set) var calls = 0

    func authenticate(reason: String) async -> Bool {
        calls += 1
        return answer
    }
}

private struct StubKeyError: Error {}

@MainActor
final class VaultManagerTests: XCTestCase {

    private var root: URL!
    private var keyProvider: InMemoryVaultKeyProvider!
    private var authenticator: StubAuthenticator!
    private var clock = Date(timeIntervalSince1970: 100_000)
    private var isolated: IsolatedDefaults!
    private var settings: SettingsManager!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaultManagerTests-\(UUID().uuidString)", isDirectory: true)
        keyProvider = InMemoryVaultKeyProvider()
        authenticator = StubAuthenticator()
        isolated = IsolatedDefaults()
        settings = SettingsManager(defaults: isolated.defaults)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        isolated.remove()
        super.tearDown()
    }

    private func makeManager() -> VaultManager {
        let manager = VaultManager(
            store: VaultStore(root: root), keyProvider: keyProvider, authenticator: authenticator,
            now: { [unowned self] in self.clock })
        manager.settingsManager = settings
        return manager
    }

    func testStartsLockedAndUnlocks() async {
        let manager = makeManager()
        XCTAssertFalse(manager.isUnlocked)
        XCTAssertEqual(manager.add(VaultPayload(itemType: .text, content: "pw")), .locked)

        let unlocked = await manager.unlock()
        XCTAssertTrue(unlocked)
        XCTAssertTrue(manager.isUnlocked)
        XCTAssertFalse(manager.isAuthenticating)
        XCTAssertTrue(keyProvider.hasKey)
    }

    func testCancelledAuthenticationStaysLocked() async {
        authenticator.answer = false
        let manager = makeManager()
        let unlocked = await manager.unlock()
        XCTAssertFalse(unlocked)
        XCTAssertFalse(manager.isUnlocked)
        XCTAssertFalse(keyProvider.hasKey)
    }

    func testKeyFailureStaysLockedWithMessage() async {
        keyProvider.failure = StubKeyError()
        let manager = makeManager()
        let unlocked = await manager.unlock()
        XCTAssertFalse(unlocked)
        XCTAssertNotNil(manager.statusMessage)
    }

    func testSecondUnlockWithinWindowDoesNotAskAgain() async {
        let manager = makeManager()
        await manager.unlock()
        clock.addTimeInterval(30 * 60)
        await manager.unlock()
        XCTAssertEqual(authenticator.calls, 1)
    }

    func testRelocksAfterIdleTimeout() async {
        settings.vaultRelockMinutes = 15
        let manager = makeManager()
        await manager.unlock()
        _ = manager.add(VaultPayload(itemType: .text, content: "pw"))

        clock.addTimeInterval(14 * 60)
        manager.checkExpiry()
        XCTAssertTrue(manager.isUnlocked)

        manager.noteUse()  // sliding: use restarts the window
        clock.addTimeInterval(14 * 60)
        manager.checkExpiry()
        XCTAssertTrue(manager.isUnlocked)

        clock.addTimeInterval(16 * 60)
        manager.checkExpiry()
        XCTAssertFalse(manager.isUnlocked)
        XCTAssertTrue(manager.entries.isEmpty)
    }

    func testLockDropsEntriesAndUnlockRestoresThem() async {
        let manager = makeManager()
        await manager.unlock()
        _ = manager.add(VaultPayload(itemType: .text, title: "Mail", content: "pw"))
        manager.lock()
        XCTAssertTrue(manager.entries.isEmpty)
        XCTAssertTrue(manager.hasStoredEntries)

        await manager.unlock()
        XCTAssertEqual(manager.entries.map(\.title), ["Mail"])
        XCTAssertEqual(authenticator.calls, 2)
    }

    func testEntriesSurviveANewManager() async {
        let first = makeManager()
        await first.unlock()
        _ = first.add(VaultPayload(itemType: .file, fileData: Data([1, 2]), fileName: "id_rsa"))

        let second = makeManager()
        await second.unlock()
        XCTAssertEqual(second.entries.first?.fileName, "id_rsa")
    }

    func testAddRejectsDuplicatesAndEmptyContent() async {
        let manager = makeManager()
        await manager.unlock()
        guard case .added(let id) = manager.add(VaultPayload(itemType: .text, title: "A", content: "pw")) else {
            return XCTFail("expected an added entry")
        }
        XCTAssertEqual(manager.add(VaultPayload(itemType: .text, title: "B", content: "pw")), .duplicate(id))
        XCTAssertEqual(manager.add(VaultPayload(itemType: .text, content: "")), .nothingToAdd)
        XCTAssertEqual(manager.entries.count, 1)
    }

    func testAddAppendsInOrder() async {
        let manager = makeManager()
        await manager.unlock()
        _ = manager.add(VaultPayload(itemType: .text, content: "1", orderIndex: 7))
        _ = manager.add(VaultPayload(itemType: .text, content: "2", orderIndex: 0))
        XCTAssertEqual(manager.entries.map(\.orderIndex), [0, 1])
        XCTAssertEqual(manager.entries.map(\.content), ["1", "2"])
    }

    func testRenameDeleteAndMove() async throws {
        let manager = makeManager()
        await manager.unlock()
        for text in ["a", "b", "c"] {
            _ = manager.add(VaultPayload(itemType: .text, content: text))
        }
        let ids = manager.entries.map(\.id)

        XCTAssertTrue(manager.rename(ids[0], to: "  First  "))
        XCTAssertEqual(manager.entry(withID: ids[0])?.title, "First")
        XCTAssertTrue(manager.rename(ids[0], to: " "))
        XCTAssertNil(manager.entry(withID: ids[0])?.title)

        XCTAssertTrue(manager.move(ids[2], by: -2))
        XCTAssertEqual(manager.entries.map(\.content), ["c", "a", "b"])
        XCTAssertFalse(manager.move(ids[2], by: -1))  // already first
        XCTAssertFalse(manager.move(UUID(), by: 1))

        XCTAssertTrue(manager.delete(ids[0]))
        XCTAssertFalse(manager.delete(ids[0]))
        XCTAssertEqual(manager.entries.map(\.content), ["c", "b"])

        // The order is stored, not only kept in memory.
        manager.lock()
        await manager.unlock()
        XCTAssertEqual(manager.entries.map(\.content), ["c", "b"])
    }

    func testDeleteAllRemovesFilesAndKey() async {
        let manager = makeManager()
        await manager.unlock()
        _ = manager.add(VaultPayload(itemType: .text, content: "pw"))
        manager.deleteAll()
        XCTAssertFalse(manager.isUnlocked)
        XCTAssertFalse(manager.hasStoredEntries)
        XCTAssertFalse(keyProvider.hasKey)
    }

    func testEntriesSealedWithALostKeyAreCounted() async {
        let manager = makeManager()
        await manager.unlock()
        _ = manager.add(VaultPayload(itemType: .text, content: "pw"))
        manager.lock()
        try? keyProvider.deleteKey()  // a new key is made on the next unlock

        await manager.unlock()
        XCTAssertTrue(manager.entries.isEmpty)
        XCTAssertEqual(manager.unreadableCount, 1)
    }

    func testMakeForAppStaysOutOfTheRealVaultUnderTests() {
        // The test host must never read the real keychain or vault folder.
        let manager = VaultManager.makeForApp()
        XCTAssertFalse(manager.isUnlocked)
        XCTAssertFalse(manager.hasStoredEntries)
    }
}

final class VaultSettingsTests: XCTestCase {

    @MainActor
    func testDefaultsAndClamping() {
        let isolated = IsolatedDefaults()
        defer { isolated.remove() }
        let settings = SettingsManager(defaults: isolated.defaults)
        XCTAssertTrue(settings.showPasswordsTab)
        XCTAssertEqual(settings.vaultRelockMinutes, 60)
        XCTAssertEqual(settings.vaultClipboardClearSeconds, 30)

        settings.vaultRelockMinutes = 0
        settings.vaultClipboardClearSeconds = -5
        settings.showPasswordsTab = false
        XCTAssertEqual(settings.vaultRelockMinutes, 1)
        XCTAssertEqual(settings.vaultClipboardClearSeconds, 0)

        let reloaded = SettingsManager(defaults: isolated.defaults)
        XCTAssertEqual(reloaded.vaultRelockMinutes, 1)
        XCTAssertEqual(reloaded.vaultClipboardClearSeconds, 0)
        XCTAssertFalse(reloaded.showPasswordsTab)
    }
}
