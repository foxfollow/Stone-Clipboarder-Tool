import SwiftData
import XCTest
@testable import StoneClipboarderTool

/// Tests for the v1.5.5 cleanup/refresh changes in CBViewModel:
/// - `refreshItemCounts()` splits totals into non-favorites vs favorites.
/// - `performItemCountCleanupCore(maxItems:)` (driven through `performManualCleanup()`)
///   removes only the oldest non-favorites and leaves favorites untouched.
@MainActor
final class CBViewModelCleanupTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var viewModel: CBViewModel!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([CBItem.self])
        let config = ModelConfiguration("CBViewModelTests", schema: schema, isStoredInMemoryOnly: true)
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

    // MARK: - refreshItemCounts

    func testRefreshItemCountsSplitsFavoritesAndNonFavorites() throws {
        insertItems(nonFavoriteCount: 4, favoriteCount: 2)
        try context.save()

        viewModel.refreshItemCounts()

        XCTAssertEqual(viewModel.totalItemCount, 4, "totalItemCount should only count non-favorites")
        XCTAssertEqual(viewModel.favoriteItemCount, 2, "favoriteItemCount should count favorites only")
    }

    func testRefreshItemCountsWithEmptyStore() {
        viewModel.refreshItemCounts()
        XCTAssertEqual(viewModel.totalItemCount, 0)
        XCTAssertEqual(viewModel.favoriteItemCount, 0)
    }

    func testRefreshItemCountsWithOnlyFavorites() throws {
        insertItems(nonFavoriteCount: 0, favoriteCount: 3)
        try context.save()

        viewModel.refreshItemCounts()

        XCTAssertEqual(viewModel.totalItemCount, 0)
        XCTAssertEqual(viewModel.favoriteItemCount, 3)
    }

    // MARK: - performItemCountCleanupCore (via performManualCleanup)

    func testManualCleanupRemovesOldestNonFavoritesAboveLimit() async throws {
        // 6 non-favorites with increasing timestamps (oldest first) and 2 favorites.
        let base = Date(timeIntervalSince1970: 1_000_000)
        for i in 0..<6 {
            context.insert(CBItem(timestamp: base.addingTimeInterval(Double(i)), content: "n\(i)", itemType: .text))
        }
        let fav1 = CBItem(timestamp: base.addingTimeInterval(-100), content: "fav-old", itemType: .text, isFavorite: true)
        let fav2 = CBItem(timestamp: base.addingTimeInterval(-50), content: "fav-newer", itemType: .text, isFavorite: true)
        context.insert(fav1)
        context.insert(fav2)
        try context.save()

        let settings = makeSettingsManager(maxItemsToKeep: 3, enableAutoCleanup: false)
        viewModel.setSettingsManager(settings)

        viewModel.performManualCleanup()

        // Cleanup defers its delete onto the next main-queue tick.
        try await waitForMainQueueDrain()

        let remainingNonFav = try context.fetchCount(
            FetchDescriptor<CBItem>(predicate: #Predicate { !$0.isFavorite })
        )
        let remainingFav = try context.fetchCount(
            FetchDescriptor<CBItem>(predicate: #Predicate { $0.isFavorite })
        )
        XCTAssertEqual(remainingNonFav, 3, "Non-favorites should be capped at maxItemsToKeep")
        XCTAssertEqual(remainingFav, 2, "Favorites must never be deleted by cleanup")

        // The 3 newest non-favorites should remain.
        let kept = try context.fetch(
            FetchDescriptor<CBItem>(
                predicate: #Predicate { !$0.isFavorite },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        )
        XCTAssertEqual(kept.map { $0.content }, ["n5", "n4", "n3"])
    }

    func testManualCleanupNoOpWhenUnderLimit() async throws {
        insertItems(nonFavoriteCount: 2, favoriteCount: 1)
        try context.save()

        let settings = makeSettingsManager(maxItemsToKeep: 10, enableAutoCleanup: false)
        viewModel.setSettingsManager(settings)

        viewModel.performManualCleanup()
        try await waitForMainQueueDrain()

        let total = try context.fetchCount(FetchDescriptor<CBItem>())
        XCTAssertEqual(total, 3, "Nothing should be deleted when count is below the limit")
    }

    func testManualCleanupOnlyFavoritesIsNoOp() async throws {
        insertItems(nonFavoriteCount: 0, favoriteCount: 5)
        try context.save()

        let settings = makeSettingsManager(maxItemsToKeep: 1, enableAutoCleanup: false)
        viewModel.setSettingsManager(settings)

        viewModel.performManualCleanup()
        try await waitForMainQueueDrain()

        let favCount = try context.fetchCount(
            FetchDescriptor<CBItem>(predicate: #Predicate { $0.isFavorite })
        )
        XCTAssertEqual(favCount, 5, "Favorites must not count against the cap and must not be deleted")
    }

    func testManualCleanupClearsSelectedItemWhenItIsDeleted() async throws {
        let base = Date(timeIntervalSince1970: 2_000_000)
        var inserted: [CBItem] = []
        for i in 0..<5 {
            let item = CBItem(timestamp: base.addingTimeInterval(Double(i)), content: "x\(i)", itemType: .text)
            context.insert(item)
            inserted.append(item)
        }
        try context.save()

        // Select the oldest item — it should be evicted by cleanup.
        viewModel.selectedItem = inserted.first
        XCTAssertNotNil(viewModel.selectedItem)

        let settings = makeSettingsManager(maxItemsToKeep: 2, enableAutoCleanup: false)
        viewModel.setSettingsManager(settings)

        viewModel.performManualCleanup()
        try await waitForMainQueueDrain()

        XCTAssertNil(viewModel.selectedItem, "Selected item must be cleared before its backing data is detached")
    }

    // MARK: - Helpers

    private func insertItems(nonFavoriteCount: Int, favoriteCount: Int) {
        let base = Date(timeIntervalSince1970: 3_000_000)
        for i in 0..<nonFavoriteCount {
            context.insert(CBItem(timestamp: base.addingTimeInterval(Double(i)), content: "nf\(i)", itemType: .text))
        }
        for i in 0..<favoriteCount {
            context.insert(CBItem(
                timestamp: base.addingTimeInterval(Double(1000 + i)),
                content: "f\(i)",
                itemType: .text,
                isFavorite: true
            ))
        }
    }

    private func makeSettingsManager(maxItemsToKeep: Int, enableAutoCleanup: Bool) -> SettingsManager {
        let defaults = UserDefaults.standard
        defaults.set(maxItemsToKeep, forKey: "maxItemsToKeep")
        defaults.set(enableAutoCleanup, forKey: "enableAutoCleanup")
        return SettingsManager()
    }

    /// Cleanup enqueues its delete onto `DispatchQueue.main.async`. To observe its effect
    /// from a `@MainActor` test we need to yield the main queue at least once.
    private func waitForMainQueueDrain() async throws {
        let expectation = expectation(description: "main queue drained")
        DispatchQueue.main.async { expectation.fulfill() }
        await fulfillment(of: [expectation], timeout: 2)
    }
}
