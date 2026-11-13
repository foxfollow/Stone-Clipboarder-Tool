import SwiftData
import XCTest
@testable import StoneClipboarderTool

/// Clearing or cleaning up the history, or recovering a corrupt store,
/// must never touch the Passwords vault.
@MainActor
final class VaultSurvivesCleanupTests: XCTestCase {

    func testStoreRecoveryDeletesOnlyThatStore() {
        let folder = [
            "ClipboardHistory.store", "ClipboardHistory.store-wal", "ClipboardHistory.store-shm",
            ".ClipboardHistory_SUPPORT", "Settings.store", "Settings.store-wal", "Vault",
            "StoneClipboarder_errors.log", "Previews",
        ]
        XCTAssertEqual(
            ModelContainerFactory.recoveryFiles(of: "ClipboardHistory.store", among: folder),
            ["ClipboardHistory.store", "ClipboardHistory.store-wal", "ClipboardHistory.store-shm"])
        XCTAssertEqual(
            ModelContainerFactory.recoveryFiles(of: "Settings.store", among: folder),
            ["Settings.store", "Settings.store-wal"])
    }

    func testVaultNeverMatchesARecoveryFile() {
        let vault = VaultStore.defaultRoot.lastPathComponent
        XCTAssertEqual(vault, "Vault")
        for store in ["ClipboardHistory.store", "Settings.store"] {
            XCTAssertFalse(ModelContainerFactory.recoveryFiles(of: store, among: [vault, vault + ".store"]).contains(vault))
        }
    }

    func testDeletingAndCleaningUpTheHistoryKeepsPasswords() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaultSurvivesCleanupTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = VaultCrypto.makeKey()
        let store = VaultStore(root: root)
        try store.save(VaultPayload(itemType: .text, content: "pw"), with: key)

        let schema = Schema([CBItem.self])
        let config = ModelConfiguration("VaultSurvivesCleanupTests", schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let viewModel = CBViewModel()
        viewModel.setModelContext(ModelContext(container))
        viewModel.addTextItem(content: "pw")
        viewModel.addTextItem(content: "other")

        viewModel.performManualCleanup()
        viewModel.deleteAllItems()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }

        XCTAssertEqual(store.loadAll(with: key).entries.map(\.content), ["pw"])
    }
}
