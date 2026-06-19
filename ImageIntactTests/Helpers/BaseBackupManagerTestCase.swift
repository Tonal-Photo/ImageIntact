// IMPORTANT: These tests mutate `PreferencesManager.shared`.
// They are NOT parallel-safe for PreferencesManager state. If parallel test
// execution is enabled in the Xcode scheme, pref mutations will overwrite each
// other's state nondeterministically.
//
// Bookmark isolation is handled by IsolatedDefaultsTestCase (the base class).
// Keep parallel execution disabled in the Xcode test plan for `ImageIntactTests`.

import XCTest
@testable import ImageIntact

/// Shared base class for BackupManager test cases. Inherits per-test
/// UserDefaults isolation from `IsolatedDefaultsTestCase` (bookmark keys are
/// in a fresh suite for each test; `BookmarkManager.store` is pointed there
/// automatically). Centralizes:
/// - Cancellation of any in-flight backup before teardown (prevents orphaned
///   Tasks if a test exits early or fails mid-flight).
///
/// Per-test files are still responsible for capturing/restoring any
/// `PreferencesManager.shared.X` values they specifically mutate (e.g.
/// `showPreflightSummary`, `lastUsedOrganizationFolderName`).
///
/// Subclasses MUST set `bm` to the BackupManager under test in their setUp
/// (after calling `super.setUp()`) so the teardown cancellation check works.
@MainActor
class BaseBackupManagerTestCase: IsolatedDefaultsTestCase {
    /// The BackupManager under test. Subclass setUp assigns this so the
    /// base tearDown can cancel any in-flight backup.
    var bm: BackupManager!

    override func setUp() async throws {
        try await super.setUp()
        // Bookmark isolation is handled by IsolatedDefaultsTestCase.
        // Subclasses add their own setup after this call.
    }

    override func tearDown() async throws {
        // Cancel any in-flight backup before isolation teardown, so spawned
        // Tasks (e.g. `performQueueBasedBackup`) don't leak past this test.
        if bm?.state.isProcessing == true {
            bm.cancelOperation()
        }

        // Release the BackupManager so its dependency graph deinits between
        // test methods. We do this AFTER the cancellation check above —
        // releasing before that would defeat the safeguard.
        bm = nil

        try await super.tearDown()
    }
}
