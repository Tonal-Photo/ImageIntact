import XCTest
@testable import ImageIntact

/// Base class that isolates per-test `UserDefaults` so tests never share the
/// on-disk `.standard` domain — the source of the parallel-execution bookmark
/// races (see `.planning/design/test-defaults-isolation.md`).
///
/// Each test gets its own `UserDefaults(suiteName:)`. `BookmarkManager.store`
/// (the production bookmark-persistence seam) is pointed at that suite for the
/// duration of the test and reset to `.standard` in tearDown. The suite is then
/// removed entirely. A developer's real saved bookmarks in `.standard` are never
/// touched, and parallel XCTest worker processes never collide on the bookmark
/// domain.
///
/// NOTE: This isolates the bookmark domain only. The `Fast` test plan still runs
/// serially (`parallelizable: false`) because `PreferencesManager`/`@AppStorage`
/// state remains on `.standard` and is not yet isolated. Applying the same seam
/// to preferences and re-enabling parallel execution is tracked as AMUX-456.
///
/// Subclasses MUST call `try await super.setUp()` / `try await super.tearDown()`.
/// Bookmark-key reads/writes inside a test MUST use `defaults` (the injected
/// suite), NOT `UserDefaults.standard`, so production `BookmarkManager` — which
/// reads `BookmarkManager.store` — sees them.
@MainActor
class IsolatedDefaultsTestCase: XCTestCase {
    /// The per-test isolated defaults. Equal to `BookmarkManager.store` for the
    /// duration of the test.
    private(set) var defaults: UserDefaults!

    /// Suite name backing `defaults`; removed in tearDown.
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        // UUID guarantees uniqueness even across parallel worker processes.
        suiteName = "tech.tonalphoto.imageintact.test.\(UUID().uuidString)"
        guard let suite = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Could not create isolated UserDefaults suite: \(suiteName ?? "<nil>")")
        }
        defaults = suite
        BookmarkManager.store = suite
    }

    override func tearDown() async throws {
        // Reset the production seam first so a failed removal can't leave a
        // dead suite wired into BookmarkManager for the next test.
        BookmarkManager.store = .standard
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }
}
