// IMPORTANT: These tests mutate `UserDefaults.standard` and `PreferencesManager.shared`.
// They are NOT parallel-safe. If parallel test execution is enabled in the
// Xcode scheme, these tests will overwrite each other's state and fail
// nondeterministically.
//
// Until `PreferencesManager` is refactored behind a protocol with per-test
// in-memory storage (deferred follow-up), keep parallel execution disabled
// in the Xcode test plan for `ImageIntactTests`.

import XCTest
@testable import ImageIntact

/// Shared base class for BackupManager test cases. Centralizes:
/// - `BookmarkManager.sourceKey` / `destinationKeys` capture+restore (prevents
///   the test suite from wiping a developer's saved bookmarks).
/// - Cancellation of any in-flight backup before pref restoration (prevents
///   orphaned Tasks if a test exits early or fails mid-flight).
///
/// Per-test files are still responsible for capturing/restoring any
/// `PreferencesManager.shared.X` values they specifically mutate (e.g.
/// `showPreflightSummary`, `lastUsedOrganizationFolderName`). The base class
/// just handles bookmarks because those are universal.
///
/// Subclasses MUST set `bm` to the BackupManager under test in their setUp
/// (after calling `super.setUp()`) so the teardown cancellation check works.
@MainActor
class BaseBackupManagerTestCase: XCTestCase {
    /// The BackupManager under test. Subclass setUp assigns this so the
    /// base tearDown can cancel any in-flight backup.
    var bm: BackupManager!

    private var savedSourceBookmark: Any?
    private var savedDestinationBookmarks: [String: Any] = [:]

    override func setUp() async throws {
        try await super.setUp()
        // Capture bookmark state BEFORE clearing so we can restore in tearDown.
        savedSourceBookmark = UserDefaults.standard.object(forKey: BookmarkManager.sourceKey)
        savedDestinationBookmarks = [:]
        for key in BookmarkManager.destinationKeys {
            if let v = UserDefaults.standard.object(forKey: key) {
                savedDestinationBookmarks[key] = v
            }
        }
        UserDefaults.standard.removeObject(forKey: BookmarkManager.sourceKey)
        for key in BookmarkManager.destinationKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() async throws {
        // Cancel any in-flight backup before pref restoration, so spawned
        // Tasks (e.g. `performQueueBasedBackup`) don't leak past this test.
        if bm?.state.isProcessing == true {
            bm.cancelOperation()
        }

        // Restore bookmarks. Conditional set-or-remove so absent keys stay absent.
        if let v = savedSourceBookmark {
            UserDefaults.standard.set(v, forKey: BookmarkManager.sourceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: BookmarkManager.sourceKey)
        }
        for key in BookmarkManager.destinationKeys {
            if let v = savedDestinationBookmarks[key] {
                UserDefaults.standard.set(v, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        // Release the BackupManager so its dependency graph deinits between
        // test methods. We do this AFTER the cancellation check above —
        // releasing before that would defeat the safeguard.
        bm = nil

        try await super.tearDown()
    }
}
