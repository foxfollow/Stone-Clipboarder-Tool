import SwiftData
import XCTest
@testable import StoneClipboarderTool

/// History copies of content saved in Passwords leave the history.
@MainActor
final class CBViewModelVaultTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var viewModel: CBViewModel!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([CBItem.self])
        let config = ModelConfiguration("CBViewModelVaultTests", schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
        viewModel = CBViewModel()
        viewModel.setModelContext(context)
    }

    override func tearDown() async throws {
        viewModel = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    func testRemovesOnlyCopiesOfSavedEntries() async throws {
        viewModel.addTextItem(content: "379696")
        viewModel.addTextItem(content: " 379696")
        viewModel.addTextItem(content: "keep me")

        let removed = viewModel.removeHistoryCopies(of: [
            VaultPayload(itemType: .text, content: "379696").contentKey,
            VaultPayload(itemType: .text, content: "not in history").contentKey,
        ])
        XCTAssertEqual(removed, 1)

        // The context delete happens on the next main-queue turn.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        let left = try context.fetch(FetchDescriptor<CBItem>()).compactMap(\.content).sorted()
        XCTAssertEqual(left, [" 379696", "keep me"])
    }
}
