import XCTest
@testable import ImageIntact

/// Verifies the injectable `BookmarkManager.store` seam: bookmark persistence
/// goes through the injected `UserDefaults`, never `.standard`, when a test has
/// pointed the seam at an isolated suite. This is what makes the bookmark tests
/// parallel-safe and stops them from clobbering a developer's real bookmarks.
@MainActor
final class BookmarkManagerStoreTests: IsolatedDefaultsTestCase {

    private let key = BookmarkManager.destinationKeys[0]   // "dest1Bookmark"

    /// While a test is running, the seam points at the per-test suite.
    func testStoreIsTheInjectedSuiteDuringTest() {
        XCTAssertTrue(BookmarkManager.store === defaults,
                      "BookmarkManager.store should be the per-test isolated suite")
        XCTAssertFalse(BookmarkManager.store === UserDefaults.standard,
                       "BookmarkManager.store must not be .standard during an isolated test")
    }

    /// saveBookmark writes into the injected suite and leaves `.standard` untouched.
    func testSaveWritesToInjectedStoreNotStandard() throws {
        let dir = try makeTempDir()
        // Capture .standard BEFORE so we can prove it is unchanged regardless of
        // whatever the developer's real defaults happen to hold for this key.
        let standardBefore = UserDefaults.standard.data(forKey: key)

        BookmarkManager.saveBookmark(url: dir, key: key)

        XCTAssertNotNil(defaults.data(forKey: key),
                        "bookmark should be written into the injected suite")
        XCTAssertEqual(UserDefaults.standard.data(forKey: key), standardBefore,
                       ".standard must be untouched by an isolated save")
    }

    /// loadBookmark reads back the bookmark written through the injected suite.
    func testLoadReadsFromInjectedStore() throws {
        let dir = try makeTempDir()
        BookmarkManager.saveBookmark(url: dir, key: key)

        let loaded = BookmarkManager.loadBookmark(forKey: key)
        XCTAssertNotNil(loaded, "loadBookmark should resolve the bookmark from the injected suite")
    }

    /// loadDestinationBookmarks counts only what the injected suite holds.
    func testLoadDestinationBookmarksReadsInjectedStore() throws {
        let d1 = try makeTempDir()
        let d2 = try makeTempDir()
        BookmarkManager.saveBookmark(url: d1, key: BookmarkManager.destinationKeys[0])
        BookmarkManager.saveBookmark(url: d2, key: BookmarkManager.destinationKeys[1])

        let dests = BookmarkManager.loadDestinationBookmarks()
        XCTAssertEqual(dests.count, 2, "should load exactly the two destinations saved to the suite")
    }

    /// clearBookmark removes the key from the injected suite.
    func testClearBookmarkRemovesFromInjectedStore() throws {
        let dir = try makeTempDir()
        BookmarkManager.saveBookmark(url: dir, key: key)
        XCTAssertNotNil(defaults.data(forKey: key))

        BookmarkManager.clearBookmark(forKey: key)
        XCTAssertNil(defaults.data(forKey: key), "clearBookmark should remove the key from the suite")
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookmarkStoreTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
