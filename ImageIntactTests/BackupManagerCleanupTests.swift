//
//  BackupManagerCleanupTests.swift
//  ImageIntactTests
//
//  TDD red-phase tests for BackupManager.cleanupMemory bug fixes (AMUX-15).
//
//  References BackupManager init parameter `deferredCleanupDelayNanos` and the
//  new internal `deferredCleanupTask` property — neither exist yet.
//  Compile failure here IS the red-phase signal.
//
//  Design doc: .planning/design/backup-manager-run-backup-extraction.md §"Fixed cleanupMemory"
//

import XCTest
@testable import ImageIntact

// Note: One of the panel-review fixes for AMUX-15 is the removal of two empty
// `autoreleasepool {}` blocks from `cleanupMemory`. There is no test for that
// fix because the change has no observable behavior — empty autoreleasepool
// blocks drain nothing and removing them is pure dead-code cleanup.

@MainActor
final class BackupManagerCleanupTests: BaseBackupManagerTestCase {

    // MARK: - Test fixtures

    var mockFileOps: MockFileOperations!

    override func setUp() async throws {
        try await super.setUp()

        // Clear preferences state (bookmarks already cleared by base class).
        PreferencesManager.shared.resetToDefaults()

        mockFileOps = MockFileOperations()
        // Note: bm is not pre-assigned here — each test assigns self.bm with its own
        // BackupManager (custom deferredCleanupDelayNanos). The base class tearDown will
        // cancel any in-flight backup via self.bm before releasing it.
    }

    override func tearDown() async throws {
        PreferencesManager.shared.resetToDefaults()

        mockFileOps = nil

        // Base class cancels any in-flight backup via self.bm and restores bookmarks.
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Populate failedFiles with a synthetic entry for assertions.
    private func addFailedFile(to bm: BackupManager) {
        bm.failedFiles.append((
            file: "/Volumes/Source/test.jpg",
            destination: "/Volumes/BackupDrive",
            error: "test error"
        ))
    }

    // MARK: - Tests

    /// High fix verification: deferred cleanup runs after the delay when sessionID
    /// hasn't changed.
    func testCleanupMemory_deferredCleanupRunsWhenSessionUnchanged() async throws {
        // 50ms delay — fast enough for tests, slow enough to test the deferred path.
        // deferredCleanupDelayNanos doesn't exist yet; compile failure is expected.
        // Assigned to self.bm so the base class tearDown can cancel any in-flight work.
        self.bm = BackupManager(
            fileOperations: mockFileOps,
            deferredCleanupDelayNanos: 50_000_000  // 50ms
        )

        bm.sessionID = "test-session-abc"
        addFailedFile(to: bm)
        XCTAssertFalse(bm.failedFiles.isEmpty, "Precondition: failedFiles should have an entry")

        bm.cleanupMemory()

        // Synchronous check: failedFiles must NOT be cleared immediately.
        // Without this assertion, the test would pass even if cleanupMemory()
        // mistakenly cleared the array synchronously rather than via the deferred task.
        XCTAssertFalse(bm.failedFiles.isEmpty,
                       "failedFiles must not be cleared synchronously — only by the deferred task")

        // Poll for up to 2s for the deferred task to clear failedFiles.
        // Task.sleep(150ms) is not reliable on loaded CI runners; a 150ms window
        // can easily be exceeded by the scheduler, causing false failures.
        let deadline = Date().addingTimeInterval(2.0)
        while !bm.failedFiles.isEmpty {
            if Date() > deadline {
                XCTFail("Deferred cleanup didn't run within 2s")
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(bm.failedFiles.isEmpty,
                      "failedFiles must be cleared by deferred cleanup when sessionID is unchanged")
    }

    /// High fix verification: deferred cleanup bails when sessionID changes before the delay.
    /// This is the core race-condition fix: a new backup's state is protected.
    func testCleanupMemory_deferredCleanupBailsWhenSessionChanges() async throws {
        // Assigned to self.bm so the base class tearDown can cancel any in-flight work.
        self.bm = BackupManager(
            fileOperations: mockFileOps,
            deferredCleanupDelayNanos: 50_000_000  // 50ms
        )

        bm.sessionID = "session-1"
        addFailedFile(to: bm)

        bm.cleanupMemory()

        // Simulate a new backup starting (sessionID changes) before the delay fires.
        bm.sessionID = "session-2"

        // Wait 1s — long enough that on a loaded CI runner where thread scheduling
        // is delayed, the deferred task would still have plenty of time to run if
        // the sessionID guard weren't working. If it doesn't run by 1s, we have
        // high confidence the guard bailed.
        try await Task.sleep(for: .seconds(1))

        XCTAssertFalse(bm.failedFiles.isEmpty,
                       "failedFiles must NOT be cleared when sessionID changed (deferred task should bail)")
    }

    /// Design doc §"deferredCleanupTask declared internal": second cleanupMemory call
    /// cancels the first deferred task. Relies on `deferredCleanupTask` being `internal`.
    func testCleanupMemory_secondCallCancelsFirstDeferredTask() async {
        // Use 50ms so the first task is still sleeping when we check isCancelled.
        // Assigned to self.bm so the base class tearDown can cancel any in-flight work.
        self.bm = BackupManager(
            fileOperations: mockFileOps,
            deferredCleanupDelayNanos: 50_000_000  // 50ms
        )

        bm.cleanupMemory()
        let firstTask = bm.deferredCleanupTask  // internal property (doesn't exist yet)

        bm.cleanupMemory()

        // Yield to let Task.cancel() propagate.
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(firstTask?.isCancelled ?? false,
                      "The first deferredCleanupTask must be cancelled when cleanupMemory is called again")
    }
}
