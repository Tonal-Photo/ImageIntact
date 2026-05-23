//
//  BackupManagerCancelTests.swift
//  ImageIntactTests
//
//  TDD red-phase tests for BackupManager.cancelOperation bug fixes (AMUX-15).
//
//  These tests reference MockBackupOrchestrator (which wraps the new subclass approach)
//  and the new synchronous isProcessing-clear behavior. Compile failure on symbols
//  that don't yet exist IS the red-phase signal.
//
//  Design doc: .planning/design/backup-manager-run-backup-extraction.md §"Fixed cancelOperation"
//

import XCTest
@testable import ImageIntact

@MainActor
final class BackupManagerCancelTests: BaseBackupManagerTestCase {

    // MARK: - Test fixtures

    var mockFileOps: MockFileOperations!

    override func setUp() async throws {
        try await super.setUp()

        // Clear preferences state (bookmarks already cleared by base class).
        PreferencesManager.shared.resetToDefaults()

        mockFileOps = MockFileOperations()
        bm = BackupManager(fileOperations: mockFileOps)
    }

    override func tearDown() async throws {
        PreferencesManager.shared.resetToDefaults()

        mockFileOps = nil

        // Base class cancels any in-flight backup (reads self.bm before releasing it)
        // and restores bookmarks. bm is released naturally when the test instance deinits.
        try await super.tearDown()
    }

    // MARK: - Tests

    /// Blocker fix verification: orchestrator.cancel() must be called SYNCHRONOUSLY
    /// (before cleanupMemory nils currentOrchestrator). With the buggy code, the
    /// cancel was scheduled in a Task — this test asserts the count without any
    /// Task.yield, so it would be 0 with the old code.
    func testCancelOperation_cancelsOrchestratorBeforeNil() {
        let mockOrch = MockBackupOrchestrator()
        bm.currentOrchestrator = mockOrch
        bm.isProcessing = true

        bm.cancelOperation()

        // Synchronous assertion — no yield, no wait.
        XCTAssertEqual(mockOrch.cancelCallCount, 1,
                       "orchestrator.cancel() must be called synchronously before cleanupMemory nils it")
    }

    /// AMUX-210: cancelled-state badges must persist after cancelOperation
    /// returns. Previously they were set then immediately wiped by resetAll().
    func testCancelOperation_cancelledStatePersists() {
        bm.isProcessing = true
        bm.progressTracker.setDestinationProgress(50, for: "/Volumes/BackupDrive")

        bm.cancelOperation()

        XCTAssertEqual(bm.progressTracker.destinationStates["/Volumes/BackupDrive"], "cancelled",
                       "cancelled state must persist after cancelOperation")
        XCTAssertEqual(bm.progressTracker.destinationProgress["/Volumes/BackupDrive"], 0,
                       "progress for cancelled destination must be zeroed")
    }

    /// shouldCancel guard: second cancelOperation call is ignored.
    func testCancelOperation_doubleCallIgnored() {
        let mockOrch = MockBackupOrchestrator()
        bm.currentOrchestrator = mockOrch
        bm.isProcessing = true

        bm.cancelOperation()
        bm.cancelOperation()

        XCTAssertEqual(mockOrch.cancelCallCount, 1,
                       "Second cancelOperation call must be ignored by shouldCancel guard")
    }

    /// Medium fix verification: isProcessing must be cleared SYNCHRONOUSLY, not inside
    /// a Task. With the old code (isProcessing = false inside a Task), this assertion
    /// would fail because the Task hasn't run yet.
    func testCancelOperation_isProcessingFalseSynchronously() {
        bm.isProcessing = true

        bm.cancelOperation()

        // Immediate assertion — no Task.yield, no await.
        XCTAssertFalse(bm.isProcessing,
                       "isProcessing must be set to false synchronously in cancelOperation (not inside a Task)")
    }

    /// Existing behavior preserved: a pending largeBackupContinuation is resumed
    /// with false and cleared when cancelOperation is called.
    func testCancelOperation_clearsLargeBackupContinuation() async {
        // Set up a continuation that we can observe.
        var continuationResult: Bool? = nil

        // Spawn a task that suspends on a continuation and captures the result.
        let awaitingTask = Task { @MainActor in
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                bm.largeBackupContinuation = continuation
                bm.showLargeBackupConfirmation = true
            }
        }

        // Poll until the child task sets the continuation, with a 2s timeout.
        // Task.yield() alone doesn't guarantee the child task advances far enough
        // to reach the withCheckedContinuation suspension and assign the property.
        // Without this guard, cancelOperation() could fire before the continuation
        // is set, do nothing, and then `await awaitingTask.value` hangs forever.
        let deadline = Date().addingTimeInterval(2.0)
        while bm.largeBackupContinuation == nil {
            if Date() > deadline {
                XCTFail("largeBackupContinuation never got set within 2s")
                return
            }
            await Task.yield()
        }

        bm.isProcessing = true
        bm.cancelOperation()

        // Collect the result the continuation was resumed with.
        continuationResult = await awaitingTask.value

        XCTAssertEqual(continuationResult, false,
                       "Continuation must be resumed with false on cancellation")
        XCTAssertNil(bm.largeBackupContinuation,
                     "largeBackupContinuation must be nil after cancelOperation")
        XCTAssertFalse(bm.showLargeBackupConfirmation,
                       "showLargeBackupConfirmation must be false after cancelOperation")
    }
}
