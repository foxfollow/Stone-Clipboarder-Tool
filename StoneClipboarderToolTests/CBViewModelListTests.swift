import SwiftData
import XCTest
@testable import StoneClipboarderTool

/// How CBViewModel.items is loaded, paged and refreshed.
@MainActor
final class CBViewModelListTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var viewModel: CBViewModel!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([CBItem.self])
        let config = ModelConfiguration("CBViewModelListTests", schema: schema, isStoredInMemoryOnly: true)
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

    func testResetLoadsTheNewestThirtyNewestFirst() throws {
        try insertTextItems(count: 50)

        viewModel.fetchItems(reset: true)

        XCTAssertEqual(viewModel.items.count, 30)
        XCTAssertEqual(viewModel.items.first?.content, "item 49")
        XCTAssertEqual(viewModel.items.last?.content, "item 20")
    }

    func testRefreshAfterACopyKeepsTheScrolledDepth() async throws {
        try insertTextItems(count: 150)
        viewModel.fetchItems(reset: true)
        viewModel.loadMoreItems()
        await waitUntil { self.viewModel.items.count == 130 }
        XCTAssertEqual(viewModel.items.count, 130)

        viewModel.addTextItem(content: "brand new")

        XCTAssertEqual(viewModel.items.first?.content, "brand new")
        XCTAssertEqual(viewModel.items.count, 130, "a copy must not collapse the list back to 30 rows")
    }

    func testNextPageAfterADeleteSkipsNothing() async throws {
        try insertTextItems(count: 40)
        viewModel.fetchItems(reset: true)
        viewModel.deleteItem(try XCTUnwrap(viewModel.items.first))  // "item 39"
        await waitForMainQueueDrain()

        viewModel.loadMoreItems()
        await waitUntil { !self.viewModel.isLoadingMore && self.viewModel.items.count > 29 }

        let contents = viewModel.items.compactMap(\.content)
        XCTAssertEqual(contents.count, 39)
        XCTAssertEqual(Set(contents).count, 39, "no duplicates")
        XCTAssertEqual(contents, (0..<39).reversed().map { "item \($0)" }, "no gaps")
    }

    func testLoadMoreStopsAtTheEnd() async throws {
        try insertTextItems(count: 35)
        viewModel.fetchItems(reset: true)

        viewModel.loadMoreItems()
        await waitUntil { self.viewModel.items.count == 35 && !self.viewModel.isLoadingMore }
        viewModel.loadMoreItems()
        await waitForMainQueueDrain()

        XCTAssertEqual(viewModel.items.count, 35)
        XCTAssertFalse(viewModel.isLoadingMore)
    }

    func testSettingTheContextDoesNotStartASecondFetch() {
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertFalse(viewModel.isLoadingMore, "only performSetup loads the first rows")
    }

    // MARK: - Helpers

    private func insertTextItems(count: Int) throws {
        let base = Date(timeIntervalSince1970: 5_000_000)
        for i in 0..<count {
            context.insert(CBItem(timestamp: base.addingTimeInterval(Double(i)), content: "item \(i)", itemType: .text))
        }
        try context.save()
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func waitForMainQueueDrain() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
