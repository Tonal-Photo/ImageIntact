//
//  BackupManagerReentryTests.swift
//  ImageIntactTests
//
//  AMUX-206: cancel-then-restart re-entrancy fix.
//
//  `cancelOperation` flips `state.isProcessing = false` synchronously while the
//  old orchestrator is still spinning down. A user can immediately start a
//  second backup; both runs share the same `progressTracker`, so the dying
//  orchestrator's late writes corrupt the new run's state. The fix makes
//  `runBackup` assign a FRESH ProgressTracker per session, so late writes from
//  the prior orchestrator land on an orphaned instance.
//
//  Red phase (pre-fix: `let progressTracker`): runBackup cannot reassign the
//  tracker, so (a) the instance is unchanged across runs and (b) a late write
//  into the prior instance leaks into the new run. Both fail.
//  Test (c) is a UX regression guard: it passes before AND after the fix,
//  protecting the synchronous `state.isProcessing = false` flip.
//

import XCTest
import Observation
@testable import ImageIntact

@MainActor
final class BackupManagerReentryTests: BaseBackupManagerTestCase {

    private var mockFileOps: MockFileOperations!
    private var mockDiskSpace: MockDiskSpaceChecker!
    private var mockPresenter: MockBackupAlertPresenter!
    private var prefs: InMemoryPreferencesProvider!

    override func setUp() async throws {
        try await super.setUp()

        mockFileOps = MockFileOperations()
        mockDiskSpace = MockDiskSpaceChecker()
        mockPresenter = MockBackupAlertPresenter()
        prefs = InMemoryPreferencesProvider()

        // Disk-space check passes with no warnings, and the preflight modal is
        // skipped, so runBackup clears every guard and reaches its state-setup
        // block — where the fresh-tracker assignment lives.
        mockDiskSpace.evaluationResult = (canProceed: true, warnings: [], errors: [])
        prefs.showPreflightSummary = false

        bm = BackupManager(
            fileOperations: mockFileOps,
            diskSpaceChecker: mockDiskSpace,
            backupAlertPresenter: mockPresenter,
            preferences: prefs
        )
    }

    override func tearDown() async throws {
        prefs = nil
        mockPresenter = nil
        mockDiskSpace = nil
        mockFileOps = nil
        // Base tearDown cancels any in-flight backup before releasing bm.
        try await super.tearDown()
    }

    /// Source + one destination so runBackup clears every guard and reaches the
    /// state-setup block (the fresh-tracker assignment site). Fake file URLs
    /// have no security scope, so the dispatched `performQueueBasedBackup` bails
    /// at its `startAccessingSecurityScopedResource` guard — no real backup work
    /// runs, keeping these tests deterministic.
    private func setUpSourceAndDestination() {
        bm.setSource(URL(fileURLWithPath: "/Volumes/CardA/DCIM"))
        bm.setDestination(URL(fileURLWithPath: "/Volumes/BackupDrive"), at: 0)
    }

    /// (a) runBackup assigns a fresh ProgressTracker; cancelOperation must NOT
    ///     swap it; a restart after cancel assigns another fresh instance.
    func testRunBackupAssignsFreshTracker_andCancelDoesNotSwap() {
        setUpSourceAndDestination()

        let original = bm.progressTracker
        bm.runBackup()
        let firstRun = bm.progressTracker
        XCTAssertFalse(original === firstRun,
                       "runBackup must assign a fresh ProgressTracker, not reuse the prior instance")

        bm.cancelOperation()
        XCTAssertTrue(firstRun === bm.progressTracker,
                      "cancelOperation must NOT swap the tracker (it preserves the cancelled badges)")

        bm.runBackup()
        XCTAssertFalse(firstRun === bm.progressTracker,
                       "a restart after cancel must assign another fresh ProgressTracker")
    }

    /// (b) Bug repro: a dying orchestrator's late write into the prior tracker
    ///     instance must NOT appear on the new run's tracker.
    func testDyingOrchestratorLateWriteDoesNotLeakIntoNewRun() {
        setUpSourceAndDestination()

        bm.runBackup()
        let firstRunTracker = bm.progressTracker   // the instance the first orchestrator captured
        bm.cancelOperation()
        bm.runBackup()                             // fixed: fresh instance; buggy: same instance

        // Simulate the still-spinning-down first orchestrator writing late.
        firstRunTracker.totalFiles = 9999

        XCTAssertEqual(bm.progressTracker.totalFiles, 0,
                       "the new run's tracker must be isolated from the dying orchestrator's late write")
        XCTAssertFalse(firstRunTracker === bm.progressTracker,
                       "the new run must not share the prior run's tracker instance")
    }

    /// (c) UX regression guard: state.isProcessing flips to false synchronously
    ///     inside cancelOperation — the instant 'Backup cancelled' behavior the
    ///     correctness reviewer praised. Passes before and after the fix.
    func testCancelFlipsIsProcessingSynchronously() {
        setUpSourceAndDestination()

        bm.runBackup()
        XCTAssertTrue(bm.state.isProcessing, "runBackup sets isProcessing synchronously")

        bm.cancelOperation()
        XCTAssertFalse(bm.state.isProcessing,
                       "cancelOperation must clear isProcessing synchronously (no await)")
    }

    /// (d) Observation payoff: a reader of `bm.progressTracker.X` is notified
    ///     when the tracker instance is reassigned. SwiftUI's @Observable view
    ///     updates are built on `withObservationTracking`, so this deterministic
    ///     unit-level check proves the user-facing re-render/rebind that the
    ///     fix depends on (ticket step 6) without driving the GUI: a progress
    ///     view reading `bm.progressTracker.totalFiles` re-renders and rebinds
    ///     to the fresh instance when runBackup swaps it.
    func testReassigningTrackerNotifiesObserverReadingThroughBM() {
        var notified = false
        withObservationTracking {
            // Exactly how a progress view reads progress: through bm into the tracker.
            _ = bm.progressTracker.totalFiles
        } onChange: {
            notified = true
        }

        // Reassign the instance only (no field mutation). An observer that read
        // bm.progressTracker.X must be invalidated — i.e. the view re-renders.
        bm.progressTracker = ProgressTracker()

        XCTAssertTrue(notified,
                      "reassigning bm.progressTracker must notify observers reading bm.progressTracker.X (the SwiftUI re-render/rebind trigger)")
    }
}
