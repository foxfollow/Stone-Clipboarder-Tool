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

    func testRemovesEveryCopyIncludingOlderDuplicates() async throws {
        // Two identical rows, as left by versions before deduplication.
        context.insert(CBItem(timestamp: Date(timeIntervalSince1970: 1), content: "secret", itemType: .text))
        context.insert(CBItem(timestamp: Date(timeIntervalSince1970: 2), content: "secret", itemType: .text))
        context.insert(CBItem(timestamp: Date(timeIntervalSince1970: 3), content: "other", itemType: .text))
        try context.save()

        let key = VaultPayload(itemType: .text, content: "secret").contentKey
        XCTAssertEqual(viewModel.removeHistoryCopies(of: [key, key]), 2, "each copy once")
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<CBItem>()).compactMap(\.content), ["other"])
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

/// Delete from the ⌥E editor: asking never deletes, only confirming does.
@MainActor
final class QPItemEditorDeleteTests: XCTestCase {

    func testDeleteNeedsConfirmation() async throws {
        let schema = Schema([CBItem.self])
        let config = ModelConfiguration("QPItemEditorDeleteTests", schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let viewModel = CBViewModel()
        viewModel.setModelContext(context)
        viewModel.addTextItem(content: "note")
        let item = try XCTUnwrap(viewModel.existingItem(matching: CBItem.ContentKey(type: .text, content: "note")))

        let editor = QPItemEditorModel(item: item, viewModel: viewModel) {}
        editor.confirmDelete()  // not asked yet: nothing happens
        editor.requestDelete()
        editor.requestDelete()  // a repeated key press only asks again
        XCTAssertTrue(editor.isConfirmingDelete)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CBItem>()), 1)

        editor.confirmDelete()
        XCTAssertFalse(editor.isConfirmingDelete)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CBItem>()), 0)
    }
}
