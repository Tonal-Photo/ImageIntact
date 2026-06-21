//
//  BackupStatisticsRerunTests.swift
//  ImageIntactTests
//
//  TDD red-phase tests for AMUX-488: post-cancel rerun zeroing global completion stats.
//
//  References a NEW `cleanupMemory(expectedSessionID:)` parameter that does not exist
//  yet. The compile failure here IS the red-phase signal (same precedent as
//  BackupManagerCleanupTests.swift:9).
//
//  Root cause (see .planning/design/backup-manager-post-cancel-stats.md):
//  a prior (cancelled) backup's 3s-deferred cleanupMemory() fires DURING the rerun,
//  captures the rerun's sessionID, and ~10s later resetAll()s the LIVE progressTracker
//  mid-copy. The monitor loop re-fills destinationProgress (per-dest stays correct) but
//  totalFiles is set only once (BackupOrchestrator:288) and is not re-set, so
//  processedFiles = min(maxCompleted, 0) = 0 and the completion sheet shows 0/0 inSource.
//
//  The fix lets the scheduling backup PIN its session; cleanupMemory bails when that
//  pinned session is no longer current.
//

import XCTest
@testable import ImageIntact

@MainActor
final class BackupStatisticsRerunTests: BaseBackupManagerTestCase {

    // MARK: - Test fixtures

    var mockFileOps: MockFileOperations!

    override func setUp() async throws {
        try await super.setUp()
        mockFileOps = MockFileOperations()
        // self.bm is assigned per-test with its own deferredCleanupDelayNanos so the
        // base tearDown can cancel any in-flight work.
    }

    override func tearDown() async throws {
        mockFileOps = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Populate a tracker + statistics as a live, mid/just-completed rerun would:
    /// global counters set, plus per-destination progress (which is correct in the bug).
    private func populateLiveRunState(on bm: BackupManager, files: Int) {
        bm.progressTracker.totalFiles = files
        bm.progressTracker.processedFiles = files
        bm.progressTracker.destinationProgress["dest1"] = files
        bm.statistics.totalFilesInSource = files
        bm.statistics.totalFilesProcessed = files
    }

    // MARK: - Tests

    /// AMUX-488 core: a deferred cleanup scheduled by a PRIOR (cancelled) backup must not
    /// wipe the live rerun's global counters, even though the cleanupMemory CALL happens
    /// during the new session (the 3s defer delays it past the rerun's start). The prior
    /// backup pins its own sessionID; cleanupMemory must bail when it no longer matches.
    func testStaleDeferredCleanupFromPriorSession_doesNotZeroLiveGlobalCounters() async throws {
        self.bm = BackupManager(
            fileOperations: mockFileOps,
            preferences: InMemoryPreferencesProvider(),
            deferredCleanupDelayNanos: 50_000_000  // 50ms
        )

        // Live rerun session with populated counts, as orchestrator:288/539 + populateStatistics set them.
        bm.state.sessionID = "rerun-session"
        populateLiveRunState(on: bm, files: 6)

        // The prior (cancelled) backup's deferred cleanup fires now, pinned to its OWN
        // (old) session. New `expectedSessionID:` parameter — compile failure on current
        // code is the red signal.
        bm.cleanupMemory(expectedSessionID: "prior-cancelled-session")

        // Wait well past the 50ms deferred delay so a non-bailing implementation would
        // have wiped the tracker by now.
        try await Task.sleep(for: .seconds(1))

        // The live counters must survive — this is the AMUX-488 bug (they read 0/0).
        XCTAssertEqual(bm.progressTracker.totalFiles, 6,
                       "stale deferred cleanup wiped the live run's progressTracker.totalFiles")
        XCTAssertEqual(bm.progressTracker.processedFiles, 6,
                       "stale deferred cleanup wiped the live run's progressTracker.processedFiles")
        XCTAssertEqual(bm.statistics.totalFilesInSource, 6,
                       "stale deferred cleanup wiped the live run's statistics.totalFilesInSource")
        XCTAssertEqual(bm.statistics.totalFilesProcessed, 6,
                       "stale deferred cleanup wiped the live run's statistics.totalFilesProcessed")
        // Per-destination aggregation is out of scope and should never have been touched.
        XCTAssertEqual(bm.progressTracker.destinationProgress["dest1"], 6,
                       "per-destination progress must be unaffected")
    }

    /// Regression: when the pinned session matches the live session, the deferred cleanup
    /// STILL runs — the AMUX-488 guard must not neuter legitimate cleanup.
    func testMatchingSessionDeferredCleanup_stillRuns() async throws {
        self.bm = BackupManager(
            fileOperations: mockFileOps,
            preferences: InMemoryPreferencesProvider(),
            deferredCleanupDelayNanos: 50_000_000  // 50ms
        )

        bm.state.sessionID = "live-session"
        populateLiveRunState(on: bm, files: 6)
        bm.state.failedFiles.append((
            file: "/Volumes/Source/test.jpg",
            destination: "/Volumes/BackupDrive",
            error: "test error"
        ))

        // Cleanup pinned to the CURRENT session — should proceed and run the deferred task.
        bm.cleanupMemory(expectedSessionID: "live-session")

        // Poll up to 2s for the deferred task to clear failedFiles (proof it ran).
        let deadline = Date().addingTimeInterval(2.0)
        while !bm.state.failedFiles.isEmpty {
            if Date() > deadline {
                XCTFail("Deferred cleanup didn't run within 2s for a matching pinned session")
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(bm.state.failedFiles.isEmpty,
                      "matching-session deferred cleanup must still clear failedFiles")
    }
}
